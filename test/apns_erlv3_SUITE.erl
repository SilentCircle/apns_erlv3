%%%----------------------------------------------------------------
%%% Purpose: Test suite for the 'apns_erlv3' module.
%%%-----------------------------------------------------------------

-module(apns_erlv3_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("lager/include/lager.hrl").
-include("apns_erlv3_defs.hrl").

-compile(export_all).

-import(apns_erlv3_test_support,
        [
         add_props/2,
         check_parsed_resp/1,
         end_group/1,
         fix_all_cert_paths/2,
         fix_simulator_cert_paths/2,
         for_all_sessions/2,
         is_uuid/1,
         make_aps_props/2,
         make_sim_notification/2,
         new_prop/1,
         props_to_aps_json/1,
         reason_list/0,
         start_group/2,
         start_session/2,
         start_simulator/3,
         stop_session/3,
         to_bin_prop/2,
         value/2,
         wait_until_sim_active/1
        ]).

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
suite() -> [{timetrap, {seconds, 30}}].

%%--------------------------------------------------------------------
all() ->
    [
        {group, session},
        {group, clients},
        {group, unhappy_path},
        {group, pre_started_session}
    ].

%%--------------------------------------------------------------------
groups() ->
    [
     {session, [], [
                    start_stop_session_direct_test,
                    start_stop_session_test
                   ]
     },
     {pre_started_session, [], [
                                {group, clients},
                                {group, unhappy_path}
                               ]
     },
     {clients, [], [
                    clear_badge_test,
                    send_msg_test,
                    send_msg_via_api_test,
                    send_msg_sound_badge_test,
                    send_msg_with_alert_proplist
                   ]
     },
     {unhappy_path, [], [
                         bad_token,
                         bad_in_general,
                         bad_token_async,
                         bad_in_general_async,
                         bad_nf_format,
                         bad_nf_backend
                        ]
     }
    ].

%%--------------------------------------------------------------------
init_per_suite(Config) ->
    ct:pal("Entering init_per_suite; config: ~p", [Config]),
    ct:pal("My Erlang node name is ~p", [node()]),

    ok = ct:require(sessions),
    ok = ct:require(simulator_config),
    ok = ct:require(sim_node_name),
    ok = ct:require(lager),

    application:load(lager),
    [application:set_env(lager, Key, Val) || {Key, Val} <- ct:get_config(lager)],
    lager:start(),

    % ct:get_config(sessions) -> [Session].
    DataDir = ?config(data_dir, Config),
    ct:pal("Data directory is ~s~n", [DataDir]),

    PrivDir = ?config(priv_dir, Config),
    ct:pal("Private directory is ~s~n", [PrivDir]),

    Sessions0 = ct:get_config(sessions),
    true = is_list(Sessions0),
    ct:pal("Raw sessions: ~p~n", [Sessions0]),

    Sessions = fix_all_cert_paths(DataDir, Sessions0),
    ct:pal("Adjusted sessions: ~p~n", [Sessions]),

    SimNode = ct:get_config(sim_node_name),
    ct:pal("Configured sim node name: ~p", [SimNode]),
    SimConfig0 = ct:get_config(simulator_config),
    ct:pal("Raw sim cfg: ~p~n", [SimConfig0]),

    SimConfig = fix_simulator_cert_paths(DataDir, SimConfig0),

    ct:pal("Starting simulator with config ~p", [SimConfig]),
    {ok, StartedApps} = start_simulator(SimNode, SimConfig, PrivDir),

    wait_until_sim_active(SimConfig),

    [{sessions, Sessions},
     {sim_node_name, SimNode},
     {simulator_config, SimConfig},
     {sim_started_apps, StartedApps} | Config].

%%--------------------------------------------------------------------
end_per_suite(Config) ->
    Config.

%%--------------------------------------------------------------------
init_per_group(pre_started_session, Config) ->
    Sessions = value(sessions, Config),
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
init_per_testcase(Case, Config) ->
    init_testcase(Case, Config, fun sc_push_svc_apnsv3:start_session/2).

%%--------------------------------------------------------------------
end_per_testcase(Case = start_stop_session_direct_test, Config) ->
    StopFun = fun({_Name, Pid, _Ref}) ->
                      apns_erlv3_session:stop(Pid)
              end,
    end_testcase(Case, Config, StopFun);
end_per_testcase(Case, Config) ->
    StopFun = fun({Name, _Pid, _Ref}) ->
                      sc_push_svc_apnsv3:stop_session(Name)
              end,
    end_testcase(Case, Config, StopFun).

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

% t_1(doc) -> ["t/1 should return 0 on an empty list"];
% t_1(suite) -> [];
% t_1(Config) when is_list(Config)  ->
%     ?line 0 = t:foo([]),
%     ok.

%%--------------------------------------------------------------------
%% Group: session
%%--------------------------------------------------------------------
start_stop_session_direct_test() ->
    [].
start_stop_session_direct_test(doc) ->
    ["Start and stop a session using start/1."];
start_stop_session_direct_test(suite) ->
    [];
start_stop_session_direct_test(Config) ->
    %% This is all done using init/end_per_testcase
    Config.

%%--------------------------------------------------------------------
start_stop_session_test() ->
    [].

start_stop_session_test(doc) ->
    ["Start and stop a named session."];
start_stop_session_test(suite) ->
    [];
start_stop_session_test(Config) ->
    %% This is all done using init/end_per_testcase
    Config.

%%--------------------------------------------------------------------
%% Group: clients
%%--------------------------------------------------------------------
clear_badge_test(doc) ->
    ["sc_push_svc_apnsv3:send/3 should clear the badge"];
clear_badge_test(suite) -> [];
clear_badge_test(Config) ->
    F = fun(Session) ->
                NewBadge = 0,
                BadgeProp = new_prop(to_bin_prop(badge, NewBadge)),
                Name = value(name, Session),
                Token = list_to_binary(value(token, Session)),
                JSON = props_to_aps_json(BadgeProp),
                ct:pal("Sending notification via session ~p, JSON = ~p",
                       [Name, JSON]),
                {ok, Resp} = apns_erlv3_session:send(Name, Token, JSON),
                ct:pal("Sent notification via session, badge = ~p, Resp = ~p",
                       [NewBadge, Resp])
        end,
    for_all_sessions(F, value(sessions, Config)).

%%--------------------------------------------------------------------
send_msg_test(doc) ->
    ["apns_erlv3_session:send/3 should send a message to APNS"];
send_msg_test(suite) -> [];
send_msg_test(Config) ->
    NewBadge = 1,
    [
        begin
            Name = value(name, Session),
            Token = list_to_binary(value(token, Session)),
            Alert = "Testing svr '" ++ atom_to_list(Name) ++ "'",
            JSON = props_to_aps_json(make_aps_props(Alert, NewBadge)),
            ct:pal("Sending notification via session ~p, JSON = ~p",
                   [Name, JSON]),
            {ok, Resp} = apns_erlv3_session:send(Name, Token, JSON),
            ct:pal("Sent notification via session, badge = ~p, Resp = ~p",
                   [NewBadge, Resp])
        end || Session <- value(sessions, Config)
    ],
    Config.

%%--------------------------------------------------------------------
send_msg_via_api_test(doc) ->
    ["sc_push_svc_apnsv3:send/3 should send a message to APNS"];
send_msg_via_api_test(suite) ->
    [];
send_msg_via_api_test(Config) ->
    NewBadge = 2,
    [
        begin
            Opts = Session,
            Name = value(name, Opts),
            Alert = "Testing svr '" ++ atom_to_list(Name) ++ "'",
            Token = list_to_binary(value(token, Opts)),
            Notification = [{alert, Alert}, {token, Token},
                            {aps, [{badge, NewBadge}]}],
            ct:pal("Sending notification via session ~p, Notification = ~p",
                   [Name, Notification]),
            {ok, Resp} = sc_push_svc_apnsv3:send(Name, Notification),
            ct:pal("Sent notification via API, badge = ~p, Resp = ~p",
                   [NewBadge, Resp])
        end || Session <- value(sessions, Config)
    ],
    Config.

%%--------------------------------------------------------------------
send_msg_sound_badge_test(doc) ->
    ["sc_push_svc_apnsv3:send/3 should send a message, sound, and badge to APNS"];
send_msg_sound_badge_test(suite) ->
    [];
send_msg_sound_badge_test(Config) ->
    NewBadge = 3,
    [
        begin
            Opts = Session,
            Name = value(name, Opts),
            Token = list_to_binary(value(token, Opts)),
            Alert = list_to_binary([<<"Hi, this is ">>, atom_to_list(Name),
                                    <<", would you like to play a game?">>]),
            Notification = [
                    {'alert', Alert},
                    {'token', Token},
                    {'aps', [
                            {'badge', NewBadge},
                            {'sound', <<"wopr">>}]}
                    ],

            ct:pal("Sending notification via session ~p, Notification = ~p",
                   [Name, Notification]),
            {ok, Resp} = sc_push_svc_apnsv3:send(Name, Notification),
            ct:pal("Sent notification via API, badge = ~p, Resp = ~p",
                   [NewBadge, Resp])
        end || Session <- value(sessions, Config)
    ],
    Config.

%%--------------------------------------------------------------------
send_msg_with_alert_proplist(doc) ->
    ["sc_push_svc_apnsv3:send/3 should send a message to APNS"];
send_msg_with_alert_proplist(suite) ->
    [];
send_msg_with_alert_proplist(Config) ->
    NewBadge = 4,
    [
        begin
            Opts = Session,
            Name = value(name, Opts),
            Token = list_to_binary(value(token, Opts)),
            Alert = list_to_binary([<<"Testing svr '">>, atom_to_list(Name),
                                    <<"' with alert dict.">>]),
            Notification = [{alert, [{body, Alert}]}, {token, Token},
                            {aps, [{badge, NewBadge}]}],
            ct:pal("Sending notification via session ~p, Notification = ~p",
                   [Name, Notification]),
            {ok, Resp} = sc_push_svc_apnsv3:send(Name, Notification),
            ct:pal("Sent notification via API, badge = ~p, Resp = ~p",
                   [NewBadge, Resp])
        end || Session <- value(sessions, Config)
    ],
    Config.

%%--------------------------------------------------------------------
%% Group: unhappy_path
%%--------------------------------------------------------------------

bad_token(doc) -> ["sync send should handle BadDeviceToken properly"];
bad_token(suite) -> [];
bad_token(Config) when is_list(Config)  ->
    F = fun(Session) ->
                NfFun = reason_nf_fun(Session, <<"BadDeviceToken">>),
                resp_failure_test(NfFun, sync)
        end,
    for_all_sessions(F, value(sessions, Config)),
    Config.

%%--------------------------------------------------------------------
bad_in_general(doc) ->
    ["sync_send should handle all APNS HTTP/2 reason responses"];
bad_in_general(suite) -> [];
bad_in_general(Config) ->
    _ = [resp_failure_test(reason_nf_fun(Session, Reason), sync)
         || Reason <- reason_list(),
            Session <- value(sessions, Config)],
    Config.

%%--------------------------------------------------------------------
bad_token_async(doc) ->
    ["async send should handle BadDeviceToken properly"];
bad_token_async(suite) -> [];
bad_token_async(Config) when is_list(Config)  ->
    F = fun(Session) ->
                NfFun = reason_nf_fun(Session, <<"BadDeviceToken">>),
                resp_failure_test(NfFun, async)
        end,
    for_all_sessions(F, value(sessions, Config)),
    Config.

%%--------------------------------------------------------------------
bad_in_general_async(doc) ->
    ["async_send should handle all APNS HTTP/2 reason responses"];
bad_in_general_async(suite) -> [];
bad_in_general_async(Config) ->
    _ = [resp_failure_test(reason_nf_fun(Session, Reason), async)
         || Reason <- reason_list(),
            Session <- value(sessions, Config)],
    Config.

%%--------------------------------------------------------------------
bad_nf_format(doc) ->
    ["Ensure bad notification proplist is handled correctly"];
bad_nf_format(suite) -> [];
bad_nf_format(Config) when is_list(Config)  ->
    BadNfs = [
              [], % missing push token
              [{token, rand_push_tok()}] % Must be binary
             ],
    F = fun(Session) ->
                Name = value(name, Session),
                [begin
                     ct:pal("Send to session ~p, req: ~p", [Name, Nf]),
                     Resp = sc_push_svc_apnsv3:send(Name, Nf),
                     ct:pal("Response: ~p", [Resp]),
                     {error, {bad_notification, _}} = Resp
                 end || Nf <- BadNfs]
        end,
    _ = for_all_sessions(F, value(sessions, Config)),
    Config.

%%--------------------------------------------------------------------
bad_nf_backend(Config) ->
    F = fun(Session) ->
                Name = value(name, Session),
                UUID = gen_uuid(),
                Nf = [{alert, <<"Should be bad topic">>},
                      {topic, <<"Some BS Topic">>},
                      {token, list_to_binary(rand_push_tok())},
                      {id, UUID}
                     ],

                {error, {UUID, ParsedResp}} = sc_push_svc_apnsv3:send(Name, Nf),
                check_parsed_resp(ParsedResp),
                ct:pal("Sent notification via API, Resp = ~p", [ParsedResp]),
                <<"BadTopic">> = value(reason, ParsedResp)
        end,
    _ = for_all_sessions(F, value(sessions, Config)),
    Config.

%%====================================================================
%% Internal helper functions
%%====================================================================
-spec init_testcase(Case, Config, StartFun) -> Result when
      Case :: atom(), Config :: [{_,_}],
      StartFun :: fun((Arg, Config) -> {ok, pid()}),
      Arg :: atom() | pid(), Result :: {ok, pid()}.
init_testcase(Case, Config, StartFun) when is_function(StartFun, 2) ->
    DataDir = ?config(data_dir, Config),
    ct:pal("~p: Data directory is ~s~n", [Case, DataDir]),
    Sessions = try
                   [begin
                        Name = value(name, Session),
                        {ok, {Pid, _MonRef}=S} = start_session(Session, StartFun),
                        ?assert(is_pid(Pid)),
                        {Name, S}
                    end || Session <- value(sessions, Config)]
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
    Sessions = value(sessions, Config),
    [ok = stop_session(Session, StartedSessions, StopFun)
     || Session <- Sessions],
    ok.

%%--------------------------------------------------------------------
resp_failure_test(MakeNfFun) when is_function(MakeNfFun, 0) ->
    resp_failure_test(MakeNfFun, sync).

%%--------------------------------------------------------------------
resp_failure_test(MakeNfFun, sync) when is_function(MakeNfFun, 0) ->
    {Nf, Name} = MakeNfFun(),
    ct:pal("Sending notification via session ~p, Notification = ~p",
           [Name, Nf]),
    {error, {UUID, ParsedResp}} = sc_push_svc_apnsv3:send(Name, Nf),
    true = is_uuid(UUID),
    check_parsed_resp(ParsedResp),
    ct:pal("Sent notification via API, Resp = ~p", [ParsedResp]);
resp_failure_test(MakeNfFun, async) when is_function(MakeNfFun, 0) ->
    {Nf, Name} = MakeNfFun(),
    ct:pal("Sending notification via session ~p, Notification = ~p",
           [Name, Nf]),
    %% TODO: Make or fix callback functions for this so that
    %% responses can be checked.
    {ok, UUID} = sc_push_svc_apnsv3:async_send(Name, Nf),
    true = is_uuid(UUID),
    ct:pal("Sent async notification via API").

%%--------------------------------------------------------------------
reason_nf_fun(Session, Reason) ->
    fun() ->
            Name = value(name, Session),
            Token = list_to_binary(value(token, Session)),
            Alert = list_to_binary([<<"Testing svr '">>, atom_to_list(Name),
                                    <<"', ">>, Reason, <<".">>]),
            SimCfg = [{reason, Reason}],
            Notification = [{alert, Alert}, {token, Token}],
            Nf = make_sim_notification(Notification, SimCfg),
            {Nf, Name}
    end.

%%--------------------------------------------------------------------
rand_push_tok() ->
    sc_util:bitstring_to_hex(crypto:rand_bytes(32)).

gen_uuid() ->
    apns_lib_http2:make_uuid().


