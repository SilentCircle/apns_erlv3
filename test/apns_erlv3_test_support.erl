-module(apns_erlv3_test_support).

-include_lib("common_test/include/ct.hrl").
-include("apns_erlv3_defs.hrl").

-export([
         add_props/2,
         check_parsed_resp/1,
         end_group/1,
         fix_all_cert_paths/2,
         fix_simulator_cert_paths/2,
         for_all_sessions/2,
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
         start_simulator/3,
         stop_session/3,
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
check_parsed_resp(ParsedResp) ->
    Keys = [id, status, status_desc, reason, reason_desc, body],
    ok = assert_keys_present(Keys, ParsedResp),
    case {value(status, ParsedResp), value(reason, ParsedResp)} of
        {<<"410">>, <<"BadDeviceToken">>} ->
            ok = assert_keys_present([timestamp, timestamp_desc], ParsedResp);
        _ ->
            ok
    end.

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
    _ = [Fun(Session) || Session <- Sessions],
    ok.

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
    APS0 = value(aps, Notification, []),
    Extra0 = value(extra, APS0, []),
    Extra = lists:keystore(sim_cfg, 1, Extra0, {sim_cfg, SimCfg}),
    APS = lists:keystore(extra, 1, APS0, {extra, Extra}),
    lists:keystore(aps, 1, Notification, {aps, APS}).

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
     <<"BadDeviceToken">>,
     <<"BadExpirationDate">>,
     <<"BadMessageId">>,
     <<"BadPath">>,
     <<"BadPriority">>,
     <<"BadTopic">>,
     <<"DeviceTokenNotForTopic">>,
     <<"DuplicateHeaders">>,
     <<"Forbidden">>,
     <<"IdleTimeout">>,
     <<"InternalServerError">>,
     <<"MethodNotAllowed">>,
     <<"MissingDeviceToken">>,
     <<"MissingTopic">>,
     <<"PayloadEmpty">>,
     <<"PayloadTooLarge">>,
     <<"ServiceUnavailable">>,
     <<"Shutdown">>,
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
    Config = value(config, Opts),
    ct:pal("Starting session ~p with config ~p~n", [Name, Config]),
    {ok, Pid} = StartFun(Name, Config),
    MonRef = erlang:monitor(process, Pid),
    ct:pal("Monitoring pid ~p with ref ~p", [Pid, MonRef]),
    %% Check that session is actually started, or fail
    wait_for_connected(Pid, 2000),
    {ok, {Pid, MonRef}}.

%%--------------------------------------------------------------------
%% SimConfig = [{ssl_options, []},{ssl_true}].
start_simulator(Name, SimConfig, _PrivDir) ->
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

    ct:pal("Starting apns_erl_sim application on ~p", [Node]),
    {ok, L} = rpc:call(Node, application, ensure_all_started,
                       [apns_erl_sim], 5000),

    ct:pal("Simulator on ~p: Started ~p", [Node, L]),
    ct:pal("Pausing ~p for 1000ms", [Node]),
    receive after 1000 -> ok end,
    {ok, L}.

%%--------------------------------------------------------------------
stop_session(SessCfg, StartedSessions, StopFun) when is_list(SessCfg),
                                                     is_function(StopFun, 1) ->
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
    end.

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

