%%% ==========================================================================
%%% Copyright 2012-2016 Silent Circle
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% ==========================================================================

%%% ==========================================================================
%%% @author Edwin Fine <efine@silentcircle.com>
%%% @doc Apple Push Notification Service (APNS) API.
%%%
%%% This is the API to the Apple Push Notification Service Provider.
%%%
%%% == Synopsis ==
%%%
%%% === Starting a session ===
%%%
%%% See {@link apns_erlv3_session} for a description of `Opts'.
%%%
%%% ```
%%% Opts = [
%%%         {name, 'apnsv3-com.example.FakeApp.voip'},
%%%         {token, "ca6a7fef1...4f1dc2"},
%%%         {config,
%%%          [
%%%           {host, <<"api.development.push.apple.com">>},
%%%           {port, 443},
%%%           {apns_env, prod},
%%%           {apns_topic, <<"com.example.FakeApp.voip">>},
%%%           {app_id_suffix, <<"com.example.FakeApp.voip">>},
%%%           {team_id, <<"6F44JJ9SDF">>},
%%%           {disable_apns_cert_validation, true},
%%%           {ssl_opts, [
%%%                       {cacertfile, "/etc/ssl/certs/ca-certificates.crt"},
%%%                       {certfile, "com.example.FakeApp.cert.pem"},
%%%                       {keyfile, "com.example.FakeApp.key.pem"},
%%%                       {verify, verify_peer},
%%%                       {honor_cipher_order, false},
%%%                       {versions, ['tlsv1.2']},
%%%                       {alpn_advertised_protocols, [<<"h2">>]}]}
%%%          ]}
%%%        ],
%%%
%%% {ok, Pid} = sc_push_svc_apnsv3:start_session(my_push_tester, Opts).
%%% '''
%%%
%%% === Sending an alert via the API ===
%%%
%%% ```
%%% Notification = [{alert, Alert}, {token, <<"e7b300...a67b">>}],
%%% {ok, ParsedResp} = sc_push_svc_apnsv3:send(my_push_tester, Notification).
%%% '''
%%%
%%% === Sending an alert via a session (for testing only) ===
%%%
%%% ```
%%% JSON = get_json_payload(), % See APNS docs for format
%%% Nf = [{token, Token}, {json, JSON}],
%%% {ok, ParsedResp} = apns_erlv3_session:send(my_push_tester, Nf).
%%% '''
%%%
%%% === Stopping a session ===
%%%
%%% ```
%%% ok = sc_push_svc_apnsv3:stop_session(my_push_tester).
%%% '''
%%% @end
%%% ==========================================================================
-module(sc_push_svc_apnsv3).
-behaviour(supervisor).

%%--------------------------------------------------------------------
%% Includes
%%--------------------------------------------------------------------
-include_lib("lager/include/lager.hrl").
-include("apns_erlv3_internal.hrl").

%%-----------------------------------------------------------------------
%% Types
%%-----------------------------------------------------------------------
-type session_config() :: apns_erlv3_session:options().
-type session_opt() :: {name, atom()}
                     | {mod, atom()}
                     | {config, session_config()}.
-type session() :: [session_opt()].
-type sessions() :: [session()].

-type fsm_ref() :: apns_erlv3_session:fsm_ref().
-type sync_send_reply() :: apns_erlv3_session:sync_send_reply().
-type async_send_reply() :: apns_erlv3_session:async_send_reply().

-type alert_prop() :: {title, binary()}
                    | {body, binary()}
                    | {'title-loc-key', binary() | null}
                    | {'title-loc-args', [binary()] | null}
                    | {'action-loc-key', binary() | null}
                    | {'loc-key', binary()}
                    | {'loc-args', [binary()]}
                    | {'launch-image', binary()}.

-type alert_proplist() :: [alert_prop()].

-type nf_prop() :: {alert, binary() | alert_proplist()}
                 | {badge, integer()}
                 | {sound, binary()}
                 | {'content-available', 0|1}
                 | {category, binary()}
                 | {extra, apns_json:json_term()}.

-type notification() :: [nf_prop()].

-type async_send_opt() :: {from_pid, pid()}
                        | {callback, apns_erlv3_session:send_callback()}.
-type async_send_opts() :: [async_send_opt()].

-type gen_proplist() :: sc_types:proplist(atom(), term()).
%%--------------------------------------------------------------------
%% Defines
%%--------------------------------------------------------------------
-define(SERVER, ?MODULE).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type, Timeout),
    {I, {I, start_link, []}, permanent, Timeout, Type, [I]}
).

-define(CHILD_ARGS(I, Args, Type, Timeout),
    {I, {I, start_link, Args}, permanent, Timeout, Type, [I]}
).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
-export([
         start_link/1,
         start_session/2,
         stop_session/1,
         send/2,
         send/3,
         async_send/2,
         async_send/3
        ]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================
%%--------------------------------------------------------------------
%% @doc `Sessions' is a list of proplists.
%% Each proplist is a session definition containing
%% `name', `mod', and `config' keys.
%% @see apns_erlv3_session:start_link/1
%% @end
%%--------------------------------------------------------------------
-spec start_link(Sessions) -> Result when
      Sessions :: sessions(), Result :: {ok, pid()} | {error, term()}.
start_link(Sessions) when is_list(Sessions) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Sessions).

%%--------------------------------------------------------------------
%% @doc Start named session for specific host and certificate as
%% supplied in the proplist `Opts'.
%% @see apns_erlv3_session_sup:start_child/2.
%% @end
%%--------------------------------------------------------------------
-spec start_session(Name, Opts) -> Result when
      Name :: atom(), Opts :: session(),
      Result :: {ok, pid()} | {error, already_started} | {error, term()}.
start_session(Name, Opts) when is_atom(Name), is_list(Opts) ->
    apns_erlv3_session_sup:start_child(Name, Opts).

%%--------------------------------------------------------------------
%% @doc Stop named session.
%% @end
%%--------------------------------------------------------------------
-spec stop_session(Name) -> Result when
      Name :: atom(), Result :: ok | {error, Reason}, Reason :: any().
stop_session(Name) when is_atom(Name) ->
    apns_erlv3_session_sup:stop_child(Name).

%%--------------------------------------------------------------------
%% @equiv send(Name, Notification, [])
%% @end
%%--------------------------------------------------------------------
-spec send(Name, Notification) -> Result when
      Name :: fsm_ref(), Notification :: notification(),
      Result :: sync_send_reply().
send(Name, Notification) when is_list(Notification) ->
    send(Name, Notification, []).

%%--------------------------------------------------------------------
%% @doc Send a notification specified by proplist `Notification'
%% to `Name' with options `Opts' (currently unused).
%%
%% Set the notification to expire in a very very long time.
%%
%% === Example ===
%%
%% Send an alert with a sound and extra data:
%%
%% ```
%% Name = 'com.example.AppId',
%% Notification = [
%%    {alert, <<"Hello">>},
%%    {token, <<"ea3f...">>},
%%    {aps, [
%%      {sound, <<"bang">>},
%%      {extra, [{a, 1}]}]}
%% ],
%% sc_push_svc_apnsv3:send(Name, Notification).
%% '''
%%
%% @end
%%--------------------------------------------------------------------
-spec send(Name, Notification, Opts) -> Result when
      Name :: fsm_ref(), Notification :: notification(),
      Opts :: gen_proplist(), Result :: sync_send_reply().
send(Name, Notification, Opts) when is_list(Notification), is_list(Opts) ->
    send(sync, Name, Notification, Opts).

%%--------------------------------------------------------------------
%% @equiv async_send(Name, Notification, [])
%% @end
%%--------------------------------------------------------------------
-spec async_send(Name, Notification) -> Result when
      Name :: fsm_ref(), Notification :: notification(),
      Result :: async_send_reply().
async_send(Name, Notification) when is_list(Notification) ->
    async_send(Name, Notification, []).

%%--------------------------------------------------------------------
%% @doc Asynchronously sends a notification specified by proplist
%% `Notification' to `Name' with proplist `Opts'.
%%
%% Returns `{ok, Result}' or `{error, term()}', where `Result' can be either
%% `{queued, uuid()}' or `{submitted, uuid()}'. The difference between
%% `queued' and `submitted' is the HTTP/2 session connection status. If the
%% HTTP/2 session is connected at the time the request is made, `submitted'
%% is used. If the session is not connected, the request is queued internally
%% until the session connects and `queued' is used to show this.
%%
%% It is possible that a queued notification could be lost if the session dies
%% before it can connect to APNS.
%%
%% == Opts ==
%%
%% `Opts' is a proplist that can take the following properties.
%%
%% <dl>
%%  <dt>`` {from_pid, pid()} ''</dt>
%%   <dd>The `pid' that will be passed to the callback function as the `from'
%%   property of the notification proplist (the first parameter of the
%%   callback function). If omitted, the `pid' is set to `self()'. It will
%%   be ignored unless the `callback' property is also provided.</dd>
%%  <dt>`` {callback, apns_erlv3_session:send_callback()} ''</dt>
%%   <dd>The callback function to be invoked when the asynchronous call
%%   completes. If omitted, the standard asynchronous behavior is
%%   used, and `from_pid' - if provided - is ignored.</dd>
%% </dl>
%%
%% === Callback function ===
%%
%% The callback function type signature is
%% {@link apns_erlv3_session:send_callback()}. The parameters
%% are described in apns_erlv3_session:async_send_cb/4.
%% ```
%% fun(NfPL, Req, Resp) -> any().
%% '''
%% <ul>
%%  <li>`NfPL' is the notification proplist as received by the session.</li>
%%  <li>`Req' is the HTTP/2 request as sent to APNS.</li>
%%  <li>`Resp' is the HTTP/2 response received from APNS, parsed into a
%%      proplist.</li>
%% </ul>
%%
%% === Example callback function ===
%%
%% ```
%% -spec example_callback(NfPL, Req, Resp) -> ok when
%%       NfPL :: apns_erlv3_session:send_opts(),
%%       Req :: apns_erlv3_session:cb_req(),
%%       Resp :: apns_erlv3_session:cb_result().
%% example_callback(NfPL, Req, Resp) ->
%%     case proplists:get_value(from, NfPL) of
%%         Caller when is_pid(Caller) ->
%%             UUID = proplists:get_value(uuid, NfPL),
%%             Caller ! {user_defined_cb, #{uuid => UUID,
%%                                          nf => NfPL,
%%                                          req => Req,
%%                                          resp => Resp}},
%%             ok;
%%         undefined ->
%%             log_error("Cannot send result, no caller info: ~p", [NfPL])
%%     end.
%% '''
%%
%% === Example parameters to callback function ===
%%
%% ```
%% NfPL = [{uuid,<<"44e83e09-bfb6-4f67-a281-f437a7450c1a">>},
%%         {expiration,2147483647},
%%         {token,<<"de891ab30fc96af54406b22cfcb2a7da09628c62236e374f044bd49879bd8e5a">>},
%%         {topic,<<"com.example.FakeApp.voip">>},
%%         {json,<<"{\"aps\":{\"alert\":\"Hello, async user callback\"}}">>},
%%         {from,<0.1283.0>},
%%         {priority,undefined}].
%%
%% Req = {[{<<":method">>,<<"POST">>},
%%         {<<":path">>, <<"/3/device/de891ab30fc96af54406b22cfcb2a7da09628c62236e374f044bd49879bd8e5a">>},
%%         {<<":scheme">>,<<"https">>},
%%         {<<"apns-topic">>, <<"com.example.FakeApp.voip">>},
%%         {<<"apns-expiration">>, <<"2147483647">>},
%%         {<<"apns-id">>, <<"44e83e09-bfb6-4f67-a281-f437a7450c1a">>}
%%        ], <<"{\"aps\":{\"alert\":\"Hello, async user callback\"}}">>
%%       }.
%%
%% Resp = {ok,[{uuid,<<"44e83e09-bfb6-4f67-a281-f437a7450c1a">>},
%%             {status,<<"200">>},
%%             {status_desc,<<"Success">>}]}.
%% '''
%%
%% @see apns_erlv3_session:async_send_cb/4
%% @end
%%--------------------------------------------------------------------

-spec async_send(Name, Notification, Opts) -> Result when
      Name :: fsm_ref(), Notification :: notification(),
      Opts :: async_send_opts(), Result :: async_send_reply().
async_send(Name, Notification, Opts) when is_list(Notification),
                                          is_list(Opts) ->
    send(async, Name, Notification, Opts).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

%% @private
-spec init(Opts) -> Result when
      Opts :: sessions(), Result :: {ok, {SupFlags, Children}},
      SupFlags :: supervisor:sup_flags(),
      Children :: [supervisor:child_spec()].
init(Opts) ->
    ?LOG_INFO("Starting APNSv3 (HTTP/2) services ~p", [service_names(Opts)]),
    ?LOG_DEBUG("APNSv3 service opts: ~p", [Opts]),
    RestartStrategy    = one_for_one,
    MaxRestarts        = 10, % If there are more than this many restarts
    MaxTimeBetRestarts = 60, % In this many seconds, then terminate supervisor

    SupFlags = {RestartStrategy, MaxRestarts, MaxTimeBetRestarts},

    Children = [
        ?CHILD_ARGS(apns_erlv3_session_sup, [Opts], supervisor, infinity)
    ],

    {ok, {SupFlags, Children}}.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
%% @private
-spec send(Mode, Name, Notification, Opts) -> Result when
      Mode :: sync | async, Name :: fsm_ref(), Notification :: notification(),
      Opts :: async_send_opts(),
      Result :: sync_send_reply() | async_send_reply().
send(Mode, Name, Notification, Opts) when is_list(Notification), is_list(Opts) ->
    ?LOG_DEBUG("Send ~p notification to ~p (opts ~p): ~p",
               [Mode, Name, Opts, Notification]),
    Nf = api_to_session_nf(Notification),
    ?LOG_DEBUG("Translated nf: ~p", [Nf]),
    case Mode of
        sync ->
            apns_erlv3_session:send(Name, Nf);
        async ->
            FromPid = sc_util:val(from_pid, Opts, self()),
            Callback = sc_util:val(callback, Opts),
            case {FromPid, Callback} of
                {Pid, CbFun} when is_pid(Pid), is_function(CbFun, 3) ->
                    apns_erlv3_session:async_send_cb(Name, Pid, Nf, CbFun);
                _Other ->
                    apns_erlv3_session:async_send(Name, Nf)
            end
    end.

%%--------------------------------------------------------------------
%% @private
api_to_session_nf(Notification) ->
    JSON = case sc_util:val(json, Notification) of
               undefined ->
                   APS = make_aps(Notification),
                   apns_json:make_notification(APS);
               Other ->
                   Other
           end,
    replace_prop(json, Notification, JSON).

%%--------------------------------------------------------------------
%% @private
make_aps(Notification) ->
    APS0 = sc_util:val(aps, Notification, []),
    APSAlert = sc_util:val(alert, Notification, sc_util:val(alert, APS0, <<>>)),
    replace_prop(alert, APS0, APSAlert).

%%--------------------------------------------------------------------
%% @private
replace_prop(Key, PL, NewVal) ->
    lists:keystore(Key, 1, PL, {Key, NewVal}).

%%--------------------------------------------------------------------
%% @private
service_names(Opts) ->
    lists:foldr(fun(Props, Acc) when is_list(Props) ->
                        [proplists:get_value(name, Props, unknown) | Acc];
                   (_, Acc) -> Acc
                end, [], Opts).
