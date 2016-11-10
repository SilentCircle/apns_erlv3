%%%----------------------------------------------------------------
%%% Purpose: Test suite for the 'apns_erlv3' module.
%%%-----------------------------------------------------------------
-module(apns_erlv3_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("lager/include/lager.hrl").
-include("apns_erlv3_defs.hrl").

-compile(export_all).
-compile({parse_transform, test_generator}).

-import(apns_erlv3_test_support,
        [add_props/2, check_parsed_resp/2, end_group/1, fix_all_cert_paths/2,
         format_str/2, format_bin/2, bin_prop/2, rand_push_tok/0, gen_uuid/0,
         wait_for_response/2, make_nf/1, make_nf/2, make_api_nf/2,
         maybe_prop/2, maybe_plist/2, plist/3, send_fun/4, send_fun_nf/4,
         gen_send_fun/4, send_funs/2, check_sync_resp/2, check_async_resp/2,
         check_match/2, sim_nf_fun/2, fix_simulator_cert_paths/2,
         for_all_sessions/2, is_uuid/1, reason_list/0, start_group/2,
         start_session/2, start_simulator/4, stop_session/3, to_bin_prop/2,
         value/2, wait_until_sim_active/1]).

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
     {group, quiesce_and_resume}
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
     }

    ].

%%--------------------------------------------------------------------
init_per_suite(Config) ->
    ct:pal("Entering init_per_suite; config: ~p", [Config]),
    ct:pal("My Erlang node name is ~p", [node()]),

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

    % ct:get_config(sessions) -> [Session].
    DataDir = ?config(data_dir, Config),
    ct:pal("Data directory is ~s", [DataDir]),

    PrivDir = ?config(priv_dir, Config),
    ct:pal("Private directory is ~s", [PrivDir]),

    Sessions0 = ct:get_config(sessions),
    true = is_list(Sessions0),
    ct:pal("Raw sessions: ~p", [Sessions0]),

    Sessions = fix_all_cert_paths(DataDir, Sessions0),
    ct:pal("Adjusted sessions: ~p", [Sessions]),

    SimNode = ct:get_config(sim_node_name),
    ct:pal("Configured sim node name: ~p", [SimNode]),
    SimConfig0 = ct:get_config(simulator_config),
    ct:pal("Raw sim cfg: ~p", [SimConfig0]),

    SimConfig = fix_simulator_cert_paths(DataDir, SimConfig0),

    ValidCertCfg0 = ct:get_config(valid_cert),
    ct:pal("Raw valid cert config: ~p", [ValidCertCfg0]),

    [ValidCertCfg] = fix_all_cert_paths(DataDir, [ValidCertCfg0]),
    ct:pal("Adjusted cert config: ~p", [ValidCertCfg]),

    LagerEnv = ct:get_config(simulator_logging),
    ct:pal("Raw sim logging cfg: ~p", [LagerEnv]),

    ct:pal("Starting simulator with logging env ~p, config ~p",
           [LagerEnv, SimConfig]),
    {ok, StartedApps} = start_simulator(SimNode, SimConfig, LagerEnv, PrivDir),
    wait_until_sim_active(SimConfig),

    LagerCTBackend = ct:get_config(lager_common_test_backend),
    Config ++ [{sessions, Sessions},
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
init_per_group(_GroupName, Config) ->
    SessionStarter = fun() -> apns_erlv3_session_sup:start_link([]) end,
    start_group(SessionStarter, Config).


%%--------------------------------------------------------------------
end_per_group(pre_started_session, Config) ->
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

crash_session_startup_test(doc) ->
    ["Crash a session by starting it badly."];
crash_session_startup_test(_Config) ->
    ct:pal("Expecting crash when starting session with empty opts~n"),
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
                ct:pal("Forcing reconnect of session ~p", [Name]),
                ok = apns_erlv3_session:reconnect(Name),
                {ok, StateName} = apns_erlv3_session:get_state_name(Name),
                ct:pal("Session ~p state is ~p", [Name, StateName]),
                ?assert(StateName =:= connecting)
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
    ct:pal("Test startup with valid push certs~n"),
    ValidCertCfg = value(valid_cert, Config),
    {ok, {Pid, _Ref}} = start_session(ValidCertCfg,
                                      fun apns_erlv3_session:start/2),
    apns_erlv3_session:stop(Pid).

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
    SendFun = apnsv3_test_gen:send_fun_nf({error, expired}, MakeNfFun),
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
             SendFun(Session)
         end || Reason <- reason_list(), Session <- ?sessions(Config)].

%%--------------------------------------------------------------------
bad_nf_format(doc) -> ["Ensure bad nf proplist is handled correctly"];
bad_nf_format(Config) when is_list(Config)  ->
    BadNfs = [
              [], % missing push token
              [{token, rand_push_tok()}] % Must be binary
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
                     SendFun(Session)
                 end || Nf <- BadNfs]
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
bad_nf_backend(doc) -> ["Ensure backend errors are handled correctly"];
bad_nf_backend(Config) ->
    F = fun(Session) ->
                Name = ?name(Session),
                UUID = gen_uuid(),
                Nf = [
                      {uuid, UUID},
                      {alert, <<"Should be bad topic">>},
                      {token, sc_util:to_bin(rand_push_tok())},
                      {topic, <<"Some BS Topic">>}
                     ],

                {ok, PResp} = sc_push_svc_apnsv3:send(Name, Nf),
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
                {ok, ParsedResp} = apns_erlv3_session:send(Name, Nf),
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
                UUID = gen_uuid(),
                APS = [{aps, [{alert, <<"Testing async user callback">>},
                              {'content-available', 1}
                             ]}],
                Nf = [
                      {uuid, UUID},
                      {token, sc_util:to_bin(rand_push_tok())},
                      {topic, <<"com.example.FakeApp.voip">>},
                      {json, jsx:encode(APS)}
                     ],

                From = self(),
                Result = apns_erlv3_session:async_send_cb(Name, From, Nf, Cb),
                ct:pal("Sent notification via session ~p, Result = ~p",
                       [Session, Result]),
                {ok, {submitted, RUUID}} = Result,
                ?assertEqual(RUUID, UUID),
                async_receive_user_cb(RUUID)
        end,
    for_all_sessions(F, ?sessions(Config)).

%%--------------------------------------------------------------------
async_api_send_user_callback(doc) ->
    ["Test async api send with user callback"];
async_api_send_user_callback(Config) ->
    Cb = async_user_callback_fun(),
    F = fun(Session) ->
                Name = ?name(Session),
                UUID = gen_uuid(),
                Nf = [{alert, <<"Testing async api user callback">>},
                      {uuid, UUID},
                      {token, sc_util:to_bin(rand_push_tok())},
                      {topic, <<"com.example.FakeApp.voip">>}
                     ],

                Opts = [{from_pid, self()}, {callback, Cb}],
                Result = sc_push_svc_apnsv3:async_send(Name, Nf, Opts),
                ct:pal("Sent notification via session ~p, Result = ~p",
                       [Name, Result]),
                {ok, {submitted, RUUID}} = Result,
                ?assertEqual(RUUID, UUID),
                async_receive_user_cb(RUUID)
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
    add_props([{started_sessions, Sessions}], Config).

%%--------------------------------------------------------------------
-spec end_testcase(Case, Config, StopFun) -> Result when
      Case :: atom(), Config :: [{_,_}],
      StopFun :: fun((Arg, Config) -> {ok, Pid}),
                     Arg :: {Name, Pid, Ref}, Name :: atom(), Pid :: pid(),
                     Ref :: reference(), Result :: {ok, {Pid, Ref}}.
end_testcase(Case, Config, StopFun) when is_function(StopFun, 1) ->
    StartedSessions = value(started_sessions, Config),
    ct:pal("~p: started_sessions is: ~p", [Case, StartedSessions]),
    Sessions = ?sessions(Config),
    [ok = stop_session(Session, StartedSessions, StopFun)
     || Session <- Sessions],
    ok.

%%--------------------------------------------------------------------
async_user_callback_fun() ->
    fun(NfPL, Req, Resp) ->
            case value(from, NfPL) of
                Caller when is_pid(Caller) ->
                    UUID = value(uuid, NfPL),
                    ct:pal("Invoke callback for UUID ~s, caller ~p",
                           [UUID, Caller]),
                    Caller ! {user_defined_cb, #{uuid => UUID,
                                                 nf => NfPL,
                                                 req => Req,
                                                 resp => Resp}},
                    ok;
                undefined ->
                    ct:fail("Cannot send result, no caller info: ~p",
                            [NfPL])
            end
    end.

%%--------------------------------------------------------------------
async_receive_user_cb(UUID) ->
    receive
        {user_defined_cb, #{uuid := UUID, resp := Resp}=Map} ->
            ct:pal("Got async apns v3 response, result map: ~p",
                   [Map]),
            {ok, ParsedResponse} = Resp,
            check_parsed_resp(ParsedResponse, success);
        Msg ->
            ct:fail("async_receive_user_cb got unexpected message: ~p", [Msg])
    after 1000 ->
              ct:fail({error, timeout})
    end.

