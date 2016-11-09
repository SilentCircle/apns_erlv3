-module(apns_erlv3_test_support).

-include_lib("common_test/include/ct.hrl").
-include("apns_erlv3_defs.hrl").

-export([
         add_props/2,
         check_parsed_resp/2,
         end_group/1,
         fix_all_cert_paths/2,
         fix_simulator_cert_paths/2,
         for_all_sessions/2,
         format_str/2,
         format_bin/2,
         bin_prop/2,
         rand_push_tok/0,
         gen_uuid/0,
         wait_for_response/2,
         make_nf/1,
         make_nf/2,
         make_api_nf/2,
         maybe_prop/2,
         maybe_plist/2,
         plist/3,
         send_fun/4,
         send_fun_nf/4,
         gen_send_fun/4,
         send_funs/2,
         check_sync_resp/2,
         check_async_resp/2,
         check_match/2,
         sim_nf_fun/2,
         is_uuid/1,
         make_aps_props/1,
         make_aps_props/2,
         make_aps_props/3,
         make_sim_notification/2,
         new_prop/1,
         new_prop/2,
         props_to_aps_json/1,
         reason_list/0,
         start_group/2,
         start_session/2,
         start_simulator/4,
         stop_session/3,
         uuid_to_str/1,
         str_to_uuid/1,
         to_bin_prop/2,
         value/2,
         value/3,
         wait_until_sim_active/1,
         wait_until_sim_active/2
        ]).


%%====================================================================
%% API
%%====================================================================
add_props(FromProps, ToProps) ->
    lists:foldl(fun(KV, Acc) -> add_prop(KV, Acc) end, ToProps, FromProps).

%%--------------------------------------------------------------------
check_parsed_resp(ParsedResp, ExpStatus) ->
    ActualStatus = check_keys_present(ParsedResp),
    check_status(ActualStatus, ExpStatus).

%%--------------------------------------------------------------------
check_keys_present(ParsedResp) ->
    SuccessKeySet = [uuid, status, status_desc],
    ErrorKeySet = SuccessKeySet ++ [reason, reason_desc, body],
    AllKeySet = ErrorKeySet ++ [timestamp, timestamp_desc],

    ActualStatus = value(status, ParsedResp),
    Reason = value(reason, ParsedResp, undefined),
    case {ActualStatus, Reason} of
        {<<"200">>, undefined} ->
            ok = assert_keys_present(SuccessKeySet, ParsedResp);
        {<<"410">>, <<"Unregistered">>} ->
            ok = assert_keys_present(AllKeySet, ParsedResp);
        {_, _} when is_binary(Reason) ->
            ok = assert_keys_present(ErrorKeySet, ParsedResp)
    end,
    ActualStatus.

%%--------------------------------------------------------------------
check_status(ActualStatus, CheckFun) when is_function(CheckFun, 1) ->
    CheckFun(ActualStatus);
check_status(ActualStatus, ExpStatus) ->
    case ExpStatus of
        any     ->  ok;
        success -> ?assertEqual(ActualStatus, <<"200">>);
        failure -> ?assertNotEqual(ActualStatus, <<"200">>);
        _       -> ?assertEqual(ActualStatus, ExpStatus)
    end.

%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
end_group(Config) ->
    case value(sess_sup_pid, Config, undefined) of
        undefined ->
            Config;
        SessSupPid ->
            unlink(SessSupPid),
            exit(SessSupPid, kill),
            ensure_stopped(ssl),
            delete_key(sess_sup_pid, Config)
    end.

%%--------------------------------------------------------------------
fix_all_cert_paths(DataDir, Sessions) ->
    KeyCfg = {config, ssl_opts},
    [fix_cert_paths(KeyCfg, DataDir, Session) || Session <- Sessions].

%%--------------------------------------------------------------------
fix_simulator_cert_paths(DataDir, SimConfig) ->
    SslOptsKey = ssl_options,
    SslOpts0 = value(SslOptsKey, SimConfig),
    SslOpts = fix_ssl_opts(SslOpts0, DataDir),
    replace_kv(SslOptsKey, SslOpts, SimConfig).

%%--------------------------------------------------------------------
for_all_sessions(Fun, Sessions) when is_function(Fun, 1), is_list(Sessions) ->
    [Fun(Session) || Session <- Sessions].

%%--------------------------------------------------------------------
is_uuid(X) ->
    %% UUID should be 8-4-4-4-12
    match =:= re:run(X,
                     "^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$",
                     [{capture, none}]).

%%--------------------------------------------------------------------
make_aps_props(Alert) ->
    new_prop(to_bin_prop(alert, Alert)).

%%--------------------------------------------------------------------
make_aps_props(Alert, Badge) when is_integer(Badge) ->
    add_prop({badge, Badge}, make_aps_props(Alert)).

%%--------------------------------------------------------------------
make_aps_props(Alert, Badge, Sound) when is_integer(Badge) ->
    add_prop(to_bin_prop(sound, Sound), make_aps_props(Alert, Badge)).

%%--------------------------------------------------------------------
make_sim_notification(Notification, SimCfg) ->
    case value(json, Notification, undefined) of
        undefined ->
            add_simcfg(Notification, SimCfg);
        JSON0 ->
            Nf = keys_binary_to_atom(jsx:decode(JSON0)),
            NewNf = add_simcfg(Nf, SimCfg),
            JSON = jsx:encode(NewNf),
            lists:keystore(json, 1, Notification, {json, JSON})
    end.

add_simcfg(Notification, SimCfg) ->
    APS0 = value(aps, Notification, []),
    Extra0 = value(extra, APS0, []),
    Extra = lists:keystore(sim_cfg, 1, Extra0, {sim_cfg, SimCfg}),
    APS = lists:keystore(extra, 1, APS0, {extra, Extra}),
    lists:keystore(aps, 1, Notification, {aps, APS}).

keys_binary_to_atom([{K, V}|Rest]) ->
    [{sc_util:to_atom(K), keys_binary_to_atom(V)}|keys_binary_to_atom(Rest)];
keys_binary_to_atom(V) ->
    V.

%%--------------------------------------------------------------------
new_prop({_, _} = KV) ->
    [KV].

%%--------------------------------------------------------------------
new_prop(K, V) ->
    new_prop({K, V}).

%%--------------------------------------------------------------------
props_to_aps_json(ApsProps) when is_list(ApsProps) ->
    jsx:encode([{aps, ApsProps}]).

%%--------------------------------------------------------------------
reason_list() ->
    [
     <<"BadCertificate">>,
     <<"BadCertificateEnvironment">>,
     <<"BadCollapseId">>,
     <<"BadDeviceToken">>,
     <<"BadExpirationDate">>,
     <<"BadMessageId">>,
     <<"BadPath">>,
     <<"BadPriority">>,
     <<"BadTopic">>,
     <<"DeviceTokenNotForTopic">>,
     <<"DuplicateHeaders">>,
     <<"ExpiredProviderToken">>,
     <<"Forbidden">>,
     <<"IdleTimeout">>,
     <<"InternalServerError">>,
     <<"InvalidProviderToken">>,
     <<"MethodNotAllowed">>,
     <<"MissingDeviceToken">>,
     <<"MissingProviderToken">>,
     <<"MissingTopic">>,
     <<"PayloadEmpty">>,
     <<"PayloadTooLarge">>,
     <<"ServiceUnavailable">>,
     <<"Shutdown">>,
     <<"TooManyProviderTokenUpdates">>,
     <<"TooManyRequests">>,
     <<"TopicDisallowed">>,
     <<"Unregistered">>
    ].

%%--------------------------------------------------------------------
start_group(SessionStarter, Config) ->
    end_group(Config),
    application:ensure_started(ssl),
    {ok, SessSupPid} = SessionStarter(),
    ct:pal("Started session sup with pid ~p", [SessSupPid]),
    unlink(SessSupPid),
    add_prop({sess_sup_pid, SessSupPid}, Config).

%%--------------------------------------------------------------------
start_session(Opts, StartFun) when is_list(Opts),
                                   is_function(StartFun, 2) ->
    Name = value(name, Opts),
    case apns_erlv3_session_sup:get_child_pid(Name) of
        undefined ->
            Config = value(config, Opts),
            ct:pal("Starting session ~p with config ~p~n", [Name, Config]),
            {ok, Pid} = StartFun(Name, Config),
            MonRef = erlang:monitor(process, Pid),
            ct:pal("Monitoring pid ~p with ref ~p", [Pid, MonRef]),
            %% Check that session is actually started, or fail
            wait_for_connected(Pid, 2000),
            {ok, {Pid, MonRef}};
        Pid ->
            {ok, {Pid, undefined}}
    end.

%%--------------------------------------------------------------------
stop_session(SessCfg, StartedSessions, StopFun) when is_list(SessCfg),
                                                     is_function(StopFun, 1) ->
    Name = value(name, SessCfg),
    case apns_erlv3_session_sup:get_child_pid(Name) of
        undefined ->
            ct:pal("Session ~p not running, no need to stop it", [Name]),
            ok;
        Pid ->
            NPR = {Name, Pid, Ref} = session_info(SessCfg, StartedSessions),
            ct:pal("Stopping session ~p pid: ~p ref: ~p", [Name, Pid, Ref]),
            ok = StopFun(NPR),
            receive
                {'DOWN', _MRef, process, Pid, Reason} ->
                    ct:pal("Received 'DOWN' from pid ~p, reason ~p",
                           [Pid, Reason]),
                    ok
            after 2000 ->
                      erlang:demonitor(Ref),
                      {error, timeout}
            end
    end.

%%--------------------------------------------------------------------
%% SimConfig = [{ssl_options, []},{ssl_true}].
start_simulator(Name, SimConfig, LagerEnv, _PrivDir) ->
    %% Get important code paths
    CodePaths = [Path || Path <- code:get_path(),
                         string:rstr(Path, "_build/") > 0],
    %{ok, GenResultPL} = generate_sys_config(chatterbox, SimConfig, PrivDir),
    ct:pal("Starting sim node named ~p", [Name]),
    {ok, Node} = start_slave(Name, []),
    ct:pal("Sim node name: ~p", [Node]),
    ct:pal("Setting simulator configuration"),
    ct:pal("~p", [SimConfig]),
    _ = [ok = rpc:call(Node, application, set_env,
                       [chatterbox, K, V], 1000) || {K, V} <- SimConfig],

    SimCBEnv = rpc:call(Node, application, get_all_env, [chatterbox], 1000),
    ct:pal("Sim's chatterbox environment: ~p", [SimCBEnv]),
    ct:pal("Adding code paths to node ~p", [Node]),
    ct:pal("~p", [CodePaths]),
    ok = rpc:call(Node, code, add_pathsz, [CodePaths], 1000),

    %% Set lager environment
    ct:pal("Setting lager environment"),
    _ = [ok = rpc:call(Node, application, set_env,
                       [lager, K, V], 1000) || {K, V} <- LagerEnv],
    ActualLagerEnv = rpc:call(Node, application, get_all_env, [lager], 1000),
    ct:pal("Sim's lager environment: ~p", [ActualLagerEnv]),

    ct:pal("Starting apns_erl_sim application on ~p", [Node]),
    {ok, L} = rpc:call(Node, application, ensure_all_started,
                       [apns_erl_sim], 5000),

    ct:pal("Simulator on ~p: Started ~p", [Node, L]),
    ct:pal("Pausing ~p for 1000ms", [Node]),
    receive after 1000 -> ok end,
    {ok, L}.

%%--------------------------------------------------------------------
to_bin_prop(K, V) ->
    {sc_util:to_atom(K), sc_util:to_bin(V)}.

%%--------------------------------------------------------------------
value(Key, Config) ->
    V = proplists:get_value(Key, Config),
    ?assertMsg(V =/= undefined, "Required key missing: ~p~n", [Key]),
    V.

%%--------------------------------------------------------------------
value(Key, Config, Def) ->
    proplists:get_value(Key, Config, Def).

%%--------------------------------------------------------------------
wait_until_sim_active(SimConfig) ->
    wait_until_sim_active(SimConfig, 2000).

%%--------------------------------------------------------------------
wait_until_sim_active(SimConfig, Timeout) ->
    Ref = erlang:send_after(Timeout, self(), {sim_timeout, self()}),
    SslOptions = value(ssl_options, SimConfig),
    wait_sim_active_loop(SslOptions),
    (catch erlang:cancel_timer(Ref)),
    ok.

%%%====================================================================
%%% Internal functions
%%%====================================================================
%%--------------------------------------------------------------------
stop_simulator(StartedApps) ->
    [ok = application:stop(App) || App <- StartedApps].

%%--------------------------------------------------------------------
generate_sys_config(AppName, AppConfig, PrivDir) ->
    Config = {AppName, AppConfig},
    ensure_dir(filename:join(PrivDir, "sim_config")),
    Filename = filename:join(PrivDir, "sim_config", "sys.config"),
    SysConfig = lists:flatten(io_lib:format("~p~n", [Config])),
    ok = file:write_file(Filename, SysConfig),
    {ok, [{config_file, Filename},
          {contents, SysConfig}]}.

%%--------------------------------------------------------------------
wait_sim_active_loop(SslOptions) ->
    Addr = value(ip, SslOptions),
    Port = value(port, SslOptions),
    Self = self(),
    ct:pal("wait_sim_active_loop: connecting to {~p, ~p}", [Addr, Port]),
    case gen_tcp:connect(Addr, Port, []) of
        {ok, Socket} ->
            ct:pal("wait_sim_active_loop: Success opening socket to {~p, ~p}",
                   [Addr, Port]),
            ok = gen_tcp:close(Socket);
        {error, Reason} ->
            ct:pal("wait_sim_active_loop: failed connecting to {~p, ~p}: ~p",
                   [Addr, Port, gen_tcp:format_error(Reason)]),
            receive
                {sim_timeout, Self} ->
                    ct:pal("wait_sim_active_loop: timed out "
                           "connecting to {~p, ~p}", [Addr, Port]),
                    throw(sim_ping_timeout)
            after
                1000 ->
                    wait_sim_active_loop(SslOptions)
            end
    end.

%%--------------------------------------------------------------------
wait_for_connected(Pid, Timeout) ->
    Ref = erlang:send_after(Timeout, self(), {timeout, self()}),
    wait_connected_loop(Pid),
    (catch erlang:cancel_timer(Ref)),
    ok.

%%--------------------------------------------------------------------
wait_connected_loop(Pid) ->
    Self = self(),
    ct:pal("wait_connected_loop: checking if pid ~p is alive/connected",
           [Pid]),
    case is_process_alive(Pid) andalso apns_erlv3_session:is_connected(Pid) of
        {ok, true} ->
            ct:pal("wait_connected_loop: yes, pid ~p is alive and connected",
                   [Pid]),
            ct:pal("wait_connected_loop: process_info(~p):", [process_info(Pid)]);
        {ok, false} ->
            ct:pal("wait_connected_loop: pid ~p is not alive/connected",
                   [Pid]),
            receive
                {'EXIT', _Pid, Reason} ->
                    throw({process_crashed, Reason});
                {'DOWN', _MRef, process, _Pid, Reason} ->
                    throw({process_down, Reason});
                {timeout, Self} ->
                    throw(session_connect_timeout)
            after
                1000 ->
                    wait_connected_loop(Pid)
            end;
        Error ->
            throw(Error)
    end.

%%--------------------------------------------------------------------
get_saved_value(K, Config, Def) ->
    case ?config(saved_config, Config) of
        undefined ->
            proplists:get_value(K, Config, Def);
        {Saved, OldConfig} ->
            ct:pal("Got config saved by ~p", [Saved]),
            proplists:get_value(K, OldConfig, Def)
    end.

%%--------------------------------------------------------------------
fix_cert_paths({ConfigKey, SslOptsKey}, DataDir, Session) ->
    Config = value(ConfigKey, Session),
    SslOpts = fix_ssl_opts(value(SslOptsKey, Config), DataDir),
    replace_kv(ConfigKey,
               replace_kv(SslOptsKey, SslOpts, Config),
               Session).


%%--------------------------------------------------------------------
fix_ssl_opts(SslOpts, DataDir) ->
    OptCaCertKV = fix_opt_kv(cacertfile, SslOpts, DataDir),
    CertFilePath = fix_path(certfile, SslOpts, DataDir),
    KeyFilePath = fix_path(keyfile, SslOpts, DataDir),
    PartialOpts = delete_keys([cacertfile, certfile, keyfile], SslOpts),
    OptCaCertKV ++ [{certfile, CertFilePath},
                    {keyfile, KeyFilePath} | PartialOpts].


%%--------------------------------------------------------------------
fix_path(Key, PL, DataDir) ->
    filename:join(DataDir, value(Key, PL)).


%%--------------------------------------------------------------------
fix_opt_kv(Key, PL, DataDir) ->
    case proplists:get_value(Key, PL) of
        undefined ->
            [];
        Val ->
            [{Key, filename:join(DataDir, Val)}]
    end.

%%--------------------------------------------------------------------
replace_kv(Key, Val, PL) ->
    [{Key, Val} | delete_key(Key, PL)].

%%--------------------------------------------------------------------
add_prop({K, _V} = KV, Props) ->
    lists:keystore(K, 1, Props, KV).

%%--------------------------------------------------------------------
delete_key(Key, PL) ->
    lists:keydelete(Key, 1, PL).

%%--------------------------------------------------------------------
delete_keys(Keys, PL) ->
    lists:foldl(fun(Key, Acc) -> delete_key(Key, Acc) end, PL, Keys).

%%--------------------------------------------------------------------
ensure_dir(Dirname) ->
    case file:make_dir(Dirname) of
        X when X == {error, eexist} orelse X == ok ->
            ok; % Fine if it's there
        {error, POSIX} ->
            Errmsg = file:format_error({?LINE, ?MODULE, POSIX}),
            ct:fail("Error (~p) trying to create ~d: ~s",
                    [POSIX, Dirname, Errmsg]),
            {error, Errmsg}
    end.

%%--------------------------------------------------------------------
ensure_stopped(App) when is_atom(App) ->
    case application:stop(App) of
        ok ->
            ok;
        {error, {not_started, App}} ->
            ok;
        {error, Error} ->
            throw(Error)
    end.

%%--------------------------------------------------------------------
check_parsed_resp_timestamp(ParsedResp) ->
    Keys = [
            timestamp, timestamp_desc],
    _ = [{'value', _} = lists:keysearch(Key, 1, ParsedResp) || Key <- Keys].

%%--------------------------------------------------------------------
assert_keys_present(Keys, PL) ->
    _ = [value(Key, PL) || Key <- Keys],
    ok.

%%====================================================================
%% Slave node support
%%====================================================================
start_slave(Name, Args) ->
    {ok, Host} = inet:gethostname(),
    slave:start(Host, Name, Args).

session_info(SessCfg, StartedSessions) ->
    Name = value(name, SessCfg),
    {Pid, Ref} = value(Name, StartedSessions),
    {Name, Pid, Ref}.

%%--------------------------------------------------------------------
format_str(Fmt, Session) ->
    format_str(Fmt, Session, []).

format_str(Fmt, Session, Args) ->
    format_str(Fmt, Session, Args, []).

format_str([$%, $n|T], Session, Args, Acc) ->
    Name = atom_to_list(?name(Session)),
    format_str(T, Session, Args, [Name | Acc]);
format_str([$%, $%|T], Session, Args, Acc) ->
    format_str(T, Session, Args, [$% | Acc]);
format_str([Ch|T], Session, Args, Acc) ->
    format_str(T, Session, Args, [Ch | Acc]);
format_str([], _Session, Args, Acc) ->
    lists:flatten(io_lib:format(lists:reverse(Acc), Args)).

%%--------------------------------------------------------------------
format_bin(Fmt, Session) ->
    format_bin(Fmt, Session, []).

format_bin(Fmt, Session, Args) ->
    sc_util:to_bin(format_str(Fmt, Session, Args)).

%%--------------------------------------------------------------------
bin_prop(K, PL) ->
    sc_util:to_bin(value(K, PL)).

%%--------------------------------------------------------------------
rand_push_tok() ->
    sc_util:bitstring_to_hex(crypto:rand_bytes(32)).

%%--------------------------------------------------------------------
gen_uuid() ->
    apns_lib_http2:make_uuid().


%%--------------------------------------------------------------------
wait_for_response(UUID, Timeout) ->
    receive
        {apns_response, v3, {UUID, Resp}} ->
            ct:pal("Received async apns v3 response, uuid: ~p, resp: ~p",
                   [UUID, Resp]),
            Resp
    after Timeout ->
              {error, timeout}
    end.

%%--------------------------------------------------------------------
%% Make a notification [{token, binary()},
%%                      {topic, binary()},
%%                      {uuid, apns_lib_http2:uuid_str()},
%%                      {priority, integer()},
%%                      {expiry, integer()},
%%                      {json, json()}
%%                      ]
%% by first converting the alert, badge and sound properties to JSON.
%% The following items are defaulted if absent:
%% alert - defaults to standard message
%% token - defaults to token defined in test config
%% extra - the keys in this optional dict will be inserted at the same level
%%         as the aps dict, for example, if the input map is
%%         #{alert => <<"foo">>, extra => [{simcfg, blah}]}, the JSON
%%         will look like {"aps": {"alert": "foo"}, "simcfg": blah}.
make_nf(Session) ->
    make_nf(Session, #{}).

make_nf(Session, #{} = Map) ->
    OptApsProps = lists:foldl(fun(K, Acc) -> Acc ++ maybe_plist(K, Map) end,
                              [], [badge, sound]),
    DefAlert = format_bin("Testing svr '%n'", Session),
    Alert = plist(alert, Map, DefAlert),
    ApsProps = Alert ++ OptApsProps,
    OptJsonProps = maybe_extra(Map),
    JSON = jsx:encode([{aps, ApsProps}] ++ OptJsonProps),
    OptProps = lists:foldl(fun(K, Acc) -> Acc ++ maybe_plist(K, Map) end,
                           [], [topic, uuid, priority, expiry]),
    Token = plist(token, Map, bin_prop(token, Session)),
    Nf = Token ++ OptProps ++ [{json, JSON}],
    {Nf, ?name(Session)}.

maybe_extra(#{extra := Extra}) when is_list(Extra) ->
    Extra;
maybe_extra(#{}) ->
    [].

%%--------------------------------------------------------------------
%% Make a notification
%% [{alert, binary()}
%%  {token, binary()},
%%  {aps, [{badge, integer()},
%%         {sound, binary()}]}]
%% using the map elements alert and token, and optional elements
%% badge and sound. If alert and token are omitted, they will be
%% synthesized (token from the session config is the default).
make_api_nf(Session, #{} = Map) ->
    DefAlert = format_bin("Testing svr '%n'", Session),
    DefToken = bin_prop(token, Session),
    Nf = plist(alert, Map, DefAlert) ++ plist(token, Map, DefToken) ++
         [{'aps', maybe_plist(badge, Map) ++ maybe_plist(sound, Map)}],
    {Nf, ?name(Session)}.

%%--------------------------------------------------------------------
maybe_prop(_K, undefined) ->
    [];
maybe_prop(K, V) ->
    [{K, V}].

%%--------------------------------------------------------------------
maybe_plist(Key, Map) ->
    case maps:find(Key, Map) of
        {ok, Val} ->
            [{Key, Val}];
        error ->
            []
    end.

%%--------------------------------------------------------------------
plist(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Val} ->
            [{Key, Val}];
        error ->
            [{Key, Default}]
    end.

%%--------------------------------------------------------------------
send_fun(Mode, Type, #{} = Map, ExpStatus) when ?is_valid_mt(Mode, Type) ->
    send_fun_nf(Mode, Type, ExpStatus,
                fun(Session) -> make_nf(Session, Map) end).

%%--------------------------------------------------------------------
send_fun_nf(Mode, Type, ExpStatus,
            MakeNfFun) when ?is_valid_mt(Mode, Type) andalso
                            is_function(MakeNfFun, 1) ->
    {SendFun, CheckRespFun} = send_funs(Mode, Type),
    gen_send_fun(ExpStatus, MakeNfFun, SendFun, CheckRespFun).

%%--------------------------------------------------------------------
gen_send_fun(ExpStatus, MakeNfFun, SendFun,
             CheckRespFun) when is_function(MakeNfFun, 1),
                                is_function(SendFun, 2),
                                is_function(CheckRespFun, 2) ->
    fun(Session) ->
            {Nf, Name} = MakeNfFun(Session),
            ct:pal("Sending notification (session ~p): ~p", [Name, Nf]),
            CheckRespFun(SendFun(Name, Nf), ExpStatus)
    end.

%%--------------------------------------------------------------------
send_funs(sync,  session) -> {fun apns_erlv3_session:send/2,
                              fun check_sync_resp/2};
send_funs(async, session) -> {fun apns_erlv3_session:async_send/2,
                              fun check_async_resp/2};
send_funs(sync,  api)     -> {fun sc_push_svc_apnsv3:send/2,
                              fun check_sync_resp/2};
send_funs(async, api)     -> {fun sc_push_svc_apnsv3:async_send/2,
                              fun check_async_resp/2}.

%%--------------------------------------------------------------------
check_sync_resp({ok, ParsedResp}, ExpStatus) ->
    ct:pal("Sent sync notification, resp = ~p", [ParsedResp]),
    check_parsed_resp(ParsedResp, ExpStatus),
    UUID = value(uuid, ParsedResp),
    true = is_uuid(UUID);
check_sync_resp(Resp, ExpStatus) ->
    ct:pal("Sent sync notification, error resp = ~p", [Resp]),
    check_match(Resp, ExpStatus).

%%--------------------------------------------------------------------
check_async_resp({ok, {Action, UUID}}, ExpStatus) ->
    ct:pal("Sent async notification, req was ~p (uuid: ~p)",
           [Action, UUID]),
    ?assert(lists:member(Action, [queued, submitted])),
    case wait_for_response(UUID, 5000) of
        {ok, ParsedResp} ->
            ct:pal("Received async response ~p", [ParsedResp]),
            check_parsed_resp(ParsedResp, ExpStatus),
            UUID = value(uuid, ParsedResp),
            true = is_uuid(UUID);
        Error ->
            ct:pal("Received async error result ~p", [Error]),
            check_match(Error, ExpStatus)
    end;
check_async_resp(Resp, ExpStatus) ->
    ct:pal("Received async error response ~p", [Resp]),
    check_match(Resp, ExpStatus).

check_match(Resp, CheckFun) when is_function(CheckFun, 1) ->
    CheckFun(Resp);
check_match(Resp, ExpStatus) ->
    ?assertMatch(Resp, ExpStatus).

%%--------------------------------------------------------------------
%% Return fun that creates a notification containing an apns simulator
%% configuration (to force a given response).
sim_nf_fun(#{} = Map, #{reason := Reason} = SimMap) ->
    fun(Session) ->
            Alert = format_bin("Testing svr '%n', ~p.", Session, [Reason]),
            SimCfg = [{reason, Reason}] ++ maybe_plist(status_code, SimMap),
            NfMap = Map#{alert => Alert,
                         extra => [{sim_cfg, SimCfg}]},
            make_nf(Session, NfMap)
    end.

%%--------------------------------------------------------------------
uuid_to_str(<<_:128>> = UUID) ->
    uuid:uuid_to_string(UUID, binary_standard).

%%--------------------------------------------------------------------
str_to_uuid(UUID) ->
    uuid:string_to_uuid(UUID).

