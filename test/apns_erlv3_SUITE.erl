%%% Purpose: Test suite for the 'apns_erlv3' module.
%%%-----------------------------------------------------------------
-module(apns_erlv3_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("lager/include/lager.hrl").
-include("apns_erlv3_defs.hrl").

-compile(export_all).
-compile({parse_transform, test_generator}).

-import(apns_erlv3_test_support,
        [set_props/2, set_prop/2, check_parsed_resp/2, end_group/1,
         fix_all_cert_paths/2, format_str/2, format_bin/2, bin_prop/2,
         rand_push_tok/0, gen_uuid/0, make_nf/1, make_nf/2, make_api_nf/2,
         maybe_prop/2, maybe_plist/2, plist/3, send_fun/4, send_fun_nf/4,
         gen_send_fun/4, send_funs/2, check_match/2, sim_nf_fun/2,
         fix_simulator_cert_paths/2, for_all_sessions/2, is_uuid/1,
         reason_list/0, start_group/2, start_session/2, start_simulator/4,
         stop_session/3, str_to_uuid/1, to_bin_prop/2, value/2, value/3,
         wait_until_sim_active/1]).

%% These tests are expanded using test_generator.erl's
%% parse transform into tests for sync & async, session & api
-expand_test([
              clear_badge_test/1,
              send_msg_test/1,
              send_msg_sound_badge_test/1,
              send_msg_with_alert_proplist/1,
              send_msg_while_reconnecting/1,
              send_expired_msg_while_reconnecting/1,
              bad_token/1,
              unregistered_token/1,
              bad_in_general/1,
              bad_nf_format/1,
              bad_nf_backend/1
             ]).

-record(nf_info, {session_name, token, uuid}).

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
suite() -> [{timetrap, {seconds, 30}}].

%%--------------------------------------------------------------------
all() ->
    [
     {group, session_control},
     {group, code_coverage},
     {group, debug_functions},
     {group, positive_send_notification_tests},
     {group, negative_send_notification_tests},
     {group, quiesce_and_resume},
     {group, recovery_under_stress},
     {group, http2_settings}
    ].

%%--------------------------------------------------------------------
groups() ->
    [
     {session_control, [], [
                            start_stop_session_direct_test,
                            start_stop_session_test,
                            crash_session_startup_test
                           ]
     },
     {quiesce_and_resume, [], [
                               quiesce_and_send,
                               quiesce_reconnect_and_send,
                               resume_and_send
                              ]
     },
     {code_coverage, [], [
                          invalid_event_test,
                          unknown_process_died_test,
                          unexpected_message_test,
                          disconnect_disconnected_test,
                          validation_tests,
                          cert_validation_test
                         ]
     },
     {debug_functions, [], [
                            get_state_test,
                            get_state_name_test,
                            reconnect_test
                           ]
     },

     {positive_send_notification_tests, [],
      clear_badge_test(suite) ++
      send_msg_test(suite) ++
      send_msg_sound_badge_test(suite) ++
      send_msg_with_alert_proplist(suite) ++
      send_msg_while_reconnecting(suite) ++
      send_expired_msg_while_reconnecting(suite) ++
      [async_session_send_user_callback,
       async_api_send_user_callback]
     },

     {negative_send_notification_tests, [],
      bad_token(suite) ++
      unregistered_token(suite) ++
      bad_in_general(suite) ++
      bad_nf_format(suite) ++
      bad_nf_backend(suite)
     },

     {recovery_under_stress, [], [
                                  async_flood_and_disconnect
                                 ]
     },
     {http2_settings, [], [
                           concurrent_stream_limits_test
                          ]
     }
    ].

%%--------------------------------------------------------------------
init_per_suite(Config) ->
    ct:pal("Entering init_per_suite; config: ~p", [Config]),
    ct:pal("My Erlang node name is ~p", [node()]),

    ok = ct:require(test_mode),
    ok = ct:require(flood_test_messages),
    ok = ct:require(sessions),
    ok = ct:require(simulator_config),
    ok = ct:require(simulator_logging),
    ok = ct:require(sim_node_name),
    ok = ct:require(valid_cert),
    ok = ct:require(lager),
    ok = ct:require(lager_common_test_backend),

    application:load(lager),
    [application:set_env(lager, Key, Val) || {Key, Val} <- ct:get_config(lager)],
    lager:start(),

    TestMode = ct:get_config(test_mode),
    ?assert(TestMode == http orelse TestMode == https),

    FloodTestMessages = ct:get_config(flood_test_messages),
    ct:pal("flood_test_messages = ~p", [FloodTestMessages ]),
    ?assert(is_integer(FloodTestMessages) andalso FloodTestMessages > 0),

    % ct:get_config(sessions) -> [Session].
    DataDir = ?config(data_dir, Config),
    ct:pal("Data directory is ~s", [DataDir]),
    set_mnesia_dir(DataDir),

    PrivDir = ?config(priv_dir, Config),
    ct:pal("Private directory is ~s", [PrivDir]),

    Sessions0 = ct:get_config(sessions),
    true = is_list(Sessions0),
    ct:pal("Raw sessions: ~p", [Sessions0]),

    Sessions = case TestMode of
                   https ->
                       Fixed = fix_all_cert_paths(DataDir, Sessions0),
                       set_session_protocols(h2, Fixed);
                   http ->
                       set_session_protocols(h2c, Sessions0)
               end,
    ct:pal("Adjusted sessions: ~p", [Sessions]),

    {StartedApps, SimNode, SimConfig} = maybe_start_sim_node(DataDir,
                                                             PrivDir,
                                                             TestMode),

    ValidCertCfg = case TestMode of
                       https ->
                           ValidCertCfg0 = ct:get_config(valid_cert),
                           ct:pal("Raw valid cert config: ~p", [ValidCertCfg0]),
                           [VCC] = fix_all_cert_paths(DataDir, [ValidCertCfg0]),
                           VCC;
                       http ->
                           []
                   end,
    ct:pal("Adjusted cert config: ~p", [ValidCertCfg]),

    LagerCTBackend = ct:get_config(lager_common_test_backend),
    Config ++ [{test_mode, TestMode},
               {flood_test_messages, FloodTestMessages},
               {sessions, Sessions},
               {sim_node_name, SimNode},
               {simulator_config, SimConfig},
               {sim_started_apps, StartedApps},
               {valid_cert, ValidCertCfg},
               {lager_common_test_backend, LagerCTBackend}].

%%--------------------------------------------------------------------
end_per_suite(Config) ->
    Config.

%%--------------------------------------------------------------------
init_per_group(pre_started_session, Config) ->
    Sessions = ?sessions(Config),
    SessionStarter = fun() -> apns_erlv3_session_sup:start_link(Sessions) end,
    start_group(SessionStarter, Config);
init_per_group(recovery_under_stress, Config) ->
    Sessions = fix_sessions(?sessions(Config), [{flush_strategy, on_reconnect},
                                                {requeue_strategy, always}]),
    ct:pal("Fixed sessions:\n~p", [Sessions]),
    SessionStarter = fun() -> apns_erlv3_session_sup:start_link(Sessions) end,
    start_group(SessionStarter, Config);
init_per_group(GroupName, Config) ->
    ct:pal("Group Name: ~p", [GroupName]),
    SessionStarter = fun() -> apns_erlv3_session_sup:start_link([]) end,
    start_group(SessionStarter, Config).

%%--------------------------------------------------------------------
end_per_group(pre_started_session, Config) ->
    Config;
end_per_group(recovery_under_stress, Config) ->
    Config;
end_per_group(_GroupName, Config) ->
    end_group(Config).

%%--------------------------------------------------------------------
init_per_testcase(Case = start_stop_session_direct_test, Config) ->
    init_testcase(Case, Config, fun apns_erlv3_session:start/2);
init_per_testcase(crash_session_startup_test, Config) ->
    Config;
init_per_testcase(validation_tests, Config) ->
    Config;
init_per_testcase(cert_validation_test, Config) ->
    Config;
init_per_testcase(Case, Config) ->
    init_testcase(Case, Config, fun sc_push_svc_apnsv3:start_session/2).

%%--------------------------------------------------------------------
end_per_testcase(Case = start_stop_session_direct_test, Config) ->
    StopFun = fun({_Name, Pid, _Ref}) ->
                      apns_erlv3_session:stop(Pid)
              end,
    end_testcase(Case, Config, StopFun);
end_per_testcase(crash_session_startup_test, Config) ->
    Config;
end_per_testcase(validation_tests, Config) ->
    Config;
end_per_testcase(cert_validation_test, Config) ->
    Config;
end_per_testcase(Case, Config) ->
    StopFun = fun({Name, _Pid, _Ref}) ->
                      sc_push_svc_apnsv3:stop_session(Name)
              end,
    end_testcase(Case, Config, StopFun).

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Group: session
%%--------------------------------------------------------------------
start_stop_session_direct_test(doc) ->
    ["Start and stop a session using start/1."];
start_stop_session_direct_test(_Config) ->
    %% This is all done using init/end_per_testcase
    ok.

%%--------------------------------------------------------------------
start_stop_session_test(doc) ->
    ["Start and stop a named session."];
start_stop_session_test(_Config) ->
    %% This is all done using init/end_per_testcase
    ok.

%%--------------------------------------------------------------------
crash_session_startup_test(doc) ->
    ["Crash a session by starting it badly."];
crash_session_startup_test(_Config) ->
    ct:pal("Expecting crash when starting session with empty opts"),
    ?assertMatch({error, {{key_not_found, _Key}, _StackTrace}},
                 apns_erlv3_session:start(dummy, [])).

%%--------------------------------------------------------------------
%% Group: debug_functions
%%--------------------------------------------------------------------
get_state_test(doc) ->
    ["apns_erlv3_session:get_state/1 should return the session state"];
get_state_test(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                ct:pal("Getting session state from session ~p", [Name]),
                Resp = apns_erlv3_session:get_state(Name),
                ct:pal("Got response ~p", [Resp]),
                ?assertMatch({ok, _}, Resp),
                {ok, State} = Resp,
                true = is_tuple(State) andalso tuple_size(State) > 1,
                apns_erlv3_session = element(1, State)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
get_state_name_test(doc) ->
    ["apns_erlv3_session:get_state_name/1 should return the "
     "session state name"];
get_state_name_test(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                ct:pal("Getting session state name from session ~p", [Name]),
                Resp = apns_erlv3_session:get_state_name(Name),
                ct:pal("Got response ~p", [Resp]),
                ?assertMatch({ok, _}, Resp),
                {ok, StateName} = Resp,
                ct:pal("State name = ~p", [StateName]),
                true = is_atom(StateName)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
reconnect_test(doc) -> ["Test reconnect/1 debug function"];
reconnect_test(Config) when is_list(Config)  ->
    F = fun(Session) ->
                Name = ?name(Session),
                ct:pal("Forcing sync reconnect of session ~p", [Name]),
                ok = apns_erlv3_session:sync_reconnect(Name),
                {ok, StateName} = apns_erlv3_session:get_state_name(Name),
                ct:pal("Session ~p state is ~p", [Name, StateName]),
                ?assertEqual(connected, StateName)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
%% Group: code_coverage
%%--------------------------------------------------------------------
invalid_event_test(doc) -> ["Invalid event should return error"];
invalid_event_test(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                case whereis(Name) of
                    Pid when is_pid(Pid) ->
                        Res = gen_fsm:sync_send_all_state_event(Pid, junk),
                        ?assert(Res =:= {error, invalid_event}),
                        %% And exercise the async code also
                        ok = gen_fsm:send_all_state_event(Pid, junk);
                    _ ->
                        ct:fail("Session ~p not found", [Name])
                end
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
unknown_process_died_test(doc) -> ["Exercise unknown process exit code"];
unknown_process_died_test(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                case whereis(Name) of
                    Pid when is_pid(Pid) ->
                        FakePid = spawn(fun() -> ok end),
                        FakeExit = {'EXIT', FakePid, common_test},
                        Pid ! FakeExit;
                    _ ->
                        ct:fail("Session ~p not found", [Name])
                end
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
unexpected_message_test(doc) -> ["Exercise unexpected message code"];
unexpected_message_test(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                case whereis(Name) of
                    Pid when is_pid(Pid) ->
                        Pid ! an_unexpected_message;
                    _ ->
                        ct:fail("Session ~p not found", [Name])
                end
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
disconnect_disconnected_test(doc) ->
    ["Exercise handling disconnect while disconnected"];
disconnect_disconnected_test(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                ct:pal("Forcing back-to-back reconnect of session ~p", [Name]),
                ok = apns_erlv3_session:reconnect(Name),
                ok = apns_erlv3_session:reconnect(Name)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
validation_tests(doc) -> ["Exercise private validation functions"];
validation_tests(Config) ->
    ?assertEqual(apns_erlv3_session:validate_boolean({test, true}), true),
    ?assertEqual(apns_erlv3_session:validate_boolean({test, false}), false),
    ?assertThrow({bad_options, {not_a_boolean, test}},
                  apns_erlv3_session:validate_boolean({test, 1})),

    ValidValues = [a, b, c, d, e],
    ?assertEqual(apns_erlv3_session:validate_enum({t_a, a}, ValidValues), a),
    ?assertThrow({bad_options,
                  {invalid_enum,
                   {name, t_x},
                   {value, x},
                   {valid_values, ValidValues}}},
                 apns_erlv3_session:validate_enum({t_x, x}, ValidValues)),

    ?assertEqual(apns_erlv3_session:validate_list({t_l, [a]}), [a]),
    ?assertThrow({bad_options, {not_a_list, t_l}},
                 apns_erlv3_session:validate_list({t_l, 0})),

    ?assertEqual(apns_erlv3_session:validate_binary({t_b, <<>>}), <<>>),
    ?assertThrow({bad_options, {not_a_binary, t_b}},
                  apns_erlv3_session:validate_binary({t_b, 1})),

    ?assertEqual(apns_erlv3_session:validate_integer({t_i, -1}), -1),
    ?assertThrow({bad_options, {not_an_integer, t_i}},
                  apns_erlv3_session:validate_integer({t_i, 1.0})),

    ?assertEqual(apns_erlv3_session:validate_non_neg({t_n, 1}), 1),
    ?assertThrow({bad_options, {not_an_integer, t_n}},
                  apns_erlv3_session:validate_non_neg({t_n, 1.0})),
    ?assertThrow({bad_options, {negative_integer, t_n}},
                  apns_erlv3_session:validate_non_neg({t_n, -1}))<
    Config.

%%--------------------------------------------------------------------
cert_validation_test(doc) -> ["Exercise cert validation"];
cert_validation_test(Config) ->
    case value(test_mode, Config) of
        https ->
            ct:pal("Test startup with valid push certs~n"),
            ValidCertCfg = value(valid_cert, Config),
            {ok, {Pid, _Ref}} = start_session(ValidCertCfg,
                                              fun apns_erlv3_session:start/2),
            apns_erlv3_session:stop(Pid);
        http ->
            {skip, {test_mode, http}}
    end.

%%--------------------------------------------------------------------
%% Tests that will be parse transformed
%%--------------------------------------------------------------------
clear_badge_test(doc) -> ["Clear the badge count"];
clear_badge_test(Config) ->
    %% Note special parse transform syntax; apnsv3_test_gen
    %% does not exist.
    F = apnsv3_test_gen:send_fun(#{badge => 0}, success),
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
send_msg_test(doc) -> ["Send a message to APNS"];
send_msg_test(Config) ->
    F = apnsv3_test_gen:send_fun(#{alert => <<"Hello, APNS!">>,
                                   badge => 1}, success),
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
send_msg_sound_badge_test(doc) ->
    ["Send a message, sound, and badge to APNS"];
send_msg_sound_badge_test(Config) ->
    Map = #{alert => <<"Hi, would you like to play a game?">>,
            badge => 3,
            sound => <<"wopr">>},
    F = apnsv3_test_gen:send_fun(Map, success),
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
send_msg_with_alert_proplist(doc) ->
    ["sc_push_svc_apnsv3:send/2 should send a message to APNS"];
send_msg_with_alert_proplist(Config) ->
    MakeNfFun = fun(Session) ->
                        Alert = format_bin("Testing svr '%n' with alert dict",
                                           Session),
                        JSON = jsx:encode([{aps, [{alert, [{body, Alert}]},
                                                  {badge, 4}]
                                           }]),
                        Nf = [
                              {token, ?token(Session)},
                              {json, JSON}
                             ],
                        {Nf, ?name(Session)}
                end,
    F = apnsv3_test_gen:send_fun_nf(success, MakeNfFun),
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
send_msg_while_reconnecting(doc) -> ["Send while SCPF is reconnecting"];
send_msg_while_reconnecting(Config) ->
    SendFun = apnsv3_test_gen:send_fun(#{badge => 5}, success),
    F = fun(Session) ->
                Name = ?name(Session),
                ct:pal("Forcing reconnect of session ~p with delay", [Name]),
                ok = apns_erlv3_session:reconnect(Name, 1000),
                SendFun(Session)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
send_expired_msg_while_reconnecting(doc) ->
    ["Return an error if sending an expired ",
     "message while SCPF is reconnecting"];
send_expired_msg_while_reconnecting(Config) ->
    MakeNfFun = fun(Session) ->
                        ExpiresAt = erlang:system_time(seconds) + 1,
                        make_nf(Session, #{badge => 6, expiry => ExpiresAt})
                end,
    CheckFun = fun(Resp) -> ?assertMatch({error, {_, expired}}, Resp) end,
    SendFun = apnsv3_test_gen:send_fun_nf(CheckFun, MakeNfFun),
    F = fun(Session) ->
                Name = ?name(Session),
                ct:pal("Forcing reconnect of session ~p with delay", [Name]),
                ok = apns_erlv3_session:reconnect(Name, 1000),
                ct:pal("Sending expired notification session ~p", [Name]),
                SendFun(Session)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
%% Group: unhappy_path
%%--------------------------------------------------------------------

bad_token(doc) -> ["send should handle BadDeviceToken properly"];
bad_token(Config) when is_list(Config)  ->
    NfFun = sim_nf_fun(#{token => <<"foobar">>},
                       #{reason => <<"BadDeviceToken">>}),
    F = apnsv3_test_gen:send_fun_nf(<<"400">>, NfFun),
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------

unregistered_token(doc) -> ["send should handle Unregistered properly"];
unregistered_token(Config) when is_list(Config)  ->
    SC = <<"410">>,
    NfFun = sim_nf_fun(#{}, #{reason => <<"Unregistered">>,
                              status_code => SC}),
    F = apnsv3_test_gen:send_fun_nf(SC, NfFun),
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
bad_in_general(doc) -> ["Handle all APNS HTTP/2 reason responses"];
bad_in_general(Config) ->
    _ = [begin
             SimNfFun = sim_nf_fun(#{}, #{reason => Reason}),
             SendFun = apnsv3_test_gen:send_fun_nf(failure, SimNfFun),
             wait_until_session_in_connected_state(Session),
             SendFun(Session)
         end || Reason <- reason_list(), Session <- ?sessions(Config)].

%%--------------------------------------------------------------------
bad_nf_format(doc) -> ["Ensure bad nf proplist is handled correctly"];
bad_nf_format(Config) when is_list(Config)  ->
    BadNfs = [
              {[],
               "Expecting '{key_not_found, token}' error"},
              [{{token, rand_push_tok()},
                "Expecting '{not_a_binary, token}' error"}]
             ],
    F = fun(Session) ->
                Name = ?name(Session),
                CheckFun = fun(Resp) ->
                                   ?assertMatch({error, {bad_notification, _}},
                                                Resp)
                           end,
                [begin
                     NfFun = fun(_) -> {Nf, Name} end,
                     SendFun = apnsv3_test_gen:send_fun_nf(CheckFun, NfFun),
                     ct:pal("~s", [DebugMsg]),
                     SendFun(Session)
                 end || {Nf, DebugMsg} <- BadNfs]
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
bad_nf_backend(doc) -> ["Ensure backend errors are handled correctly"];
bad_nf_backend(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                UUIDStr = gen_uuid(),
                UUID = str_to_uuid(UUIDStr),
                Nf = [
                      {uuid, UUIDStr},
                      {alert, <<"Should be bad topic">>},
                      {token, sc_util:to_bin(rand_push_tok())},
                      {topic, <<"Some BS Topic">>}
                     ],

                ct:pal("Sending notification via API: ~p", [Nf]),
                {ok, {UUID, PResp}} = sc_push_svc_apnsv3:send(Name, Nf),
                ct:pal("Sent notification via API, Resp = ~p", [PResp]),
                CheckFun = fun(Status) ->
                                   ?assertEqual(?pstatus(PResp), Status),
                                   ?assertEqual(?preason(PResp), <<"BadTopic">>)
                           end,
                check_parsed_resp(PResp, CheckFun)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
%% Group: quiesce_and_resume
%%--------------------------------------------------------------------
quiesce_and_send(doc) ->
    ["Test sending to a quiesced session"];
quiesce_and_send(Config) when is_list(Config)  ->
    F = fun(Session) ->
                {Nf, Name} = make_nf(Session),
                ct:pal("Quiescing server ~p", [Name]),
                Resp = apns_erlv3_session:quiesce(Name),
                ct:pal("Quiesced resp = ~p", [Resp]),
                ok = Resp,
                ct:pal("Sending notification via session ~p, Nf = ~p",
                       [Name, Nf]),
                {error, quiesced} = apns_erlv3_session:send(Name, Nf)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
quiesce_reconnect_and_send(doc) ->
    ["Test sending to a quiesced session while it is reconnecting"];
quiesce_reconnect_and_send(Config) when is_list(Config)  ->
    F = fun(Session) ->
                {Nf, Name} = make_nf(Session),
                ct:pal("Quiescing server ~p", [Name]),
                Resp = apns_erlv3_session:quiesce(Name),
                ct:pal("Quiesced resp = ~p", [Resp]),
                ok = Resp,
                ct:pal("Forcing reconnect of session ~p with delay", [Name]),
                ok = apns_erlv3_session:reconnect(Name, 1000),
                ct:pal("Sending notification via session ~p, Nf = ~p",
                       [Name, Nf]),
                {error, quiesced} = apns_erlv3_session:send(Name, Nf)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
resume_and_send(doc) ->
    ["Test sending to a resumed session"];
resume_and_send(Config) when is_list(Config)  ->
    F = fun(Session) ->
                {Nf, Name} = make_nf(Session),
                ct:pal("Quiescing server ~p", [Name]),
                ok = apns_erlv3_session:quiesce(Name),

                ct:pal("Expecting quiesced error, session ~p, Nf = ~p",
                       [Name, Nf]),
                {error, quiesced} = apns_erlv3_session:send(Name, Nf),

                ct:pal("Resuming server ~p", [Name]),
                ok = apns_erlv3_session:resume(Name),

                ct:pal("Sending via resumed session ~p, Nf = ~p", [Name, Nf]),
                {ok, {_UUID, ParsedResp}} = apns_erlv3_session:send(Name, Nf),
                ct:pal("Sent notification, Resp = ~p", [ParsedResp]),
                check_parsed_resp(ParsedResp, success)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
async_session_send_user_callback(doc) ->
    ["Test async session send with user callback"];
async_session_send_user_callback(Config) ->
    Cb = async_user_callback_fun(),
    F = fun(Session) ->
                Name = ?name(Session),
                UUIDStr = gen_uuid(),
                UUID = str_to_uuid(UUIDStr),
                APS = [{aps, [{alert, <<"Testing async user callback">>},
                              {'content-available', 1}
                             ]}],
                Nf = [
                      {uuid, UUIDStr},
                      {token, sc_util:to_bin(rand_push_tok())},
                      {topic, <<"com.example.FakeApp.voip">>},
                      {json, jsx:encode(APS)}
                     ],

                From = self(),
                Result = apns_erlv3_session:async_send_cb(Name, From, Nf, Cb),
                ct:pal("Sent notification via session ~p, Result = ~p",
                       [Session, Result]),
                {ok, {_Status, RUUID}} = Result,
                ?assertEqual(RUUID, UUID),
                async_receive_user_cb(UUIDStr)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
async_api_send_user_callback(doc) ->
    ["Test async api send with user callback"];
async_api_send_user_callback(Config) ->
    Cb = async_user_callback_fun(),
    F = fun(Session) ->
                Name = ?name(Session),
                UUIDStr = gen_uuid(),
                UUID = str_to_uuid(UUIDStr),
                Nf = [{alert, <<"Testing async api user callback">>},
                      {uuid, UUIDStr},
                      {token, sc_util:to_bin(rand_push_tok())},
                      {topic, <<"com.example.FakeApp.voip">>}
                     ],

                Opts = [{from_pid, self()}, {callback, Cb}],
                Result = sc_push_svc_apnsv3:async_send(Name, Nf, Opts),
                ct:pal("Sent notification via session ~p, Result = ~p",
                       [Name, Result]),
                {ok, {Status, RUUID}} = Result,
                ?assert(Status =:= queued orelse Status =:= submitted),
                ?assertEqual(RUUID, UUID),
                async_receive_user_cb(UUIDStr)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
%% Group: recovery_under_stress
%%--------------------------------------------------------------------
async_flood_and_disconnect(doc) ->
    ["Test recovery from disconnect while many async notifications"
     "are in progress"];
async_flood_and_disconnect(Config) ->
    NumToSend = value(flood_test_messages, Config),
    LogDisp = ct:get_config(flood_test_log_disp, dont_log),
    Self = self(),
    Cb = async_user_callback_fun(LogDisp),
    F = fun(Session) ->
                Name = ?name(Session),
                % Start a receiver process to collect the responses
                ct:pal("Spawning receiver process..."),
                {ok, {Receiver, MonRef}} = p_spawn(?MODULE,
                                                   async_flood_receiver,
                                                   [NumToSend, Self]),
                ct:pal("Spawned receiver process ~p", [Receiver]),
                % Send off all the notifications asynchronously
                L = do_n_times(NumToSend,
                               fun(I) ->
                                       send_async_nf(I, Session, Receiver, Cb)
                               end),
                ct:pal("Sent off ~B notifications", [NumToSend]),
                % Store list of pending notifications
                Pending = lists:foldl(
                            fun(#nf_info{}=NFI, Acc) ->
                                    dict:store(NFI#nf_info.uuid, NFI, Acc)
                            end, dict:new(), L),
                ct:pal("Pausing until first response received"),
                receive {Receiver, got_first_response} -> ok end,
                ct:pal("Disconnecting and reconnecting session now"),
                ok = apns_erlv3_session:reconnect(Name),
                ct:pal("Reconnected session ~p", [Name]),
                % Wait for all the responses or die
                ct:pal("Waiting for pending responses from ~p", [Name]),
                T1 = erlang:system_time(milli_seconds),
                wait_pending_responses(Pending, Receiver, MonRef),
                T2 = erlang:system_time(milli_seconds),
                Elapsed = T2 - T1,
                ct:pal("Got ~B pending responses from ~p in ~B ms",
                       [dict:size(Pending), Name, Elapsed]),
                % -----------------------------------------
                % TODO: Ensure that session doesn't have any requests
                % hanging around in its internal state.
                % -----------------------------------------
                % Stop receiver (probably not really necessary, but ok)
                p_call(Receiver, stop)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
sync_flood_and_disconnect(doc) ->
    ["Test recovery from disconnect while sync notifications",
     "are in progress"];
sync_flood_and_disconnect(Config) ->
    NumToSend = value(flood_test_messages, Config),
    F = fun(Session) ->
                % Send off all the notifications asynchronously
                L = do_n_times(NumToSend,
                               fun(I) ->
                                       send_sync_nf(I, Session)
                               end),
                ct:pal("Sent off ~B notifications", [NumToSend]),
                ct:pal("Responses:\n~p", [L])
        end,
    for_all_sessions(F, ?sessions(Config)).

%%====================================================================
%% Internal helper functions
%%====================================================================
-spec init_testcase(Case, Config, StartFun) -> Result when
      Case :: atom(), Config :: [{_,_}],
      StartFun :: fun((Arg, Config) -> {ok, pid()}),
                      Arg :: atom() | pid(), Result :: list().
init_testcase(Case, Config, StartFun) when is_function(StartFun, 2) ->
    LagerCTEnv = ?config(lager_common_test_backend, Config),
    Level = value(bounce_level, LagerCTEnv),
    lager_common_test_backend:bounce(Level),
    DataDir = ?config(data_dir, Config),
    ct:pal("~p: Data directory is ~s", [Case, DataDir]),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),
    ok = sc_push_reg_api:init(),
    Start = fun(Session) ->
                    Name = ?name(Session),
                    {ok, {Pid, _Ref}=S} = start_session(Session, StartFun),
                    ?assert(is_pid(Pid)),
                    {Name, S}
            end,
    Sessions = try
                   for_all_sessions(Start, ?sessions(Config))
               catch
                   throw:Reason ->
                       ct:fail(Reason)
               end,
    set_props([{started_sessions, Sessions}], Config).

%%--------------------------------------------------------------------
-spec end_testcase(Case, Config, StopFun) -> Result when
      Case :: atom(), Config :: [{_,_}],
      StopFun :: fun((Arg, Config) -> {ok, Pid}),
                     Arg :: {Name, Pid, Ref}, Name :: atom(), Pid :: pid(),
                     Ref :: reference(), Result :: {ok, {Pid, Ref}}.
end_testcase(Case, Config, StopFun) when is_function(StopFun, 1) ->
    mnesia:stop(),
    ok = mnesia:delete_schema([node()]),
    StartedSessions = value(started_sessions, Config),
    ct:pal("~p: started_sessions is: ~p", [Case, StartedSessions]),
    Sessions = ?sessions(Config),
    [ok = stop_session(Session, StartedSessions, StopFun)
     || Session <- Sessions],
    ok.

%%--------------------------------------------------------------------
async_user_callback_fun() ->
    async_user_callback_fun(do_log).

%%--------------------------------------------------------------------
async_user_callback_fun(LogDisposition) when LogDisposition == do_log orelse
                                             LogDisposition == dont_log ->
    fun(NfPL, Req, Resp) ->
            case value(from, NfPL) of
                Caller when is_pid(Caller) ->
                    UUIDStr = value(uuid, NfPL),
                    _ = (LogDisposition == do_log) andalso
                        ct:pal("Invoke callback for UUIDStr ~s, caller ~p, "
                               "resp:\n~p", [UUIDStr, Caller, Resp]),
                    Caller ! {user_defined_cb, #{uuid => UUIDStr,
                                                 nf => NfPL,
                                                 req => Req,
                                                 resp => Resp}},
                    ok;
                undefined ->
                    ct:fail("Cannot send result, no caller info: ~p",
                            [NfPL]);
                _Unknown ->
                    ct:fail("Unhandled 'from' value in ~p", [NfPL])
            end
    end.

%%--------------------------------------------------------------------
async_receive_user_cb(UUIDStr) ->
    receive
        {user_defined_cb, #{uuid := UUIDStr, resp := Resp}=Map} ->
            ct:pal("Got async apns v3 response, result map: ~p", [Map]),
            UUID = str_to_uuid(UUIDStr),
            {ok, {UUID, ParsedResponse}} = Resp,
            check_parsed_resp(ParsedResponse, success);
        Msg ->
            ct:fail("async_receive_user_cb got unexpected message: ~p", [Msg])
    after
        1000 ->
            ct:fail({error, timeout})
    end.

%%--------------------------------------------------------------------
set_mnesia_dir(DataDir) ->
    MnesiaDir = filename:join(DataDir, "db"),
    ok = filelib:ensure_dir(MnesiaDir),
    ok = application:set_env(mnesia, dir, MnesiaDir).

%%--------------------------------------------------------------------
wait_until_session_in_connected_state(Session) ->
    Pid = erlang:whereis(?name(Session)),
    apns_erlv3_test_support:wait_for_connected(Pid, 5000).

%%--------------------------------------------------------------------
wait_pending_responses(PendingDict, Receiver, MonRef) ->
    receive
        {Receiver, {exit, ReceivedDict}} ->
            PSet = ordsets:from_list(dict:fetch_keys(PendingDict)),
            RSet = ordsets:from_list(dict:fetch_keys(ReceivedDict)),
            case ordsets:to_list(ordsets:subtract(PSet, RSet)) of
                [] ->
                    ct:pal("All pending responses received!");
                Keys ->
                    Missing = [dict:fetch(K, PendingDict) || K <- Keys],
                    ct:pal("Missing responses:\n~p", [Missing]),
                    ct:fail(missing_responses)
            end;
        {'DOWN', MonRef, Type, Receiver, Reason} ->
            ct:fail("~p ~p crashed before completing, reason: ~p",
                    [Type, Receiver, Reason])
    end.


%%--------------------------------------------------------------------
send_async_nf(I, Session, Receiver, Cb) when is_pid(Receiver) ->
    Name = ?name(Session),
    UUIDStr = gen_uuid(),
    Alert = list_to_binary(io_lib:format("async_flood_and_disconnect #~4..0B",
                                         [I])),
    Token = sc_util:to_bin(rand_push_tok()),
    Nf = [{alert, Alert},
          {uuid, UUIDStr},
          {token, Token},
          {topic, <<"com.example.FakeApp.voip">>}
         ],

    Opts = [{from_pid, Receiver}, {callback, Cb}],
    send_async_nf_impl(Name, Nf, Opts, Token, UUIDStr).

%%--------------------------------------------------------------------
send_async_nf_impl(Name, Nf, Opts, Token, UUIDStr) ->
    case sc_push_svc_apnsv3:async_send(Name, Nf, Opts) of
        {ok, {Action, _RUUID}} when Action =:= submitted;
                                    Action =:= queued ->
            #nf_info{session_name = Name,
                     token = Token,
                     uuid = UUIDStr};
        {error, {_UUID, try_again_later}} -> % backpressure kicked in
            timer:sleep(50),
            send_async_nf_impl(Name, Nf, Opts, Token, UUIDStr);
        Other ->
            ct:fail("Unexpected response: ~p", [Other])
    end.

%%--------------------------------------------------------------------
send_sync_nf(I, Session) ->
    Name = ?name(Session),
    UUIDStr = gen_uuid(),
    Alert = list_to_binary(io_lib:format("sync_flood_and_disconnect #~4..0B",
                                         [I])),
    Token = sc_util:to_bin(rand_push_tok()),
    Nf = [{alert, Alert},
          {uuid, UUIDStr},
          {token, Token},
          {topic, <<"com.example.FakeApp.voip">>}
         ],

    sc_push_svc_apnsv3:send(Name, Nf).

%%--------------------------------------------------------------------
p_spawn(M, F, A) ->
    {Pid, Ref} = spawn_monitor(M, F, A),
    receive
        {Pid, started} ->
            {ok, {Pid, Ref}}
    after
        5000 ->
            {error, timeout}
    end.

%%--------------------------------------------------------------------
p_call(Pid, Op) when is_pid(Pid) ->
    Pid ! {self(), Op},
    receive
        {Pid, Resp} ->
            {ok, Resp}
    after
        100 ->
            {error, timeout}
    end.

%%--------------------------------------------------------------------
p_reply(Pid, Reply) when is_pid(Pid) ->
    Pid ! {self(), Reply}.

-compile({inline, [p_reply/2]}).

%%--------------------------------------------------------------------
async_flood_receiver(ExpectedCount, ParentPid) when is_pid(ParentPid) ->
    p_reply(ParentPid, started),
    async_flood_receiver(ExpectedCount, ParentPid, dict:new(), 0);
async_flood_receiver(ExpectedCount, ParentPid) ->
    ct:pal("Invalid parameters, ExpectedCount=~p, ParentPid=~p",
           [ExpectedCount, ParentPid]).

%%--------------------------------------------------------------------
async_flood_receiver(0, ParentPid, Dict, _NR) when is_pid(ParentPid) ->
    p_reply(ParentPid, {exit, Dict});
async_flood_receiver(Count, ParentPid, Dict, NR) when Count > 0 andalso
                                                      is_pid(ParentPid) ->
    receive
        {user_defined_cb, #{uuid := UUIDStr, resp := Resp}} ->
            notify_first_response(ParentPid, NR),
            UUID = str_to_uuid(UUIDStr),
            ParsedResponse = case Resp of
                                 {ok, {UUID, PR}} ->
                                     PR;
                                 _ ->
                                     ct:fail("~p: error in resp ~p",
                                             [async_flood_receiver, Resp])
                             end,
            case value(status, ParsedResponse) of
                <<"200">> ->
                    async_flood_receiver(Count - 1, ParentPid,
                                         dict:store(UUIDStr, ParsedResponse,
                                                    Dict), NR + 1);
                Other ->
                    ct:fail("~p: bad response code ~s, ParsedResponse:\n~p",
                            [async_flood_receiver, Other, ParsedResponse])
            end;
        {ParentPid, stop} ->
            p_reply(ParentPid, {exit, Dict});
        {ParentPid, count} ->
            p_reply(ParentPid, {count, dict:size(Dict)}),
            async_flood_receiver(Count, ParentPid, Dict, NR);
        Msg ->
            ct:fail("~p: unexpected message: ~p", [async_flood_receiver, Msg])
    after
        1000 ->
            ct:pal("~p: ~B responses received so far, ~B left",
                   [async_flood_receiver, NR, Count]),
            async_flood_receiver(Count, ParentPid, Dict, NR)
    end;
async_flood_receiver(Count, ParentPid, Dict, NR) ->
    ct:fail("~p: invalid parameters, Count=~p, ParentPid=~p, Dict=~p, NR=~p",
            [async_flood_receiver, Count, ParentPid, Dict, NR]).

%%--------------------------------------------------------------------
notify_first_response(ParentPid, 0) ->
    p_reply(ParentPid, got_first_response);
notify_first_response(_ParentPid, _) ->
    ok.

-compile({inline, [notify_first_response/2]}).

%%--------------------------------------------------------------------
do_n_times(Count, Fun) ->
    do_n_times(Count, Fun, [], 0).

do_n_times(Count, Fun, Acc, I) when Count > 0 ->
    do_n_times(Count - 1, Fun, [Fun(I + 1)|Acc], I + 1);
do_n_times(0, _Fun, Acc, _I) ->
    lists:reverse(Acc).

%%--------------------------------------------------------------------
fix_sessions(Sessions, PropsToChange) ->
    [set_session_cfg(Session, PropsToChange) || Session <- Sessions].

%%--------------------------------------------------------------------
set_session_protocols(Proto, Sessions) ->
    [set_protocol(Proto, Session) || Session <- Sessions].

%%--------------------------------------------------------------------
set_protocol(Proto, Session) ->
    Config = value(config, Session),
    case Proto of
        h2 ->
            set_prop({config,
                      set_prop({protocol, Proto}, Config)}, Session);
        h2c ->
            % Note that ssl_opts is what's used in the session configs,
            % not ssl_options.
            ConfigWithoutSsl = set_prop({ssl_opts, []}, Config),
            set_prop({config, set_prop({protocol, Proto}, ConfigWithoutSsl)},
                     Session)
    end.

%%--------------------------------------------------------------------
set_session_cfg(Session, PropList) ->
    SessCfg = set_props(?cfg(Session), PropList),
    set_prop({config, SessCfg}, Session).

%%--------------------------------------------------------------------
sleep(Ms) ->
    receive
    after
        Ms -> ok
    end.

%%--------------------------------------------------------------------
wait_until(Pred, Args) when is_function(Pred, 1) ->
    case Pred(Args) of
        false ->
            sleep(5),
            wait_until(Pred, Args);
        true ->
            ok
    end.

%%--------------------------------------------------------------------
maybe_start_sim_node(DataDir, PrivDir, TestMode) ->
    case ct:get_config(sim_node_override, use_slave) of
        no_slave ->
            {[], noname, []};
        use_slave ->
            start_sim_node(DataDir, PrivDir, TestMode)
    end.

%%--------------------------------------------------------------------
start_sim_node(DataDir, PrivDir, TestMode) ->
    SimNode = ct:get_config(sim_node_name),
    ct:pal("Configured sim node name: ~p", [SimNode]),
    SimConfig0 = ct:get_config(simulator_config),
    ct:pal("Raw sim cfg: ~p", [SimConfig0]),

    SimConfig1 = fix_simulator_cert_paths(DataDir, SimConfig0),
    ct:pal("Sim cfg with fixed paths: ~p", [SimConfig1]),
    SimConfig = case TestMode of
                    https ->
                        set_prop({ssl, true}, SimConfig1);
                    http ->
                        SimSslOpts = lists:filter(
                                       fun({K, _}) ->
                                               lists:member(K, [ip, port])
                                       end, value(ssl_options, SimConfig1, [])
                                      ),
                        set_props([{ssl, false},
                                   {ssl_options, SimSslOpts}], SimConfig1)
                end,

    LagerEnv = ct:get_config(simulator_logging),
    ct:pal("Raw sim logging cfg: ~p", [LagerEnv]),

    ct:pal("Starting simulator with logging env ~p, config ~p",
           [LagerEnv, SimConfig]),
    {ok, StartedApps} = start_simulator(SimNode, SimConfig, LagerEnv, PrivDir),
    wait_until_sim_active(SimConfig),
    {StartedApps, SimNode, SimConfig}.
