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

%%%-------------------------------------------------------------------
%%% @author Edwin Fine <efine@silentcircle.com>
%%% @copyright (C) 2012-2016 Silent Circle LLC
%%% @doc
%%% APNS V3 (HTTP/2) server session.
%%%
%%% There must be one session per App Bundle ID and certificate (Development or
%%% Production) combination. Sessions must have unique (i.e. they are
%%% registered) names within the node.
%%%
%%% When connecting or disconnecting, all the notifications received by the
%%% session are put in the input queue. When the connection is established, all
%%% the queued notifications are sent to the APNS server.
%%%
%%% When failing to connect, the delay between retries will grow exponentially
%%% up to a configurable maximum value. The delay is reset when successfully
%%% reconnecting.
%%%
%%% When the session receives an error from APNS servers, it unregisters the
%%% token if the error was due to a bad token.
%%%
%%%
%%% Process configuration:
%%% <dl>
%%%
%%% <dt>`host':</dt>
%%%   <dd>is the hostname of the APNS HTTP/2 service as a binary string. This may
%%%       be omitted as long as `apns_env' is present. In this case, the code will
%%%       choose a default host using `apns_lib_http2:host_port/1' based on the
%%%       environment.
%%%   </dd>
%%%
%%% <dt>`port':</dt>
%%%   <dd>is the port of the APNS HTTP/2 service as a positive integer. This may
%%%       be omitted as long as `apns_env' is present. In this case, the code will
%%%       choose a default port using `apns_lib_http2:host_port/1' based on the
%%%       environment.
%%%   </dd>
%%%
%%% <dt>`apns_env':</dt>
%%%   <dd>is the push notification environment. This can be either `` 'dev' ''
%%%       or `` 'prod' ''. This is *mandatory* if either `host' or `port' are
%%%       omitted. If
%%% </dd>
%%%
%%% <dt>`bundle_seed_id':</dt>
%%%   <dd>is the APNS bundle seed identifier as a binary. This is used to
%%%   validate the APNS certificate unless `disable_apns_cert_validation'
%%%   is `true'.
%%% </dd>
%%%
%%% <dt>`apns_topic':</dt>
%%%   <dd>is the <b>default</b> APNS topic to which to push notifications. If a
%%%   topic is provided in the notification, it always overrides the default.
%%%   This must be one of the topics in `certfile', otherwise the notifications
%%%   will all fail, unless the topic is explicitly provided in the
%%%   notifications.
%%%   <br/>
%%%   If this is omitted and the certificate is a multi-topic certificate, the
%%%   notification will fail unless the topic is provided in the actual push
%%%   notification. Otherwise, with regular single-topic certificates, the
%%%   first app bundle id in `certfile' is used.
%%%
%%%   Default value:
%%%     <ul>
%%%     <li>If multi-topic certificate: none (notification will fail)</li>
%%%     <li>If NOT multi-topic certificate: First app bundle ID in `certfile'</li>
%%%     </ul>
%%% </dd>
%%%
%%% <dt>`retry_delay':</dt>
%%%   <dd>is the minimum time in milliseconds the session will wait before
%%%     reconnecting to APNS servers as an integer; when reconnecting multiple
%%%     times this value will be multiplied by 2 for every attempt.
%%%
%%%     Default value: `1000'.
%%%
%%% </dd>
%%%
%%% <dt>`retry_max':</dt>
%%%   <dd>is the maximum amount of time in milliseconds that the session will wait
%%%     before reconnecting to the APNS servers.
%%%
%%%     Default value: `60000'.
%%%
%%% </dd>
%%%
%%% <dt>`disable_apns_cert_validation':</dt>
%%%   <dd>is `true' is APNS certificate validation against its bundle id
%%%     should be disabled, `false' if the validation should be done.
%%%     This option exists to allow for changes in APNS certificate layout
%%%     without having to change code.
%%%
%%%     Default value: `false'.
%%% </dd>
%%%
%%% <dt>`ssl_opts':</dt>
%%%   <dd>is the property list of SSL options including the certificate file path.
%%% </dd>
%%% </dl>
%%%
%%% === Example configuration ===
%%% ```
%%%     [{host, "api.development.push.apple.com"},
%%%      {port, 443},
%%%      {apns_env, dev},
%%%      {bundle_seed_id, <<"com.example.MyApp">>},
%%%      {apns_topic, <<"com.example.MyApp">>},
%%%      {retry_delay, 1000},
%%%      {disable_apns_cert_validation, false},
%%%      {ssl_opts,
%%%       [{certfile, "/some/path/com.example.MyApp--DEV.cert.pem"},
%%%        {keyfile, "/some/path/com.example.MyApp--DEV.key.unencrypted.pem"},
%%%        {honor_cipher_order, false},
%%%        {versions, ['tlsv1.2']},
%%%        {alpn_preferred_protocols, [<<"h2">>]}].
%%%       ]}
%%%     ]
%%% '''
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(apns_erlv3_session).

-behaviour(gen_fsm).


%%% ==========================================================================
%%% Includes
%%% ==========================================================================

-include_lib("lager/include/lager.hrl").
-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("public_key/include/public_key.hrl").


%%% ==========================================================================
%%% Exports
%%% ==========================================================================

%%% API Functions
-export([start/2,
         start_link/2,
         stop/1,
         send/2,
         send/3,
         send/4,
         send/5,
         async_send/2,
         async_send/3,
         async_send/4,
         async_send/5
     ]).

%%% Debugging Functions
-export([get_state/1, get_state_name/1, is_connected/1]).

%%% Behaviour gen_fsm standard callbacks
-export([init/1,
         handle_event/3,
         handle_sync_event/4,
         handle_info/3,
         terminate/3,
         code_change/4]).

%%% Behaviour gen_fsm states callbacks
-export([connecting/2, connecting/3,
         connected/2, connected/3,
         disconnecting/2, disconnecting/3]).

%%% "Internal" exports
-export([validate_binary/2]).
-export([validate_boolean/2]).
-export([validate_integer/2]).
-export([validate_list/2]).
-export([validate_non_neg/2]).

%%% ==========================================================================
%%% Macros
%%% ==========================================================================

-define(S, ?MODULE).

%% Valid APNS priority values
-define(PRIO_IMMEDIATE,     10).
-define(PRIO_CONSERVE_POWER, 5).

-define(DEFAULT_APNS_PORT, 443).
-define(DEFAULT_RETRY_DELAY, 1000).
-define(DEFAULT_RETRY_MAX, 60*1000).
-define(DEFAULT_EXPIRY_TIME, 16#7FFFFFFF). % INT_MAX, 32 bits
-define(DEFAULT_PRIO, ?PRIO_IMMEDIATE).

-define(assert(Cond),
    case (Cond) of
        true ->
            true;
        false ->
            throw({assertion_failed, ??Cond})
    end).

-define(assertList(Term), begin ?assert(is_list(Term)), Term end).
-define(assertInt(Term), begin ?assert(is_integer(Term)), Term end).
-define(assertPosInt(Term), begin ?assert(is_integer(Term) andalso Term > 0), Term end).
-define(assertNonNegInt(Term), begin ?assert(is_integer(Term) andalso Term >= 0), Term end).
-define(assertBinary(Term), begin ?assert(is_binary(Term)), Term end).
-define(assertReadFile(Filename),
        ((fun(Fname) ->
                 case file:read_file(Fname) of
                     {ok, B} ->
                         B;
                     {error, Reason} ->
                         throw({file_read_error, {Reason, file:format_error(Reason), Fname}})
                 end
         end)(Filename))).
-ifdef(namespaced_queues).
-type sc_queue() :: queue:queue().
-else.
-type sc_queue() :: queue().
-endif.

%%% ==========================================================================
%%% Records
%%% ==========================================================================

%%% Process state
-record(?S,
        {name               = undefined                  :: atom(),
         http2_pid          = undefined                  :: pid() | undefined,
         host               = ""                         :: string(),
         port               = ?DEFAULT_APNS_PORT         :: non_neg_integer(),
         bundle_seed_id     = <<>>                       :: binary(),
         apns_env           = undefined                  :: prod | dev,
         apns_topic         = <<>>                       :: undefined | binary(),
         ssl_opts           = []                         :: list(),
         retry_delay        = ?DEFAULT_RETRY_DELAY       :: non_neg_integer(),
         retry_max          = ?DEFAULT_RETRY_MAX         :: non_neg_integer(),
         retry_ref          = undefined                  :: reference() | undefined,
         retries            = 1                          :: non_neg_integer(),
         queue              = undefined                  :: sc_queue() | undefined,
         stop_callers       = []                         :: list()
        }).

%% Notification
-record(nf,
        {id             = <<>>                   :: undefined | apns_lib_http2:uuid_str(),
         expiry         = 0                      :: non_neg_integer(),
         token          = <<>>                   :: binary(),
         topic          = <<>>                   :: undefined | binary(), % APNS topic/bundle id
         json           = <<>>                   :: binary(),
         from           = undefined              :: undefined | term(),
         prio           = ?DEFAULT_PRIO          :: undefined | non_neg_integer()
        }).

%% Note on prio field.
%%
%% Apple documentation states:
%%
%% The remote notification must trigger an alert, sound, or badge on the
%% device. It is an error to use this priority for a push that contains only
%% the content-available key.

%%% ==========================================================================
%%% Types
%%% ==========================================================================

-type state() :: #?S{}.

-type state_name() :: connecting | connected | disconnecting.

-type option() :: {host, string()} |
                  {port, non_neg_integer()} |
                  {bundle_seed_id, binary()} |
                  {apns_env, prod | dev} |
                  {apns_topic, binary()} |
                  {ssl_opts, list()} |
                  {retry_delay, non_neg_integer()} |
                  {retry_max, pos_integer()}.

-type options() :: [option()].

-type fsm_ref() :: atom() | pid().
-type nf() :: #nf{}.
-type bstrtok() :: binary(). %% binary of string rep of APNS token.
-type send_opt() :: {token, bstrtok()}
                  | {topic, binary()}
                  | {id, apns_lib_http2:uuid_str()}
                  | {priority, integer()}
                  | {expiry, integer()}
                  | {json, binary()}
                  .
-type send_opts() :: [send_opt()].

%%% ==========================================================================
%%% API Functions
%%% ==========================================================================

%%--------------------------------------------------------------------
%% @doc Start a named session as described by the options `Opts'.  The name
%% `Name' is registered so that the session can be referenced using the name to
%% call functions like send/3. Note that this function is only used
%% for testing; see start_link/2.
%% @end
%%--------------------------------------------------------------------

-spec start(Name, Opts) -> {ok, Pid} | ignore | {error, Error}
    when Name :: atom(), Opts :: options(), Pid :: pid(), Error :: term().

start(Name, Opts) when is_atom(Name), is_list(Opts) ->
    gen_fsm:start({local, Name}, ?MODULE, [Name, Opts], []).


%%--------------------------------------------------------------------
%% @doc Start a named session as described by the options `Opts'.  The name
%% `Name' is registered so that the session can be referenced using the name to
%% call functions like send/3.
%% @end
%%--------------------------------------------------------------------

-spec start_link(Name, Opts) -> {ok, Pid} | ignore | {error, Error}
    when Name :: atom(), Opts :: options(), Pid :: pid(), Error :: term().

start_link(Name, Opts) when is_atom(Name), is_list(Opts) ->
    gen_fsm:start_link({local, Name}, ?MODULE, [Name, Opts], []).


%%--------------------------------------------------------------------
%% @doc Stop session.
%% @end
%%--------------------------------------------------------------------

-spec stop(FsmRef) -> ok
    when FsmRef :: fsm_ref().

stop(FsmRef) ->
    gen_fsm:sync_send_all_state_event(FsmRef, stop).


%%--------------------------------------------------------------------
%% @doc Asynchronously send notification in `Opts'.
%% Return UUID of request or error. If `id' is not provided in `Opts',
%% generate a UUID for this request.
%% @end
%%--------------------------------------------------------------------
-spec async_send(FsmRef, Opts) -> {ok, UUID} | {error, term()} when
      FsmRef :: fsm_ref(), Opts :: send_opts(),
      UUID :: apns_lib_http2:uuid_str().
async_send(FsmRef, Opts) when is_list(Opts) ->
    try make_nf(Opts) of
        #nf{} = Nf ->
            ok = gen_fsm:send_event(FsmRef, {send, Nf}),
            {ok, Nf#nf.id};
        Error ->
            Error
    catch
        _:Reason ->
            {error, {bad_notification, [{opts, Opts}, {reason, Reason}]}}
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------

-spec async_send(FsmRef, Token, JSON) -> ok
    when FsmRef :: fsm_ref(), Token :: binary(), JSON :: binary().

async_send(FsmRef, Token, JSON) when is_binary(Token), is_binary(JSON) ->
    async_send(FsmRef, [{token, Token},
                        {json, JSON}]).


%%--------------------------------------------------------------------
%% @doc Send a push notification asynchronously. See send/4 for details.
%% @end
%%--------------------------------------------------------------------

-spec async_send(FsmRef, Expiry, Token, JSON) -> ok
    when FsmRef :: fsm_ref(), Expiry :: non_neg_integer(),
         Token :: binary(), JSON :: binary().

async_send(FsmRef, Expiry, Token, JSON) ->
    async_send(FsmRef, [{expiry, Expiry},
                        {token, Token},
                        {json, JSON}]).

%%--------------------------------------------------------------------
%% @doc Send a push notification asynchronously. See send/5 for details.
%% @end
%%--------------------------------------------------------------------

-spec async_send(FsmRef, Expiry, Token, JSON, Prio) -> ok
    when FsmRef :: fsm_ref(), Expiry :: non_neg_integer(),
         Token :: binary(), JSON :: binary(), Prio :: non_neg_integer().

async_send(FsmRef, Expiry, Token, JSON, Prio) when is_integer(Expiry),
                                                   is_binary(Token),
                                                   is_binary(JSON),
                                                   is_integer(Prio) ->
    async_send(FsmRef, [{priority, Prio},
                        {expiry, Expiry},
                        {token, Token},
                        {json, JSON}]).


%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec send(FsmRef, Opts) -> Result when
      FsmRef :: fsm_ref(), Opts :: send_opts(),
      Result :: {ok, undefined | UUID} | {error, Reason},
      UUID :: apns_lib_http2:uuid_str(), Reason :: term().
send(FsmRef, Opts) when is_list(Opts) ->
    lager:debug("Sending sync notification ~p", [Opts]),
    try make_nf(Opts) of
        #nf{} = Nf ->
            lager:debug("Sending sync notification ~p", [Nf]),
            try_sync_send(FsmRef, Nf);
        Error ->
            Error
    catch
        _:Reason ->
            {error, {bad_notification, [{opts, Opts}, {reason, Reason}]}}
    end.

try_sync_send(FsmRef, #nf{} = Nf) ->
    try
        gen_fsm:sync_send_event(FsmRef, {send, Nf})
    catch
        exit:{timeout, _} -> {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @doc
%% @equiv send(FsmRef, 16#7FFFFFFF, Token, JSON)
%% @end
%%--------------------------------------------------------------------

-spec send(FsmRef, Token, JSON) -> {ok, undefined | UUID} | {error, Reason}
    when FsmRef :: fsm_ref(), Token :: binary(),
         JSON :: binary(), UUID :: apns_lib_http2:uuid_str(), Reason :: term().

send(FsmRef, Token, JSON) when is_binary(Token), is_binary(JSON) ->
    send(FsmRef, [{token, Token},
                  {json, JSON}]).

%%--------------------------------------------------------------------
%% @doc Send a notification specified by APS `JSON' to `Token' via
%% `FsmRef'. Expire the notification after the epoch `Expiry'.
%% For JSON format, see
%% <a href="https://developer.apple.com/library/ios/#documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/">
%% Local and Push Notification Programming Guide
%% </a> (requires Apple Developer login).
%%
%% It the notification has been sent to an APNS server, the function returns
%% its UUID, if it has been queued but could not be sent before
%% the default timeout (5000 ms) it returns undefined.
%% @end
%%--------------------------------------------------------------------

-spec send(FsmRef, Expiry, Token, JSON) -> {ok, undefined | UUID} | {error, Reason}
    when FsmRef :: fsm_ref(), Expiry :: non_neg_integer(),
         Token :: binary(), JSON :: binary(),
         UUID :: apns_lib_http2:uuid_str(), Reason :: term().

send(FsmRef, Expiry, Token, JSON) ->
    send(FsmRef, [{token, Token},
                  {json, JSON},
                  {expiry, Expiry}]).

%%--------------------------------------------------------------------
%% @doc Send a notification specified by APS `JSON' to `Token' via
%% `FsmRef'. Expire the notification after the epoch `Expiry'.
%% Set the priority to a valid value of `Prio' (currently 5 or 10,
%% 10 may not be used to push notifications without alert, badge or sound).
%%
%% If the notification has been sent to an APNS server, the function returns
%% its UUID, if it has been queued but could not be sent before
%% the default timeout (5000 ms) it returns undefined.
%% @end
%%--------------------------------------------------------------------

-spec send(FsmRef, Expiry, Token, JSON, Prio) -> Result when
      FsmRef :: fsm_ref(), Expiry :: non_neg_integer(),
      Token :: binary(), JSON :: binary(), Prio :: non_neg_integer(),
      Result :: {ok, Resp} | {error, Reason},
      Resp :: apns_lib_http2:parsed_rsp(), Reason :: term().

send(FsmRef, Expiry, Token, JSON, Prio) when is_integer(Expiry),
                                             is_binary(Token),
                                             is_binary(JSON),
                                             is_integer(Prio) ->
    send(FsmRef, [{token, Token},
                  {json, JSON},
                  {expiry, Expiry},
                  {priority, Prio}]).

%%% ==========================================================================
%%% Debugging Functions
%%% ==========================================================================

get_state(FsmRef) ->
    try
        gen_fsm:sync_send_all_state_event(FsmRef, get_state)
    catch
        exit:{noproc, _}  -> {error, noproc};
        exit:{timeout, _} -> {error, timeout}
    end.

get_state_name(FsmRef) ->
    try
        gen_fsm:sync_send_all_state_event(FsmRef, get_state_name)
    catch
        exit:{noproc, _}  -> {error, noproc};
        exit:{timeout, _} -> {error, timeout}
    end.

is_connected(FsmRef) ->
    try
        gen_fsm:sync_send_all_state_event(FsmRef, is_connected)
    catch
        exit:{noproc, _}  -> {error, noproc};
        exit:{timeout, _} -> {error, timeout}
    end.


%%% ==========================================================================
%%% Behaviour gen_fsm Standard Functions
%%% ==========================================================================

init([Name, Opts]) ->
    lager:info("APNS HTTP/2 session ~p started", [Name]),
    try
        process_flag(trap_exit, true),
        State = init_queue(init_state(Name, Opts)),
        bootstrap(State)
    catch
        _What:Why ->
            {stop, {Why, erlang:get_stacktrace()}}
    end.


handle_event(Event, StateName, State) ->
    lager:warning("Received unexpected event while ~p: ~p", [StateName, Event]),
    continue(StateName, State).


handle_sync_event(stop, _From, connecting, State) ->
    stop(connecting, normal, ok, State);

handle_sync_event(stop, From, disconnecting, #?S{stop_callers = L} = State) ->
    continue(disconnecting, State#?S{stop_callers = [From |L]});

handle_sync_event(stop, From, StateName, #?S{stop_callers = L} = State) ->
    next(StateName, disconnecting, State#?S{stop_callers = [From | L]});

handle_sync_event(get_state, _From, StateName, State) ->
    reply({ok, State}, StateName, State);

handle_sync_event(get_state_name, _From, StateName, State) ->
    reply({ok, StateName}, StateName, State);

handle_sync_event(is_connected, _From, StateName, State) ->
    reply({ok, StateName == connected}, StateName, State);

handle_sync_event(Event, {Pid, _Tag}, StateName, State) ->
    lager:warning("Received unexpected event from ~p while ~p: ~p",
                  [Pid, StateName, Event]),
    reply({error, invalid_event}, StateName, State).


handle_info({'EXIT', CrashPid, Reason}, StateName,
            #?S{http2_pid = Pid} = State) when CrashPid =:= Pid ->
    lager:error("HTTP/2 client ~p died while ~p: ~p",
                [Pid, StateName, Reason]),
    handle_connection_closure(StateName, State);
handle_info({'EXIT', Pid, Reason}, StateName, State) ->
    lager:error("Unknown process ~p died while ~p: ~p",
                [Pid, StateName, Reason]),
    continue(StateName, State);

handle_info(Info, StateName, State) ->
    lager:warning("Unexpected message received in state ~p: ~p",
                  [StateName, Info]),
    continue(StateName, State).


terminate(Reason, StateName, State) ->
    WaitingCallers = State#?S.stop_callers,
    lager:info("APNS HTTP/2 session ~p terminated in state ~p with ~w queued "
               "notifications: ~p",
               [State#?S.name, StateName, queue_length(State), Reason]),
    % Notify all senders that the notifications will not be sent.
    _ = [failure_callback(N, terminated) || N <- queue:to_list(State#?S.queue)],
    % Cleanup all we can.
    terminate_queue(State),
    % Notify the process wanting us dead.
    _ = [gen_fsm:reply(C, ok) || C <- WaitingCallers],
    ok.


code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.


%%% ==========================================================================
%%% Behaviour gen_fsm State Functions
%%% ==========================================================================

%% -----------------------------------------------------------------
%% Connecting State
%% -----------------------------------------------------------------
connecting({send, #nf{} = Nf}, State) ->
    continue(connecting, queue_notification(update_nf(Nf, State), State));

connecting(connect, State) ->
    #?S{name = Name, host = Host, port = Port, ssl_opts = Opts} = State,
    lager:info("APNS HTTP/2 session ~p connecting to ~s:~w",
               [Name, Host, Port]),
    case apns_connect(Host, Port, Opts) of
        {ok, Pid} ->
            lager:info("APNS HTTP/2 session ~p connected to ~s:~w "
                       "on HTTP/2 client pid ~p", [Name, Host, Port, Pid]),
            next(connecting, connected, State#?S{http2_pid = Pid});
        {error, {{badmatch, Reason}, _}} ->
            lager:error("APNS HTTP/2 session ~p failed to connect "
                        "to ~s:~w, probable configuration error: ~p",
                        [Name, Host, Port, Reason]),
            stop(connecting, Reason, State);
        {error, Reason} ->
            lager:error("APNS HTTP/2 session ~p failed to connect "
                        "to ~s:~w : ~p", [Name, Host, Port, Reason]),
            next(connecting, connecting, State)
    end;

connecting(Event, State) ->
    handle_event(Event, connecting, State).

connecting({send, #nf{} = Nf}, From, State) ->
    continue(connecting,
             queue_notification(update_nf(Nf, State, From), State));

connecting(Event, From, State) ->
    handle_sync_event(Event, From, connecting, State).


%% -----------------------------------------------------------------
%% Connected State
%% -----------------------------------------------------------------

connected(flush, State) ->
    {_, NewState} = flush_queued_notifications(State),
    continue(connected, NewState);

connected({send, #nf{} = Nf},  State) ->
    {_OkOrError, _Resp, NewState} = send_notification(update_nf(Nf, State),
                                                      State),
    continue(connected, NewState);

connected(Event, State) ->
    handle_event(Event, connected, State).

%% Sync send
connected({send, #nf{} = Nf}, From, State) ->
    case send_notification(update_nf(Nf, State, From), State) of
        {ok, Resp, NewState} ->
            reply({ok, Resp}, connected, NewState);
        {error, UUID, NewState} ->
            reply({error, UUID}, connected, NewState)
    end;

connected(Event, From, State) ->
    handle_sync_event(Event, From, connected, State).


%% -----------------------------------------------------------------
%% Disconnecting State
%% -----------------------------------------------------------------

disconnecting({send, #nf{} = Nf}, State) ->
    continue(disconnecting, queue_notification(update_nf(Nf, State), State));
disconnecting(disconnect, State) ->
    apns_disconnect(State#?S.http2_pid),
    continue(disconnecting, State);

disconnecting(Event, State) ->
    handle_event(Event, disconnecting, State).


disconnecting({send, #nf{} = Nf}, From, State) ->
    continue(disconnecting, queue_notification(update_nf(Nf, State, From),
                                               State));
disconnecting(Event, From, State) ->
    handle_sync_event(Event, From, disconnecting, State).


%%% ==========================================================================
%%% Internal Functions
%%% ==========================================================================

flush_queued_notifications(#?S{queue = Queue} = State) ->
    Now = sc_util:posix_time(),
    case queue:out(Queue) of
        {empty, NewQueue} ->
            {ok, State#?S{queue = NewQueue}};
        {{value, #nf{expiry = Exp} = Nf}, NewQueue} when Exp > Now ->
            case send_notification(Nf, State#?S{queue = NewQueue}) of
                {error, _UUID, NewState} ->
                    {error, NewState};
                {ok, _Resp, NewState} ->
                    success_callback(Nf),
                    flush_queued_notifications(NewState)
            end;
        {{value, #nf{} = Nf}, NewQueue} ->
            lager:debug("Notification ~s with token ~s expired",
                        [Nf#nf.id, tok_s(Nf)]),
            failure_callback(Nf, expired),
            flush_queued_notifications(State#?S{queue = NewQueue})
    end.


send_notification(#nf{id = UUID} = Nf, State) ->
    lager:debug("Sending notification ~p", [Nf]),
    case apns_send(State#?S.http2_pid, Nf) of
        {ok, Resp} ->
            check_uuid(UUID, Resp),
            {ok, Resp, State};
        {error, {{badmatch, Reason}, _}} ->
            lager:error("APNS HTTP/2 session ~p crashed "
                        "on notification ~w with token ~s: ~p",
                        [State#?S.name, UUID, tok_s(Nf), Reason]),
            {error, {UUID, Reason}, recover_notification(Nf, State)};
        {error, ParsedResponse} ->
            lager:error("APNS HTTP/2 session ~p failed to send "
                        "notification ~s with token ~s: ~p",
                        [State#?S.name, UUID, tok_s(Nf), ParsedResponse]),
            {error, {UUID, ParsedResponse},
             maybe_recover_notification(ParsedResponse, Nf, State)}
    end.


handle_connection_closure(StateName, State) ->
    apns_disconnect(State#?S.http2_pid),
    NewState = State#?S{http2_pid = undefined},
    case State#?S.stop_callers of
        [] ->
            next(StateName, connecting, NewState);
        _ ->
            stop(StateName, normal, NewState)
    end.


format(Tmpl, Args) ->
    iolist_to_binary(io_lib:format(Tmpl, Args)).


format_props(Props) ->
    iolist_to_binary(string:join([io_lib:format("~w=~p", [K, V])
                                  || {K, V} <- Props], ", ")).

maybe_recover_notification(ParsedResponse, Nf, State) ->
    case should_retry_notification(ParsedResponse) of
        true ->
            recover_notification(Nf, State);
        false ->
            State
    end.

-spec should_retry_notification(ParsedResponse) -> boolean() when
      ParsedResponse :: apns_lib_http2:parsed_rsp().

should_retry_notification(ParsedResponse) ->
    Status = pv(status, ParsedResponse, <<"missing status">>),
    should_retry_notification(Status, ParsedResponse).

should_retry_notification(<<"200">>, _ParsedResponse) -> false;
should_retry_notification(<<"400">>, _ParsedResponse) -> false;
should_retry_notification(<<"403">>, _ParsedResponse) -> false;
should_retry_notification(<<"405">>, _ParsedResponse) -> false;
should_retry_notification(<<"410">>, _ParsedResponse) -> false;
should_retry_notification(<<"413">>, _ParsedResponse) -> false;
should_retry_notification(<<"429">>, _ParsedResponse) -> true;
should_retry_notification(<<"500">>, _ParsedResponse) -> true;
should_retry_notification(<<"503">>, _ParsedResponse) -> true;
should_retry_notification(Status, ParsedResponse) ->
    lager:error("should_retry_notification, unhandled status ~s, "
                "parsed response: ~p", [Status, ParsedResponse]),
    throw({unhandled_status, [{file, ?FILE},
                              {line, ?LINE},
                              {status, Status},
                              {parsed_response, ParsedResponse}]})
    .

%%% --------------------------------------------------------------------------
%%% State Machine Functions
%%% --------------------------------------------------------------------------

-compile({inline, [bootstrap/1,
                   continue/2,
                   next/3,
                   reply/3,
                   stop/3,
                   stop/4,
                   leave/2,
                   transition/3,
                   enter/2]}).


%% -----------------------------------------------------------------
%% Bootstraps the state machine.
%% -----------------------------------------------------------------

-spec bootstrap(State) -> {ok, StateName, State}
    when StateName :: state_name(), State ::state().

bootstrap(State) ->
    gen_fsm:send_event(self(), connect),
    {ok, connecting, State}.


%% -----------------------------------------------------------------
%% Stays in the same state without triggering any transition.
%% -----------------------------------------------------------------

-spec continue(StateName, State) -> {next_state, StateName, State}
    when StateName :: state_name(), State ::state().

continue(StateName, State) ->
    {next_state, StateName, State}.


%% -----------------------------------------------------------------
%% Changes the current state triggering corresponding transition.
%% -----------------------------------------------------------------

-spec next(FromStateName, ToStateName, State) -> {next_state, StateName, State}
    when FromStateName :: state_name(), ToStateName ::state_name(),
         StateName ::state_name(), State ::state().

next(From, To, State) ->
    {next_state, To, enter(To, transition(From, To, leave(From, State)))}.


%% -----------------------------------------------------------------
%% Replies without changing the current state or triggering any transition.
%% -----------------------------------------------------------------

-spec reply(Reply, StateName, State) -> {reply, Reply, StateName, State}
    when Reply :: term(), StateName :: state_name(), State ::state().

reply(Reply, StateName, State) ->
    {reply, Reply, StateName, State}.


%% -----------------------------------------------------------------
%% Stops the process without reply.
%% -----------------------------------------------------------------

-spec stop(StateName, Reason, State) -> {stop, Reason, State}
    when StateName :: state_name(), State ::state(), Reason :: term().

stop(_StateName, Reason, State) ->
    {stop, Reason, State}.


%% -----------------------------------------------------------------
%% Stops the process with a reply.
%% -----------------------------------------------------------------

-spec stop(StateName, Reason, Reply, State) -> {stop, Reason, Reply, State}
    when StateName :: state_name(), Reason ::term(),
         Reply :: term(), State ::state().

stop(_StateName, Reason, Reply, State) ->
    {stop, Reason, Reply, State}.


%% -----------------------------------------------------------------
%% Performs actions when leaving a state.
%% -----------------------------------------------------------------

-spec leave(StateName, State) -> State
    when StateName :: state_name(), State ::state().

leave(connecting, State) ->
    % Cancel any scheduled reconnection.
    cancel_reconnect(State);

leave(_, State) ->
    State.


%% -----------------------------------------------------------------
%% Validate transitions and performs transition-specific actions.
%% -----------------------------------------------------------------

-spec transition(FromStateName, ToStateName, State) -> State
    when FromStateName :: state_name(), ToStateName ::state_name(),
         State ::state().

transition(connecting,    connecting,    State) -> State;
transition(connecting,    connected,     State) -> State;
transition(connected,     connecting,    State) -> State;
transition(connected,     disconnecting, State) -> State;
transition(disconnecting, connecting,    State) -> State.


%% -----------------------------------------------------------------
%% Performs actions when entering a state.
%% -----------------------------------------------------------------

-spec enter(StateName, State) -> State
    when StateName :: state_name(), State ::state().

enter(connecting, State) ->
    % Trigger the connection after an exponential delay.
    schedule_reconnect(State);

enter(connected, State) ->
    % Trigger the flush of queued notifications
    gen_fsm:send_event(self(), flush),
    % Reset the exponential delay
    reset_delay(State);

enter(disconnecting, State) ->
    % Trigger the disconnection when disconnecting.
    gen_fsm:send_event(self(), disconnect),
    State.


%%% --------------------------------------------------------------------------
%%% Option Validation Functions
%%% --------------------------------------------------------------------------

-compile({inline, [pv/2, pv/3, pv_req/2,
                   validate_list/2,
                   validate_binary/2,
                   validate_non_neg/2]}).


init_state(Name, Opts) ->
    {Host, Port, ApnsEnv} = validate_host_port_env(Opts),
    {SslOpts, CertData} = validate_ssl_opts(pv_req(ssl_opts, Opts)),
    BundleSeedId = validate_bundle_seed_id(Opts),
    {ok, ApnsTopic} = get_default_topic(Opts),
    maybe_validate_bundle(Opts, CertData, BundleSeedId, ApnsTopic),

    RetryDelay = validate_retry_delay(Opts),
    RetryMax = validate_retry_max(Opts),

    lager:debug("With options: host=~p, port=~w, "
                "retry_delay=~w, retry_max=~p, "
                "bundle_seed_id=~p, apns_topic=~p",
                [Host, Port,
                 RetryDelay, RetryMax,
                 BundleSeedId, ApnsTopic]),
    lager:debug("With SSL options: ~s", [format_props(SslOpts)]),

    #?S{name = Name,
        host = binary_to_list(Host), % h2_client requires a list
        port = Port,
        apns_env = ApnsEnv,
        apns_topic = ApnsTopic,
        bundle_seed_id = BundleSeedId,
        ssl_opts = SslOpts,
        retry_delay = RetryDelay,
        retry_max = RetryMax
       }.

validate_host_port_env(Opts) ->
    ApnsEnv = pv_req(apns_env, Opts),
    ?assert(lists:member(ApnsEnv, [prod, dev])),
    {DefHost, DefPort} = apns_lib_http2:host_port(ApnsEnv),
    Host = pv(host, Opts, DefHost),
    ?assertBinary(Host),
    Port = pv(port, Opts, DefPort),
    ?assertNonNegInt(Port),
    {Host, Port, ApnsEnv}.


-spec validate_ssl_opts(SslOpts) -> ValidOpts
    when SslOpts :: proplists:proplist(),
         ValidOpts :: {proplists:proplist(), CertData :: binary()}.

validate_ssl_opts(SslOpts) ->
    CertFile = ?assertList(pv_req(certfile, SslOpts)),
    CertData = ?assertReadFile(CertFile),
    KeyFile = ?assertList(pv_req(keyfile, SslOpts)),
    _ = ?assertReadFile(KeyFile),
    DefSslOpts = apns_lib_http2:make_ssl_opts(CertFile, KeyFile),
    {lists:ukeymerge(1, lists:sort(SslOpts), lists:sort(DefSslOpts)),
     CertData}.

%% This is disabling the bundle ID and bundle seed id checks,
%% not SSL checking.
maybe_validate_bundle(Opts, CertData, BundleSeedId, ApnsTopic) ->
    DisableCertVal = validate_boolean_opt(disable_apns_cert_validation,
                                          Opts, false),
    case DisableCertVal orelse ApnsTopic =:= undefined of
        true ->
            ok;
        false ->
            case apns_cert:validate(CertData, BundleSeedId, ApnsTopic) of
                ok ->
                    ok;
                {_ErrorClass, _Reason} = Reason ->
                    throw({bad_cert, Reason})
            end
    end.


-spec validate_boolean_opt(Name, Opts, Default) -> Value
    when Name :: atom(), Opts :: proplists:proplist(),
         Default :: boolean(), Value :: boolean().
validate_boolean_opt(Name, Opts, Default) ->
    validate_boolean(Name, pv(Name, Opts, Default)).

-spec validate_boolean(Name, Value) -> Value
    when Name :: atom(), Value :: boolean().
validate_boolean(Name, Bool) ->
    is_boolean(Bool) orelse throw({bad_options, {not_a_boolean, Name}}).


-spec validate_list(Name, Value) -> Value
    when Name :: atom(), Value :: list().
validate_list(_Name, List) when is_list(List) ->
    List;
validate_list(Name, _Other) ->
    throw({bad_options, {not_a_list, Name}}).


-spec validate_binary(Name, Value) -> Value
    when Name :: atom(), Value :: binary().
validate_binary(_Name, Bin) when is_binary(Bin) -> Bin;
validate_binary(Name, _Other) ->
    throw({bad_options, {not_a_binary, Name}}).

-spec validate_integer(Name, Value) -> Value
    when Name :: atom(), Value :: term().
validate_integer(_Name, Value) when is_integer(Value) -> Value;
validate_integer(Name, _Other) ->
    throw({bad_options, {not_an_integer, Name}}).

-spec validate_non_neg(Name, Value) -> Value
    when Name :: atom(), Value :: non_neg_integer().
validate_non_neg(_Name, Int) when is_integer(Int), Int >= 0 -> Int;
validate_non_neg(Name, Int) when is_integer(Int) ->
    throw({bad_options, {negative_integer, Name}});
validate_non_neg(Name, _Other) ->
    throw({bad_options, {not_an_integer, Name}}).


validate_host(Opts) ->
    validate_list(host, pv_req(host, Opts)).


validate_port(Opts) ->
    validate_non_neg(port, pv(port, Opts, ?DEFAULT_APNS_PORT)).


validate_bundle_seed_id(Opts) ->
    validate_binary(bundle_seed_id, pv_req(bundle_seed_id, Opts)).


validate_apns_topic(Opts) ->
    validate_binary(apns_topic, pv_req(apns_topic, Opts)).


validate_retry_delay(Opts) ->
    validate_non_neg(retry_delay, pv(retry_delay, Opts, ?DEFAULT_RETRY_DELAY)).


validate_retry_max(Opts) ->
    validate_non_neg(retry_max, pv(retry_max, Opts, ?DEFAULT_RETRY_MAX)).


pv(Key, PL) ->
    proplists:get_value(Key, PL).


pv(Key, PL, Default) ->
    proplists:get_value(Key, PL, Default).


pv_req(Key, PL) ->
    case pv(Key, PL) of
        undefined ->
            key_not_found_error(Key);
        Val ->
            Val
    end.

key_not_found_error(Key) ->
    throw({key_not_found, Key}).

%%% --------------------------------------------------------------------------
%%% Notification Creation Functions
%%% --------------------------------------------------------------------------

make_nf(Opts) ->
    #nf{id = get_id_opt(Opts),
        expiry = get_expiry_opt(Opts),
        token = get_token_opt(Opts),
        topic = pv(topic, Opts),
        json = get_json_opt(Opts),
        prio = get_prio_opt(Opts),
        from = undefined}.

update_nf(#nf{} = Nf, State) ->
    update_nf(#nf{} = Nf, State, undefined).

update_nf(#nf{topic = Topic} = Nf, State, From) ->
    Nf#nf{topic = sel_topic(Topic, State), from = From}.

success_callback(#nf{from = undefined}) -> ok;

success_callback(#nf{id = UUID, from = Caller}) ->
    gen_fsm:reply(Caller, {ok, UUID}).


failure_callback(#nf{from = undefined}, _Reason) -> ok;

failure_callback(#nf{from = Caller}, Reason) ->
    gen_fsm:reply(Caller, {error, Reason}).


%%% --------------------------------------------------------------------------
%%% History and Queue Managment Functions
%%% --------------------------------------------------------------------------
init_queue(#?S{queue = undefined} = State) ->
    State#?S{queue = queue:new()}.


terminate_queue(#?S{queue = Queue} = State) when Queue =/= undefined ->
    State#?S{queue = undefined}.


queue_length(State) ->
    queue:len(State#?S.queue).


queue_notification(Nf, #?S{queue = Queue} = State) ->
    State#?S{queue = queue:in(Nf, Queue)}.


recover_notification(Nf, #?S{queue = Queue} = State) ->
    State#?S{queue = queue:in_r(Nf, Queue)}.


%%% --------------------------------------------------------------------------
%%% Reconnection Delay Functions
%%% --------------------------------------------------------------------------

schedule_reconnect(#?S{retry_ref = Ref} = State) ->
    _ = (catch erlang:cancel_timer(Ref)),
    {Delay, NewState} = next_delay(State),
    lager:info("APNS HTTP/2 session ~p will reconnect in ~w ms",
               [State#?S.name, Delay]),
    NewRef = gen_fsm:send_event_after(Delay, connect),
    NewState#?S{retry_ref = NewRef}.


cancel_reconnect(#?S{retry_ref = Ref} = State) ->
    catch erlang:cancel_timer(Ref),
    State#?S{retry_ref = undefined}.


next_delay(#?S{retries = 0} = State) ->
    {0, State#?S{retries = 1}};

next_delay(State) ->
    #?S{retries = Retries, retry_delay = RetryDelay,
        retry_max = RetryMax} = State,
    Delay = RetryDelay * trunc(math:pow(2, (Retries - 1))),
    {min(RetryMax, Delay), State#?S{retries = Retries + 1}}.


reset_delay(State) ->
    % Reset to 1 so the first reconnection is always done after the retry delay.
    State#?S{retries = 1}.

%%% --------------------------------------------------------------------------
%%% APNS Handling Functions
%%% --------------------------------------------------------------------------

apns_connect(Host, Port, SslOpts) ->
    h2_client:start_link(https, Host, Port, SslOpts).

apns_disconnect(undefined) ->
    ok;
apns_disconnect(Http2Client) when is_pid(Http2Client) ->
    ok = h2_client:stop(Http2Client).

-spec apns_send(Http2Client, Nf) -> Resp
    when Http2Client :: pid(), Nf :: nf(),
         Resp :: {ok, apns_lib_http2:parsed_rsp()} | {error, term()}.
apns_send(Http2Client, Nf) when Http2Client =/= undefined ->
    Req = apns_lib_http2:make_req(Nf#nf.token, Nf#nf.json, nf_to_opts(Nf)),
    case send_impl(Http2Client, Req) of
        {ok, Resp} ->
            lager:debug("Got HTTP/2 response: ~p", [Resp]),
            ParsedResp = apns_lib_http2:parse_resp(Resp),
            case pv_req(status, ParsedResp) of
                <<"200">> ->
                    {ok, ParsedResp};
                _ErrorStatus ->
                    {error, ParsedResp}
            end;
        Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% The idea here is not to provide values that APNS will default,
%% so this could potentially return an empty list.
nf_to_opts(#nf{} = Nf) ->
    KVs = [
     {id, Nf#nf.id},
     %% NB: APNS and apns_lib_http2 use the keyword `expiration', so
     %% this translation is necessary.
     {expiration, Nf#nf.expiry},
     {priority, Nf#nf.prio},
     {topic, Nf#nf.topic}
    ],
    [{K, V} || {K, V} <- KVs, V /= undefined].


%%--------------------------------------------------------------------
check_uuid(UUID, Resp) ->
    case pv_req(id, Resp) of
        UUID ->
            ok;
        ActualUUID ->
            lager:warning("Unmatched UUIDs, expected: ~p actual: ~p\n",
                          [UUID, ActualUUID]),
            {error, {exp, UUID, act, ActualUUID}}
    end.

%%--------------------------------------------------------------------
-spec send_impl(Http2Client, Req) -> Result
    when Http2Client :: pid(), Req :: apns_lib_http2:http2_req(),
         Result :: {ok, apns_lib_http2:http2_rsp()} | {error, term()}.
send_impl(Http2Client, {ReqHdrs, ReqBody}) ->
    lager:debug("Sending synchronous request, headers: ~p\nBody: ~p\n",
                [ReqHdrs, ReqBody]),
    TStart = erlang:system_time(micro_seconds),
    try h2_client:sync_request(Http2Client, ReqHdrs, ReqBody) of
        {ok, {RespHdrs, RespBody}} = R ->
            lager:info("Received synchronous response, headers: ~p\n"
                        "Body: ~p\n", [RespHdrs, RespBody]),
            TEnd = erlang:system_time(micro_seconds),
            TElapsed = TEnd - TStart,
            lager:debug("Response time: ~B microseconds~n"
                        "Response headers: ~p~n"
                        "Response body: ~p~n",
                        [TElapsed, RespHdrs, RespBody]),
            R;
        Error ->
            lager:error("Error sending synchronous request, error: ~p\n"
                        "headers: ~p\nbody: ~p\n", [Error, ReqHdrs, ReqBody]),
            Error
    catch
        What:Why ->
            WW = {What, Why},
            lager:error("Exception sending synchronous request, error: ~p\n"
                        "headers: ~p\nbody: ~p\n", [WW, ReqHdrs, ReqBody]),
            Why
    end.

apns_deregister_token(Token) ->
    SvcTok = sc_push_reg_api:make_svc_tok(apns, Token),
    ok = sc_push_reg_api:deregister_svc_tok(SvcTok).

-spec tok_s(Token) -> BStr
    when Token :: nf() | binary() | string(), BStr :: bstrtok().
tok_s(#nf{token = Token}) ->
    tok_s(sc_util:to_bin(Token));
tok_s(Token) when is_list(Token) ->
    tok_s(sc_util:to_bin(Token));
tok_s(<<Token/binary>>) ->
    list_to_binary(sc_util:bitstring_to_hex(
                     apns_lib:maybe_encode_token(Token))
                  ).


%%--------------------------------------------------------------------
-spec get_default_topic(Opts) -> Result when
      Opts :: [{_,_}], Result :: {ok, binary()} | {error, term()}.
get_default_topic(Opts) ->
    ApnsTopic = pv(apns_topic, Opts),
    CertFile = pv_req(certfile, pv_req(ssl_opts, Opts)),
    {ok, CertData} = file:read_file(CertFile),
    #'OTPCertificate'{} = OTPCert = apns_cert:decode_cert(CertData),
    CertInfoMap = apns_cert:get_cert_info_map(OTPCert),
    #{subject_uid := SubjectUID, topics := Topics} = CertInfoMap,
    IsMultiTopics = is_list(Topics),
    %% - If there is a configured topic, use it as the default.
    %% - If there is no configured topic and the cert is single-topic,
    %%   use the cert subject UID as the default topic.
    %% - If there is no configured topic and this is a multi-topic
    %%   cert, there will be no default, so the topic must be provided
    %%   in the request. We will allow it if is not, and APNS will
    %%   yell at us then.
    case {ApnsTopic, IsMultiTopics} of
        {undefined, true} ->
            {ok, undefined};
        {undefined, false} ->
            {ok, ?assertBinary(SubjectUID)};
        {_, _} ->
            {ok, ?assertBinary(ApnsTopic)}
    end.

%% We want to default the id because it is also returned from
%% the async interface once it is validated and queued.
get_id_opt(Opts) ->
    case pv(id, Opts) of
        undefined ->
            apns_lib_http2:make_uuid();
        Id ->
            validate_binary(id, Id)
    end.

get_token_opt(Opts) ->
    validate_binary(token, pv_req(token, Opts)).

%% If topic is provided in Opts, it overrides
%% topic in State, otherwise we used the State
%% optic, even if it's `undefined'.
get_topic_opt(Opts, State) ->
    case pv(topic, Opts) of
        undefined ->
            State#?S.apns_topic;
        Topic ->
            Topic
    end.

get_json_opt(Opts) ->
    validate_binary(json, pv_req(json, Opts)).

get_prio_opt(Opts) ->
    pv(priority, Opts).

%% We need the default here because this is checked via pattern-matching when
%% requeuing notifications.
get_expiry_opt(Opts) ->
    pv(expiry, Opts, ?DEFAULT_EXPIRY_TIME).

sel_topic(undefined, State) ->
    State#?S.apns_topic;
sel_topic(Topic, _State) ->
    Topic.

