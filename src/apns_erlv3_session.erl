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
%%% There must be one session per App ID Suffix and certificate (Development or
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
%%% <dt>`host'</dt>
%%%   <dd>The hostname of the APNS HTTP/2 service as a binary string. This may
%%%       be omitted as long as `apns_env' is present. In this case, the code will
%%%       choose a default host using `apns_lib_http2:host_port/1' based on the
%%%       environment.
%%%   </dd>
%%%
%%% <dt>`port'</dt>
%%%   <dd>The port of the APNS HTTP/2 service as a positive integer. This may
%%%       be omitted as long as `apns_env' is present. In this case, the code will
%%%       choose a default port using `apns_lib_http2:host_port/1' based on the
%%%       environment.
%%%   </dd>
%%%
%%% <dt>`apns_env'</dt>
%%%   <dd>The push notification environment. This can be either `` 'dev' ''
%%%       or `` 'prod' ''. This is *mandatory*.
%%% </dd>
%%%
%%% <dt>`team_id'</dt>
%%%   <dd>The 10-character Team ID as a binary.  This is
%%%   used for one of two purposes:
%%%   <ul>
%%%    <li>To validate the APNS certificate unless
%%%    `disable_apns_cert_validation' is `true'.</li>
%%%    <li>When JWT authentication is active, it will be
%%%    used as the Issuer (iss) in the JWT.</li>
%%%    </ul>
%%%   </dd>
%%%
%%% <dt>`app_id_suffix'</dt>
%%%   <dd>The AppID Suffix as a binary, usually in reverse DNS format.  This is
%%%   used to validate the APNS certificate unless
%%%   `disable_apns_cert_validation' is `true'.  </dd>
%%%
%%% <dt>`apns_jwt_info'</dt>
%%%   <dd>`{Kid :: binary(), KeyFile :: binary()} | undefined'.  `Kid' is the
%%%   key id corresponding to the signind key.  `KeyFile' is the name of the
%%%   PEM-encoded JWT signing key to be used for authetication. This value is
%%%   mutually exclusive with `ssl_opts'.  If this value is provided and is not
%%%   `undefined', `ssl_opts' will be ignored.  </dd>
%%%
%%% <dt>`apns_topic'</dt>
%%%   <dd>The <b>default</b> APNS topic to which to push notifications. If a
%%%   topic is provided in the notification, it always overrides the default.
%%%   This must be one of the topics in `certfile', otherwise the notifications
%%%   will all fail, unless the topic is explicitly provided in the
%%%   notifications.
%%%   <br/>
%%%   If this is omitted and the certificate is a multi-topic certificate, the
%%%   notification will fail unless the topic is provided in the actual push
%%%   notification. Otherwise, with regular single-topic certificates, the
%%%   first app id suffix in `certfile' is used.
%%%   <br/>
%%%   Default value:
%%%     <ul>
%%%     <li>If multi-topic certificate: none (notification will fail)</li>
%%%     <li>If NOT multi-topic certificate: First app ID suffix in `certfile'</li>
%%%     </ul>
%%% </dd>
%%%
%%% <dt>`retry_strategy'</dt>
%%%   <dd>The strategy to be used when reattempting connection to APNS.
%%%   Valid values are `exponential' and `fixed'.
%%%   <ul>
%%%    <li>When `fixed', the same `retry_delay' is used for every reconnection attempt.</li>
%%%    <li>When `exponential', the `retry_delay' is multiplied by 2 after each
%%%   unsuccessful attempt, up to `retry_max'.</li>
%%%   </ul>
%%%   <br/>
%%%   Default value: `exponential'.
%%% </dd>
%%%
%%% <dt>`retry_delay'</dt>
%%%   <dd>The minimum time in milliseconds the session will wait before
%%%     reconnecting to APNS servers as an integer; when reconnecting multiple
%%%     times this value will be multiplied by 2 for every attempt if
%%%     `retry_strategy' is `exponential'.
%%%     <br/>
%%%     Default value: `1000'.
%%% </dd>
%%%
%%% <dt>`retry_max'</dt>
%%%   <dd>The maximum amount of time in milliseconds that the session will wait
%%%   before reconnecting to the APNS servers. This serves to put an upper
%%%   bound on `retry_delay', and only really makes sense if using a non-fixed
%%%   strategy.
%%%   <br/>
%%%   Default value: `60000'.
%%% </dd>
%%%
%%% <dt>`disable_apns_cert_validation'</dt>
%%%   <dd>`true' if APNS certificate validation against its app id suffix and
%%%   team ID should be disabled, `false' if the validation should be done.
%%%   This option exists to allow for changes in APNS certificate layout
%%%   without having to change code.
%%%   <br/>
%%%   Default value: `false'.
%%% </dd>
%%%
%%% <dt>`ssl_opts'</dt>
%%%   <dd>The property list of SSL options including the certificate file path.
%%%   See [http://erlang.org/doc/man/ssl.html].
%%% </dd>
%%% </dl>
%%%
%%% === Example configuration ===
%%% ```
%%% [{host, <<"api.push.apple.com">>},
%%%  {port, 443},
%%%  {apns_env, prod},
%%%  {apns_topic, <<"com.example.MyApp">>},
%%%  {apns_jwt_info, {<<"KEYID67890">>, <<"/path/to/private/key.pem">>}},
%%%  {app_id_suffix, <<"com.example.MyApp">>},
%%%  {team_id, <<"6F44JJ9SDF">>},
%%%  {retry_strategy, exponential},
%%%  {retry_delay, 1000},
%%%  {retry_max, 60000},
%%%  {disable_apns_cert_validation, false},
%%%  {ssl_opts,
%%%   [{certfile, "/some/path/com.example.MyApp.cert.pem"},
%%%    {keyfile, "/some/path/com.example.MyApp.key.unencrypted.pem"},
%%%    {cacertfile, "/etc/ssl/certs/ca-certificates.crt"},
%%%    {honor_cipher_order, false},
%%%    {versions, ['tlsv1.2']},
%%%    {alpn_preferred_protocols, [<<"h2">>]}].
%%%   ]}
%%% ]
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
-include("apns_erlv3_internal.hrl").


%%% ==========================================================================
%%% Exports
%%% ==========================================================================

%%% API Functions
-export([start/2,
         start_link/2,
         stop/1,
         quiesce/1,
         resume/1,
         reconnect/1,
         reconnect/2,
         send/2,
         send_cb/3,
         async_send/2,
         async_send/3,
         async_send_cb/4,
         sync_send_callback/3,
         async_send_callback/3
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
-export([validate_binary/1]).
-export([validate_boolean/1]).
-export([validate_integer/1]).
-export([validate_list/1]).
-export([validate_non_neg/1]).
-export([validate_enum/2]).


-export_type([
              async_send_reply/0,
              async_send_result/0,
              bstrtok/0,
              caller/0,
              cb_req/0,
              cb_result/0,
              fsm_ref/0,
              option/0,
              options/0,
              queued_result/0,
              reply_fun/0,
              send_callback/0,
              send_opt/0,
              send_opts/0,
              submitted_result/0,
              sync_result/0,
              sync_send_reply/0,
              sync_send_result/0,
              uuid_str/0
             ]).

%%% ==========================================================================
%%% Macros
%%% ==========================================================================

-define(S, ?MODULE).

%% Valid APNS priority values
-define(PRIO_IMMEDIATE,     10).
-define(PRIO_CONSERVE_POWER, 5).

-define(DEFAULT_APNS_PORT, 443).
-define(DEFAULT_RETRY_STRATEGY, exponential).
-define(DEFAULT_RETRY_DELAY, 1000).
-define(DEFAULT_RETRY_MAX, 60*1000).
-define(DEFAULT_EXPIRY_TIME, 16#7FFFFFFF). % INT_MAX, 32 bits
-define(DEFAULT_PRIO, ?PRIO_IMMEDIATE).

-define(REQ_STORE, ?MODULE).

%%% ==========================================================================
%%% Types
%%% ==========================================================================

-type state_name() :: connecting | connected | disconnecting.

-type cb_req() :: apns_lib_http2:http2_req().
-type cb_result() :: {ok, {uuid(), apns_lib_http2:parsed_rsp()}}
                   | {error, term()}.
-type send_callback() :: fun((list(), cb_req(), cb_result()) -> term()).
-type caller() :: pid() | {pid(), term()}.
-type uuid() :: binary(). % 128-bit raw UUID
-type uuid_str() :: apns_lib_http2:uuid_str().
-type reply_fun() :: fun((caller(), uuid(), cb_result()) -> none()).

-type option() :: {host, binary()} |
                  {port, non_neg_integer()} |
                  {app_id_suffix, binary()} |
                  {team_id, binary()} |
                  {apns_env, prod | dev} |
                  {apns_topic, binary()} |
                  {disable_apns_cert_validation, boolean()} |
                  {ssl_opts, list()} |
                  {retry_delay, non_neg_integer()} |
                  {retry_max, pos_integer()} |
                  {retry_strategy, fixed | exponential}.

-type options() :: [option()].
-type fsm_ref() :: atom() | pid().
-type bstrtok() :: binary(). %% binary of string rep of APNS token.

-type send_opt() :: {token, bstrtok()}
                  | {topic, binary()}
                  | {uuid, uuid_str()}
                  | {priority, integer()}
                  | {expiry, integer()}
                  | {json, binary()}
                  | {authorization, binary()}
                  .

-type send_opts() :: [send_opt()].

%% This result is returned when the notification is queued because
%% the session was temporarily in a disconnected state.
-type queued_result() :: {queued, uuid()}.

%% This result is returned immediately when the notification was submitted
%% asynchronously. The APNS response will be sent to the caller's process
%% as a message in the following format:
%% `{apns_response, v3, {uuid(), Resp :: cb_result()}}'
-type submitted_result() :: {submitted, uuid()}.

%% This result is returned from a synchronous send.
-type sync_result() :: {uuid(), apns_lib_http2:parsed_rsp()}.

-type async_send_result() :: queued_result() | submitted_result().
-type sync_send_result() :: sync_result().
-type sync_send_reply() :: {ok, sync_send_result()} | {error, term()}.
-type async_send_reply() :: {ok, async_send_result()} | {error, term()}.

%%% ==========================================================================
%%% Records
%%% ==========================================================================

-type jwt_ctx() :: apns_jwt:context().

%%% Process state
-record(?S,
        {name               = undefined                  :: atom(),
         http2_pid          = undefined                  :: pid() | undefined,
         host               = ""                         :: string(),
         port               = ?DEFAULT_APNS_PORT         :: non_neg_integer(),
         app_id_suffix      = <<>>                       :: binary(),
         apns_auth          = <<>>                       :: binary(), % current JWT
         apns_env           = undefined                  :: prod | dev,
         apns_topic         = <<>>                       :: undefined | binary(),
         jwt_ctx            = undefined                  :: undefined | jwt_ctx(),
         ssl_opts           = []                         :: list(),
         retry_strategy     = ?DEFAULT_RETRY_STRATEGY    :: exponential | fixed,
         retry_delay        = ?DEFAULT_RETRY_DELAY       :: non_neg_integer(),
         retry_max          = ?DEFAULT_RETRY_MAX         :: non_neg_integer(),
         retry_ref          = undefined                  :: reference() | undefined,
         retries            = 1                          :: non_neg_integer(),
         queue              = undefined                  :: sc_queue() | undefined,
         stop_callers       = []                         :: list(),
         quiesced           = false                      :: boolean(),
         req_store          = undefined                  :: term()
        }).

-type state() :: #?S{}.

%% Notification
-record(nf,
        {uuid           = <<>>                   :: undefined | uuid_str(),
         expiry         = 0                      :: non_neg_integer(),
         token          = <<>>                   :: binary(),
         topic          = <<>>                   :: undefined | binary(), % APNS topic/app id suffix
         json           = <<>>                   :: binary(),
         from           = undefined              :: undefined | term(),
         prio           = ?DEFAULT_PRIO          :: non_neg_integer(),
         cb             = undefined              :: undefined | send_callback()
        }).

-type nf() :: #nf{}.

-record(apns_erlv3_req,
        {stream_id      = undefined              :: term(),
         nf             = #nf{}                  :: nf(),
         req            = {[], <<>>}             :: apns_lib_http2:http2_req()
        }).

-type apns_erlv3_req() :: #apns_erlv3_req{}.

%% Note on prio field.
%%
%% Apple documentation states:
%%
%% The remote notification must trigger an alert, sound, or badge on the
%% device. It is an error to use this priority for a push that contains only
%% the content-available key.

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
%% If `id' is not provided in `Opts', generate a UUID.  When a response is
%% received from APNS, send it to the caller's process as a message in the
%% format `{apns_response, v3, {uuid(), Resp :: cb_result()}}'.
%% @end
%%--------------------------------------------------------------------
-spec async_send(FsmRef, Opts) -> Result when
      FsmRef :: fsm_ref(), Opts :: send_opts(),
      Result :: async_send_reply().
async_send(FsmRef, Opts) when is_list(Opts) ->
    async_send(FsmRef, self(), Opts).

%%--------------------------------------------------------------------
%% @doc Asynchronously send notification in `Opts'.
%% If `id' is not provided in `Opts', generate a UUID.  When a response is
%% received from APNS, send it to the caller's process as a message in the
%% format `{apns_response, v3, {uuid(), Resp :: cb_result()}}'.
%% @see async_send/1
%% @end
%%--------------------------------------------------------------------
-spec async_send(FsmRef, ReplyPid, Opts) -> Result when
      FsmRef :: fsm_ref(), ReplyPid :: pid(), Opts :: send_opts(),
      Result :: async_send_reply().
async_send(FsmRef, ReplyPid, Opts) when is_pid(ReplyPid), is_list(Opts) ->
    async_send_cb(FsmRef, ReplyPid, Opts, fun async_send_callback/3).

%%--------------------------------------------------------------------
%% @doc Asynchronously send notification in `Opts' with user-defined
%% callback function. If `id' is not provided in `Opts', generate a UUID.
%% When the request has completed, invoke the user-defined callback
%% function.
%%
%% Note that there are different returns depending on the state of the
%% session.
%%
%% If the session has been quiesced by calling quiesce/1, all
%% subsequent attempts to send notifications will receive `{error, quiesced}'
%% responses.
%%
%% If the session is busy connecting to APNS (or disconnecting from APNS),
%% attempts to send will receive a response, `{ok, {queued, UUID ::
%% binary()}}'. The `queued' status means that the notification is being held
%% until the session is able to connect to APNS, at which time it will be
%% submitted. Queued notifications can be lost if the session is stopped
%% without connecting.
%%
%% If the session is already connected (and not quiesced), and the notification
%% passes preliminary validation, attempts to send will receive a response
%% `{ok, {submitted, UUID :: binary()}}'.  This means that the notification has
%% been accepted by the HTTP/2 client for asynchronous processing, and the
%% callback function will be invoked at completion.
%%
%% == Timeouts ==
%%
%% There are multiple kinds of timeouts.
%%
%% If the session itself is so busy that the send request cannot be processed in time,
%% a timeout error will occur. The default Erlang call timeout is applicable here.
%%
%% An asynchronous timeout feature is planned but not currently implemented.
%%
%% == Callback function ==
%%
%% The callback function provided must have the following form:
%%
%% ```
%% fun(NfPL, Req, Resp) -> any().
%% '''
%%
%% The function return value is ignored. Throw an exception or raise an error
%% to indicate callback failure instead.
%%
%% === Function Parameters ===
%%
%% <dl>
%%   <dt>`NfPL :: [{atom(), binary() | non_neg_integer() | {pid(), any()}'</dt>
%%     <dd>The notification data as a proplist. See below for a description.</dd>
%%   <dt>`Req :: {Headers :: [{binary(), binary()}], Body :: binary()}'</dt>
%%     <dd>The original request headers and data</dd>
%%   <dt>`Resp :: {ok, {uuid(), ParsedRsp}} | {error, any()}'</dt>
%%     <dd>The APNS response.  See "Parsed Response Property List" below for
%%     more detail.</dd>
%% </dl>
%%
%% **Sample request headers**
%%
%% ```
%% [
%%  {<<":method">>, <<"POST">>},
%%  {<<":path">>, <<"/3/device/ca6a7fef19bcf22c38d5bee0c29f80d9461b2848061f0f4f0c0d361e4c4f1dc2">>},
%%  {<<":scheme">>, <<"https">>},
%%  {<<"apns-topic">>, <<"com.example.FakeApp.voip">>},
%%  {<<"apns-expiration">>, <<"2147483647">>},
%%  {<<"apns-id">>, <<"519d99ac-1bb0-42df-8381-e6979ce7cd32">>}
%% ]
%% '''
%%
%% === Notification Property List ===
%%
%% ```
%%  [{uuid, binary()},              % Canonical UUID string
%%   {expiration, non_neg_integer()},
%%   {token, binary()},             % Hex string
%%   {topic, binary()},             % String
%%   {json, binary()},              % JSON string
%%   {from, {pid(), Tag :: any()}}, % Caller
%%   {priority, non_neg_integer()}
%%   ].
%% '''
%%
%% **Sample JSON string (formatted)**
%%
%% ```
%% {
%%   "aps": {
%%     "alert": "Some alert string",
%%     "content-available": 1
%%   }
%% }
%% '''
%%
%% === Parsed Response Property List ===
%%
%% The properties present in the list depend on the status code.
%%
%% <ul>
%%  <li><b>Always present</b>: `uuid', `status', `status_desc'.</li>
%%  <li><b>Also present for 4xx, 5xx status</b>: `reason', `reason_desc',
%%  `body'.</li>
%%  <li><b>Also present, but only for 410 status</b>: `timestamp',
%%  `timestamp_desc'.</li>
%% </ul>
%%
%% See `apns_lib_http2:parsed_rsp()'.
%%
%% ```
%% [
%%  {uuid, binary()},            % UUID string
%%  {status, binary()},          % HTTP/2 status string, e.g. <<"200">>.
%%  {status_desc, binary()},     % Status description string
%%  {reason, binary()},          % Reason string
%%  {reason_desc, binary()},     % Reason description
%%  {timestamp, non_neg_integer()},
%%  {timestamp_desc, binary()},  % Timestamp description
%%  {body, term()}               % Parsed APNS response body
%% ]
%% '''
%%
%% **Sample success return**
%%
%% ```
%% [
%%  {uuid,
%%   <<"d013d454-b1d0-469a-96d3-52e0c5ec4281">>},
%%  {status,<<"200">>},
%%  {status_desc,<<"Success">>}
%% ]
%% '''
%%
%% **Sample status 400 return**
%%
%% ```
%% [
%%  {uuid,<<"519d99ac-1bb0-42df-8381-e6979ce7cd32">>},
%%  {status,<<"400">>},
%%  {status_desc,<<"Bad request">>},
%%  {reason,<<"BadDeviceToken">>},
%%  {reason_desc,<<"The specified device token was bad...">>},
%%  {body,[{<<"reason">>,<<"BadDeviceToken">>}]}
%% ]
%% '''
%%
%% **Sample status 410 return**
%%
%% ```
%% [
%%  {uuid,<<"7824c0f2-a5e6-4c76-9699-45ac477e64d2">>},
%%  {status,<<"410">>},
%%  {status_desc,<<"The device token is no longer active for the topic.">>},
%%  {reason,<<"Unregistered">>},
%%  {reason_desc,<<"The device token is inactive for the specified topic.">>},
%%  {timestamp,1475784832119},
%%  {timestamp_desc,<<"2016-10-06T20:13:52Z">>},
%%  {body,[{<<"reason">>,<<"Unregistered">>},
%%         {<<"timestamp">>,1475784832119}]}
%% ]
%% '''
%%
%% @TODO: Implement async timeout.
%% @TODO: Implement stale request sweeps so that the request table doesn't become slowly
%% filled with entries that will never complete. A request that is swept must generate
%% a timeout error to the calling process, probably by invoking the callback function
%% with `{error, timeout}' or maybe `{error, stale_request}'.
%%
%% @end
%%--------------------------------------------------------------------
-spec async_send_cb(FsmRef, ReplyPid, Opts, Callback) -> Result when
      FsmRef :: fsm_ref(), ReplyPid :: pid(), Opts :: send_opts(),
      Callback :: send_callback(), Result :: async_send_reply().
async_send_cb(FsmRef, ReplyPid, Opts, Callback)
  when is_pid(ReplyPid), is_function(Callback, 3) ->
    try
        #nf{} = Nf = make_nf(Opts, ReplyPid, Callback),
        %% Even though the event is sent synchronously, the actual notification
        %% is sent asynchronously. The synchronous aspect is used to return
        %% error conditions that would prevent the notification from even
        %% being queued, such as if the session is quiescent.
        gen_fsm:sync_send_event(FsmRef, {send, async, Nf})
    catch
        _:Reason ->
            {error, {bad_notification,
                     [{mod, ?MODULE},
                      {line, ?LINE},
                      {send_opts, Opts},
                      {reason, Reason}]}}
    end.

%%--------------------------------------------------------------------
%% @doc Send a notification specified by `Nf' with options `Opts'.
%% @end
%%--------------------------------------------------------------------
-spec send(FsmRef, Opts) -> Result when
      FsmRef :: fsm_ref(), Opts :: send_opts(),
      Result :: sync_send_reply().
send(FsmRef, Opts) when is_list(Opts) ->
    send_cb(FsmRef, Opts, fun sync_send_callback/3).

%%--------------------------------------------------------------------
%% @doc Send a notification specified by `Nf' and a user-supplied callback
%% function.
%% @end
%%--------------------------------------------------------------------
-spec send_cb(FsmRef, Opts, Callback) -> Result when
      FsmRef :: fsm_ref(), Opts :: send_opts(), Callback :: send_callback(),
      Result :: sync_send_reply().
send_cb(FsmRef, Opts, Callback) when is_list(Opts) andalso
                                     is_function(Callback, 3) ->
    ?LOG_DEBUG("Sending sync notification ~p", [Opts]),
    try
        #nf{} = Nf = make_nf(Opts, undefined, Callback),
        ?LOG_DEBUG("Sending sync notification ~p", [Nf]),
        try_send(FsmRef, sync, Nf)
    catch
        Class:Reason ->
            ?LOG_ERROR("Bad notification, opts: ~p\nStacktrace: ~s",
                       [Opts, ?STACKTRACE(Class, Reason)]),
            {error, {bad_notification,
                     [{mod, ?MODULE},
                      {line, ?LINE},
                      {send_opts, Opts},
                      {reason, Reason}]}}
    end.

%%--------------------------------------------------------------------
%% @doc Quiesce a session. This put sthe session into a mode
%% where all subsequent requests are rejected with `{error, quiesced}'.
%% @end
%%--------------------------------------------------------------------
-spec quiesce(FsmRef) -> Result when
      FsmRef :: fsm_ref(), Result :: ok | {error, term()}.
quiesce(FsmRef) ->
    try_sync_send_all_state_event(FsmRef, quiesce).

%%--------------------------------------------------------------------
%% @doc Resume a quiesced session.
%% @see quiesce/1
%% @end
%%--------------------------------------------------------------------
-spec resume(FsmRef) -> Result when
      FsmRef :: fsm_ref(), Result :: ok | {error, term()}.
resume(FsmRef) ->
    try_sync_send_all_state_event(FsmRef, resume).

%%--------------------------------------------------------------------
%% @doc Standard sync callback function. This is not normally needed
%% outside of this module.
%% @see send_cb/1
%% @end
%%--------------------------------------------------------------------
-spec sync_send_callback(NfPL, Req, Resp) -> Result when
      NfPL :: [{atom(), term()}], Req :: cb_req(), Resp :: cb_result(),
      Result :: cb_result().
sync_send_callback(NfPL, Req, Resp) ->
    gen_send_callback(fun sync_reply/3, NfPL, Req, Resp).

%%--------------------------------------------------------------------
%% @doc Standard async callback function. This is not normally needed
%% outside of this module.
%% @see async_send_cb/1
%% @end
%%--------------------------------------------------------------------
-spec async_send_callback(NfPL, Req, Resp) -> Result when
      NfPL :: [{atom(), term()}], Req :: cb_req(), Resp :: cb_result(),
      Result :: cb_result().
async_send_callback(NfPL, Req, Resp) ->
    gen_send_callback(fun async_reply/3, NfPL, Req, Resp).

%%% ==========================================================================
%%% Debugging Functions
%%% ==========================================================================

%%--------------------------------------------------------------------
%% @doc Immediately disconnect the session and reconnect.
%% @end
%%--------------------------------------------------------------------
reconnect(FsmRef) ->
    reconnect(FsmRef, 0).

%%--------------------------------------------------------------------
%% @doc Immediately disconnect the session and reconnect after `Delay' ms.
%% @end
%%--------------------------------------------------------------------
reconnect(FsmRef, Delay) when is_integer(Delay), Delay >= 0 ->
    try_sync_send_all_state_event(FsmRef, {force_reconnect, Delay}).

%%--------------------------------------------------------------------
%% @doc Get the current state of the FSM.
%% @end
%%--------------------------------------------------------------------
get_state(FsmRef) ->
    try_sync_send_all_state_event(FsmRef, get_state).

%%--------------------------------------------------------------------
%% @doc Get the name of the current state of the FSM.
%% @end
%%--------------------------------------------------------------------
get_state_name(FsmRef) ->
    try_sync_send_all_state_event(FsmRef, get_state_name).

%%--------------------------------------------------------------------
%% @doc Return `true' if the session is connected, `false' otherwise.
%% @end
%%--------------------------------------------------------------------
is_connected(FsmRef) ->
    try_sync_send_all_state_event(FsmRef, is_connected).

%%% ==========================================================================
%%% Behaviour gen_fsm Standard Functions
%%% ==========================================================================

%% @private
init([Name, Opts]) ->
    ?LOG_INFO("APNS HTTP/2 session ~p started", [Name]),
    try
        process_flag(trap_exit, true),
        State = init_queue(init_state(Name, Opts)),
        bootstrap(State)
    catch
        Class:Reason ->
            ?LOG_CRITICAL("Init failed on APNS HTTP/2 session ~p\n"
                          "Stacktrace:~s",
                          [Name, ?STACKTRACE(Class, Reason)]),
            {stop, {Reason, erlang:get_stacktrace()}}
    end.


%% @private
handle_event(Event, StateName, State) ->
    ?LOG_WARNING("Received unexpected event while ~p: ~p", [StateName, Event]),
    continue(StateName, State).


%% @private
handle_sync_event({force_reconnect, Delay}, From, StateName, State) ->
    _ = apns_disconnect(State#?S.http2_pid),
    NewState = State#?S{retry_strategy = fixed,
                        retry_delay = Delay},
    gen_fsm:reply(From, ok),
    next(StateName, connecting, NewState);

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

handle_sync_event(quiesce, _From, StateName, State) ->
    reply(ok, StateName, State#?S{quiesced = true});

handle_sync_event(resume, _From, StateName, State) ->
    reply(ok, StateName, State#?S{quiesced = false});

handle_sync_event(Event, {Pid, _Tag}, StateName, State) ->
    ?LOG_WARNING("Received unexpected sync event from ~p while ~p: ~p",
                 [Pid, StateName, Event]),
    reply({error, invalid_event}, StateName, State).


%% @private
handle_info({'EXIT', CrashPid, normal}, StateName,
            #?S{http2_pid = Pid} = State) when CrashPid =:= Pid ->
    ?LOG_INFO("HTTP/2 client ~p died normally while ~p",
              [Pid, StateName]),
    handle_connection_closure(StateName, State);
handle_info({'EXIT', CrashPid, Reason}, StateName,
            #?S{http2_pid = Pid} = State) when CrashPid =:= Pid ->
    ?LOG_WARNING("HTTP/2 client ~p died while ~p, reason: ~p",
                [Pid, StateName, Reason]),
    handle_connection_closure(StateName, State);
handle_info({'EXIT', Pid, Reason}, StateName, State) ->
    ?LOG_NOTICE("Unknown process ~p died while ~p: ~p",
                [Pid, StateName, Reason]),
    continue(StateName, State);
handle_info({'END_STREAM', StreamId}, StateName, State) ->
    ?LOG_DEBUG("HTTP/2 end of stream id ~p while ~p", [StreamId, StateName]),
    NewState = handle_end_of_stream(StreamId, StateName, State),
    continue(StateName, NewState);
handle_info(Info, StateName, State) ->
    ?LOG_WARNING("Unexpected message received in state ~p: ~p",
                 [StateName, Info]),
    continue(StateName, State).


%% @private
terminate(Reason, StateName, State) ->
    WaitingCallers = State#?S.stop_callers,
    QueueLen = queue_length(State),
    Fmt = ("Session terminated: APNS HTTP/2 session ~p, state ~p with ~w "
           "queued notifications, reason: ~p"),
    Args = [State#?S.name, StateName, QueueLen, Reason],
    case QueueLen of
        0 -> ?LOG_INFO(Fmt, Args);
        _ -> ?LOG_ERROR(Fmt, Args)
    end,

    % Notify all senders that the notifications will not be sent.
    _ = [notify_failure(N, terminated) || N <- queue:to_list(State#?S.queue)],
    % Cleanup all we can.
    terminate_queue(State),
    % Notify the processes wanting us dead.
    _ = [gen_fsm:reply(C, ok) || C <- WaitingCallers],
    ok = req_store_delete(State#?S.req_store),
    ok.


%% @private
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.


%%% ==========================================================================
%%% Behaviour gen_fsm State Functions
%%% ==========================================================================

%% -----------------------------------------------------------------
%% Connecting State
%% -----------------------------------------------------------------
%% @private
connecting(connect, State) ->
    #?S{name = Name, host = Host, port = Port, ssl_opts = Opts} = State,
    ?LOG_INFO("Connecting APNS HTTP/2 session ~p to ~s:~w",
              [Name, Host, Port]),
    case apns_connect(Host, Port, Opts) of
        {ok, Pid} ->
            ?LOG_INFO("Connected APNS HTTP/2 session ~p to ~s:~w "
                      "on HTTP/2 client pid ~p", [Name, Host, Port, Pid]),
            next(connecting, connected, State#?S{http2_pid = Pid});
        {error, {{badmatch, Reason}, _}} ->
            ?LOG_CRITICAL("Connection failed for APNS HTTP/2 session ~p, "
                          "host:port ~s:~w, probable configuration error: ~p",
                          [Name, Host, Port, Reason]),
            stop(connecting, Reason, State);
        {error, Reason} ->
            ?LOG_ERROR("Connection failed for APNS HTTP/2 session ~p, "
                       "host:port ~s:~w\nReason: ~p",
                       [Name, Host, Port, Reason]),
            next(connecting, connecting, State)
    end;

connecting(Event, State) ->
    handle_event(Event, connecting, State).

%% @private
connecting({send, _Mode, _ = #nf{}}, _From, #?S{quiesced = true} = State) ->
    reply({error, quiesced}, connecting, State);
connecting({send, sync, #nf{} = Nf}, From, State) ->
    continue(connecting,
             queue_nf(update_nf(Nf, State, From), State));
connecting({send, async, #nf{} = Nf}, From, State) ->
    reply({ok, {queued, str_to_uuid(Nf#nf.uuid)}}, connecting,
          queue_nf(update_nf(Nf, State, From), State));
connecting(Event, From, State) ->
    handle_sync_event(Event, From, connecting, State).


%% -----------------------------------------------------------------
%% Connected State
%% -----------------------------------------------------------------

%% @private
connected(flush, State) ->
    {_, NewState} = flush_queued_notifications(State),
    continue(connected, NewState);
connected(Event, State) ->
    handle_event(Event, connected, State).


%% @private
connected({send, _Mode, _ = #nf{}}, _From, #?S{quiesced = true} = State) ->
    reply({error, quiesced}, connected, State);
connected({send, sync, #nf{} = Nf}, From, State) ->
    case send_notification(update_nf(Nf, State, From), sync, State) of
        {ok, {submitted, _UUID}, NewState} ->
            continue(connected, NewState);
        {error, ErrorInfo, NewState} -> % Reply immediately on error
            reply({error, ErrorInfo}, connected, NewState)
    end;
connected({send, async, #nf{} = Nf}, From, State) ->
    case send_notification(update_nf(Nf, State, From), async, State) of
        {ok, Resp, NewState} ->
            reply({ok, Resp}, connected, NewState);
        {error, ErrorInfo, NewState} ->
            reply({error, ErrorInfo}, connected, NewState)
    end;

connected(Event, From, State) ->
    handle_sync_event(Event, From, connected, State).


%% -----------------------------------------------------------------
%% Disconnecting State
%% -----------------------------------------------------------------

%% @private
disconnecting(disconnect, State) ->
    apns_disconnect(State#?S.http2_pid),
    continue(disconnecting, State);
disconnecting(Event, State) ->
    handle_event(Event, disconnecting, State).


%% @private
disconnecting({send, _Mode, _ = #nf{}}, _From, #?S{quiesced = true} = State) ->
    reply({error, quiesced}, disconnecting, State);
disconnecting({send, sync, #nf{} = Nf}, From, State) ->
    continue(disconnecting, queue_nf(update_nf(Nf, State, From), State));
disconnecting({send, async, #nf{} = Nf}, From, State) ->
    reply({ok, {queued, str_to_uuid(Nf#nf.uuid)}}, disconnecting,
          queue_nf(update_nf(Nf, State, From), State));
disconnecting(Event, From, State) ->
    handle_sync_event(Event, From, disconnecting, State).


%%% ==========================================================================
%%% Internal Functions
%%% ==========================================================================

%% @private
flush_queued_notifications(#?S{queue = Queue} = State) ->
    Now = sc_util:posix_time(),
    case queue:out(Queue) of
        {empty, NewQueue} ->
            {ok, State#?S{queue = NewQueue}};
        {{value, #nf{expiry = Exp} = Nf}, NewQueue} when Exp > Now ->
            case send_notification(Nf, sync, State#?S{queue = NewQueue}) of
                {ok, _Resp, NewState} ->
                    flush_queued_notifications(NewState);
                {error, _ErrorInfo, NewState} ->
                    {error, NewState}
            end;
        {{value, #nf{} = Nf}, NewQueue} ->
            ?LOG_NOTICE("Notification ~s with token ~s expired",
                        [Nf#nf.uuid, tok_s(Nf)]),
            notify_failure(Nf, expired),
            flush_queued_notifications(State#?S{queue = NewQueue})
    end.


%% @private
-spec send_notification(Nf, Mode, State) -> Result when
      Nf :: nf(), Mode :: async | sync, State :: state(),
      Result :: {ok, {submitted, UUID}, NewState} |
                {error, {UUID, {badmatch, Reason}}, NewState} |
                {error, {UUID, ParsedResponse}, NewState},
      UUID :: uuid(), NewState :: state(),
      Reason :: term(), ParsedResponse :: apns_lib_http2:parsed_rsp().
send_notification(#nf{uuid = UUIDStr} = Nf, Mode, State) ->
    ?LOG_DEBUG("Sending ~p notification: ~p", [Mode, Nf]),
    UUID = str_to_uuid(UUIDStr),
    case apns_send(Nf, State) of
        {ok, StreamId} ->
            ?LOG_DEBUG("Submitted ~p notification ~s on stream ~p",
                       [Mode, UUIDStr, StreamId]),
            {ok, {submitted, UUID}, State};
        {error, {{badmatch, _} = Reason, _}} ->
            ?LOG_ERROR("Crashed on notification ~w, APNS HTTP/2 session ~p"
                       " with token ~s: ~p",
                       [UUIDStr, State#?S.name, tok_s(Nf), Reason]),
            {error, {UUID, Reason}, recover_notification(Nf, State)};
        {error, ParsedResponse} ->
            ?LOG_WARNING("Failed to send notification ~s on APNS HTTP/2 "
                         "session ~p with token ~s:\n~p",
                         [UUIDStr, State#?S.name, tok_s(Nf), ParsedResponse]),
            {error, {UUID, ParsedResponse},
             maybe_recover_notification(ParsedResponse, Nf, State)}
    end.


%% @private
handle_connection_closure(StateName, State) ->
    apns_disconnect(State#?S.http2_pid),
    NewState = State#?S{http2_pid = undefined},
    case State#?S.stop_callers of
        [] ->
            next(StateName, connecting, NewState);
        _ ->
            stop(StateName, normal, NewState)
    end.


%% @private
format_props(Props) ->
    iolist_to_binary(string:join([io_lib:format("~w=~p", [K, V])
                                  || {K, V} <- Props], ", ")).

%% @private
maybe_recover_notification(undefined, _Nf, State) ->
    State;
maybe_recover_notification(ParsedResponse, Nf, State) ->
    case should_retry_notification(ParsedResponse) of
        true ->
            recover_notification(Nf, State);
        false ->
            State
    end.

%% @private
-spec should_retry_notification(ParsedResponse) -> boolean() when
      ParsedResponse :: apns_lib_http2:parsed_rsp().

should_retry_notification(ParsedResponse) ->
    Status = pv(status, ParsedResponse, <<"missing status">>),
    should_retry_notification(Status, ParsedResponse).

%% @private
should_retry_notification(<<"400">>, _ParsedResponse) -> false;
should_retry_notification(<<"403">>, _ParsedResponse) -> false;
should_retry_notification(<<"405">>, _ParsedResponse) -> false;
should_retry_notification(<<"410">>, _ParsedResponse) -> false;
should_retry_notification(<<"413">>, _ParsedResponse) -> false;
should_retry_notification(<<"429">>, _ParsedResponse) -> true;
should_retry_notification(<<"500">>, _ParsedResponse) -> true;
should_retry_notification(<<"503">>, _ParsedResponse) -> true;
should_retry_notification(Status, ParsedResponse) ->
    ?LOG_ERROR("should_retry_notification, unhandled status ~s, "
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

%% @private
bootstrap(State) ->
    gen_fsm:send_event(self(), connect),
    {ok, connecting, State}.


%% -----------------------------------------------------------------
%% Stays in the same state without triggering any transition.
%% -----------------------------------------------------------------

-spec continue(StateName, State) -> {next_state, StateName, State}
    when StateName :: state_name(), State ::state().

%% @private
continue(StateName, State) ->
    {next_state, StateName, State}.


%% -----------------------------------------------------------------
%% Changes the current state triggering corresponding transition.
%% -----------------------------------------------------------------

-spec next(FromStateName, ToStateName, State) -> {next_state, StateName, State}
    when FromStateName :: state_name(), ToStateName ::state_name(),
         StateName ::state_name(), State ::state().

%% @private
next(From, To, State) ->
    {next_state, To, enter(To, transition(From, To, leave(From, State)))}.


%% -----------------------------------------------------------------
%% Replies without changing the current state or triggering any transition.
%% -----------------------------------------------------------------

-spec reply(Reply, StateName, State) -> {reply, Reply, StateName, State}
    when Reply :: term(), StateName :: state_name(), State ::state().

%% @private
reply(Reply, StateName, State) ->
    {reply, Reply, StateName, State}.


%% -----------------------------------------------------------------
%% Stops the process without reply.
%% -----------------------------------------------------------------

-spec stop(StateName, Reason, State) -> {stop, Reason, State}
    when StateName :: state_name(), State ::state(), Reason :: term().

%% @private
stop(_StateName, Reason, State) ->
    {stop, Reason, State}.


%% -----------------------------------------------------------------
%% Stops the process with a reply.
%% -----------------------------------------------------------------

-spec stop(StateName, Reason, Reply, State) -> {stop, Reason, Reply, State}
    when StateName :: state_name(), Reason ::term(),
         Reply :: term(), State ::state().

%% @private
stop(_StateName, Reason, Reply, State) ->
    {stop, Reason, Reply, State}.


%% -----------------------------------------------------------------
%% Performs actions when leaving a state.
%% -----------------------------------------------------------------

-spec leave(StateName, State) -> State
    when StateName :: state_name(), State ::state().

%% @private
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

%% @private
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

%% @private
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

%% @private
init_state(Name, Opts) ->
    {Host, Port, ApnsEnv} = validate_host_port_env(Opts),
    AppIdSuffix = validate_app_id_suffix(Opts),
    {ok, ApnsTopic} = get_default_topic(Opts),
    TeamId = validate_team_id(Opts),
    {SslOpts, JwtCtx} = get_auth_info(AppIdSuffix, TeamId, Opts),

    RetryStrategy = validate_retry_strategy(Opts),
    RetryDelay = validate_retry_delay(Opts),
    RetryMax = validate_retry_max(Opts),

    ?LOG_DEBUG("With options: host=~p, port=~w, "
               "retry_strategy=~w, retry_delay=~w, retry_max=~p, "
               "app_id_suffix=~p, apns_topic=~p",
               [Host, Port,
                RetryStrategy, RetryDelay, RetryMax,
                TeamId, ApnsTopic]),
    ?LOG_DEBUG("With SSL options: ~s", [format_props(SslOpts)]),

    #?S{name = Name,
        host = binary_to_list(Host), % h2_client requires a list
        port = Port,
        apns_auth = make_apns_auth(JwtCtx),
        apns_env = ApnsEnv,
        apns_topic = ApnsTopic,
        app_id_suffix = AppIdSuffix,
        jwt_ctx = JwtCtx,
        ssl_opts = SslOpts,
        retry_strategy = RetryStrategy,
        retry_delay = RetryDelay,
        retry_max = RetryMax,
        req_store = req_store_new(?REQ_STORE)
       }.


-spec get_auth_info(AppIdSuffix, TeamId, Opts) -> Result when
      AppIdSuffix :: binary(), TeamId :: binary(), Opts :: send_opts(),
      Result :: {SslOpts, JwtCtx},
      SslOpts :: list(), JwtCtx :: undefined | jwt_ctx().
get_auth_info(AppIdSuffix, TeamId, Opts) ->
    case pv(apns_jwt_info, Opts) of
        {<<Kid/binary>>, <<KeyFile/binary>>} ->
            SigningKey = validate_jwt_keyfile(KeyFile),
            JwtCtx = apns_jwt:new(Kid, TeamId, SigningKey),
            SslOpts = minimal_ssl_opts(),
            {SslOpts, JwtCtx};
        undefined ->
            {SslOpts, CertData} = validate_ssl_opts(pv_req(ssl_opts, Opts)),
            maybe_validate_apns_cert(Opts, CertData, AppIdSuffix, TeamId),
            {SslOpts, undefined}
    end.

%% @private
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

%% @private
%% Either we are doing JWT-based authentication or cert-based.
%% If JWT-based, we don't want certfile or keyfile.
validate_ssl_opts(SslOpts) ->
    CertFile = ?assertList(pv_req(certfile, SslOpts)),
    CertData = ?assertReadFile(CertFile),
    KeyFile = ?assertList(pv_req(keyfile, SslOpts)),
    _ = ?assertReadFile(KeyFile),
    DefSslOpts = apns_lib_http2:make_ssl_opts(CertFile, KeyFile),
    {lists:ukeymerge(1, lists:sort(SslOpts), lists:sort(DefSslOpts)),
     CertData}.

validate_jwt_keyfile(KeyFile) ->
    ?assertReadFile(sc_util:to_list(KeyFile)).

%% This is disabling the Team ID and AppID Suffix checks. It does not affect
%% SSL validation.
%% @private
maybe_validate_apns_cert(Opts, CertData, AppIdSuffix, TeamId) ->
    DisableCertVal = validate_boolean_opt(disable_apns_cert_validation,
                                          Opts, false),
    case DisableCertVal of
        true ->
            ok;
        false ->
            case apns_cert:validate(CertData, AppIdSuffix, TeamId) of
                ok ->
                    ok;
                {_ErrorClass, _Reason} = Reason ->
                    throw({bad_cert, Reason})
            end
    end.

-compile({inline, [pv/2, pv/3, pv_req/2,
                   kv/3, kv_req/2,
                   validate_list/1,
                   validate_binary/1,
                   validate_boolean/1,
                   validate_enum/2,
                   validate_integer/1,
                   validate_non_neg/1]}).



-spec validate_boolean_opt(Name, Opts, Default) -> Value
    when Name :: atom(), Opts :: proplists:proplist(),
         Default :: boolean(), Value :: boolean().
%% @private
validate_boolean_opt(Name, Opts, Default) ->
    validate_boolean(kv(Name, Opts, Default)).

-spec validate_boolean({Name, Value}) -> boolean()
    when Name :: atom(), Value :: atom().
%% @private
validate_boolean({_Name, true})  -> true;
validate_boolean({_Name, false}) -> false;
validate_boolean({Name, _Value}) ->
    throw({bad_options, {not_a_boolean, Name}}).

%% @private
-spec validate_enum({Name, Value}, ValidValues) -> Value when
      Name :: atom(), ValidValues :: [term()], Value :: term().
validate_enum({Name, Value}, [_|_] = ValidValues) when is_atom(Name) ->
    case lists:member(Value, ValidValues) of
        true ->
            Value;
        false ->
            throw({bad_options, {invalid_enum,
                                 {name, Name},
                                 {value, Value},
                                 {valid_values, ValidValues}}})
    end.


-spec validate_list({Name, Value}) -> Value
    when Name :: atom(), Value :: list().
%% @private
validate_list({_Name, List}) when is_list(List) ->
    List;
validate_list({Name, _Other}) ->
    throw({bad_options, {not_a_list, Name}}).


-spec validate_binary({Name, Value}) -> Value
    when Name :: atom(), Value :: binary().
%% @private
validate_binary({_Name, Bin}) when is_binary(Bin) -> Bin;
validate_binary({Name, _Other}) ->
    throw({bad_options, {not_a_binary, Name}}).

-spec validate_integer({Name, Value}) -> Value
    when Name :: atom(), Value :: term().
%% @private
validate_integer({_Name, Value}) when is_integer(Value) -> Value;
validate_integer({Name, _Other}) ->
    throw({bad_options, {not_an_integer, Name}}).

-spec validate_non_neg({Name, Value}) -> Value
    when Name :: atom(), Value :: non_neg_integer().
%% @private
validate_non_neg({_Name, Int}) when is_integer(Int), Int >= 0 -> Int;
validate_non_neg({Name, Int}) when is_integer(Int) ->
    throw({bad_options, {negative_integer, Name}});
validate_non_neg({Name, _Other}) ->
    throw({bad_options, {not_an_integer, Name}}).

%%--------------------------------------------------------------------

%% @private
validate_app_id_suffix(Opts) ->
    validate_binary(kv_req(app_id_suffix, Opts)).

%% @private
validate_team_id(Opts) ->
    validate_binary(kv_req(team_id, Opts)).

%% @private
validate_retry_delay(Opts) ->
    validate_non_neg(kv(retry_delay, Opts, ?DEFAULT_RETRY_DELAY)).

%% @private
validate_retry_strategy(Opts) ->
    validate_enum(kv(retry_strategy, Opts, ?DEFAULT_RETRY_STRATEGY),
                  [exponential, fixed]).

%% @private
validate_retry_max(Opts) ->
    validate_non_neg(kv(retry_max, Opts, ?DEFAULT_RETRY_MAX)).


%% @private
pv(Key, PL) ->
    pv(Key, PL, undefined).


%% @private
pv(Key, PL, Default) ->
    element(2, kv(Key, PL, Default)).

%% @private
pv_req(Key, PL) ->
    element(2, kv_req(Key, PL)).

%% @private
kv(Key, PL, Default) ->
    case lists:keysearch(Key, 1, PL) of
        {value, {_K, _V}=KV} ->
            KV;
        _ ->
            {Key, Default}
    end.

%% @private
kv_req(Key, PL) ->
    case lists:keysearch(Key, 1, PL) of
        {value, {_K, _V}=KV} ->
            KV;
        _ ->
            key_not_found_error(Key)
    end.

%% @private
key_not_found_error(Key) ->
    throw({key_not_found, Key}).

%%% --------------------------------------------------------------------------
%%% Notification Creation Functions
%%% --------------------------------------------------------------------------

%% @private
make_nf(Opts, From, Callback) when (From =:= undefined orelse
                                    is_pid(From)) andalso
                                   is_function(Callback, 3) ->
    #nf{uuid = get_id_opt(Opts),
        expiry = get_expiry_opt(Opts),
        token = get_token_opt(Opts),
        topic = pv(topic, Opts),
        json = get_json_opt(Opts),
        prio = get_prio_opt(Opts),
        from = From,
        cb = Callback}.

%% @private
update_nf(#nf{topic = Topic, from = NfFrom} = Nf, State, From) ->
    %% Don't override the notification's from PID if it's already
    %% defined - it might have been set explicitly by a caller.
    UseFrom = case is_pid(NfFrom) of
                  true -> NfFrom;
                  false -> From
              end,
    Nf#nf{topic = sel_topic(Topic, State), from = UseFrom}.

%% @private
notify_failure(#nf{from = undefined}, _Reason) -> ok;
notify_failure(#nf{from = {Pid, _} = Caller}, Reason) when is_pid(Pid) ->
    gen_fsm:reply(Caller, {error, Reason});
notify_failure(#nf{uuid = UUIDStr, from = Pid}, Reason) when is_pid(Pid) ->
    Pid ! make_apns_response(UUIDStr, {error, Reason}).

%%% --------------------------------------------------------------------------
%%% History and Queue Managment Functions
%%% --------------------------------------------------------------------------
%% @private
init_queue(#?S{queue = undefined} = State) ->
    State#?S{queue = queue:new()}.


%% @private
terminate_queue(#?S{queue = Queue} = State) when Queue =/= undefined ->
    State#?S{queue = undefined}.


%% @private
queue_length(State) ->
    queue:len(State#?S.queue).


%% @private
queue_nf(Nf, #?S{queue = Queue} = State) ->
    State#?S{queue = queue:in(Nf, Queue)}.


%% @private
recover_notification(Nf, #?S{queue = Queue} = State) ->
    State#?S{queue = queue:in_r(Nf, Queue)}.


%%% --------------------------------------------------------------------------
%%% Reconnection Delay Functions
%%% --------------------------------------------------------------------------

%% @private
schedule_reconnect(#?S{retry_ref = Ref} = State) ->
    _ = (catch erlang:cancel_timer(Ref)),
    {Delay, NewState} = next_delay(State),
    ?LOG_INFO("Reconnecting APNS HTTP/2 session ~p in ~w ms",
              [State#?S.name, Delay]),
    NewRef = gen_fsm:send_event_after(Delay, connect),
    NewState#?S{retry_ref = NewRef}.


%% @private
cancel_reconnect(#?S{retry_ref = Ref} = State) ->
    catch erlang:cancel_timer(Ref),
    State#?S{retry_ref = undefined}.


%% @private
next_delay(#?S{retries = 0} = State) ->
    {0, State#?S{retries = 1}};
next_delay(#?S{retry_strategy = exponential} = State) ->
    #?S{retries = Retries, retry_delay = RetryDelay,
        retry_max = RetryMax} = State,
    Delay = RetryDelay * trunc(math:pow(2, (Retries - 1))),
    {min(RetryMax, Delay), State#?S{retries = Retries + 1}};
next_delay(#?S{retry_strategy = fixed} = State) ->
    #?S{retries = Retries, retry_delay = RetryDelay,
        retry_max = RetryMax} = State,
    {min(RetryDelay, RetryMax), State#?S{retries = Retries + 1}}.


%% @private
reset_delay(State) ->
    % Reset to 1 so the first reconnection is always done after the retry delay.
    State#?S{retries = 1}.

%%% --------------------------------------------------------------------------
%%% APNS Handling Functions
%%% --------------------------------------------------------------------------

%% @private
apns_connect(Host, Port, SslOpts) ->
    h2_client:start_link(https, Host, Port, SslOpts).

%%--------------------------------------------------------------------
%% @private
apns_disconnect(undefined) ->
    ok;
apns_disconnect(Http2Client) when is_pid(Http2Client) ->
    ok = h2_client:stop(Http2Client).

%%--------------------------------------------------------------------
%% @private
-spec apns_send(Nf, State) -> Resp
    when Nf :: nf(), State :: state(),
         Resp :: {ok, StreamId} | {error, term()}, StreamId :: term().
apns_send(Nf, State) ->
    Opts = make_opts(Nf, State),
    Req = apns_lib_http2:make_req(Nf#nf.token, Nf#nf.json, Opts),
    case send_impl(State#?S.http2_pid, Req) of
        {ok, StreamId} = Result ->
            ReqInfo = #apns_erlv3_req{stream_id = StreamId, nf = Nf, req = Req},
            ok = req_add(State#?S.req_store, ReqInfo),
            Result;
        Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @private
-spec apns_get_response(Http2Client, StreamId) -> Result when
      Http2Client :: pid(), StreamId :: term(),
      Result :: {ok, Resp} | {error, Reason},
      Resp :: apns_lib_http2:http2_rsp(), Reason :: term().
apns_get_response(Http2Client, StreamId) ->
    h2_connection:get_response(Http2Client, StreamId).

%%--------------------------------------------------------------------
%% @private
-spec gen_send_callback(ReplyFun, NfPL, Req, Resp) -> Result when
      ReplyFun :: reply_fun(), NfPL :: [{atom(), term()}], Req :: cb_req(),
      Resp :: cb_result(), Result :: cb_result().
gen_send_callback(ReplyFun, NfPL, Req, Resp) when is_function(ReplyFun, 3) ->
    _ = log_response(Resp, Req),
    case pv_req(from, NfPL) of
        undefined ->
            ?LOG_ERROR("Cannot send result, no caller info: ~p", [NfPL]),
            {error, no_caller_info};
        Caller  ->
            UUID = pv_req(uuid, NfPL),
            ?LOG_DEBUG("Invoke callback for UUID ~s, caller ~p", [UUID, Caller]),
            ReplyFun(Caller, UUID, Resp),
            ok
    end.

%%--------------------------------------------------------------------
%% @private
log_response({ok, {UUID, [_|_] = ParsedResp}}, _Req) ->
    ?LOG_DEBUG("Received parsed response (uuid ~s): ~p",
               [uuid_to_str(UUID), ParsedResp]);
log_response({error, {UUID, [_|_] = ParsedResp}}, _Req) ->
    ?LOG_DEBUG("Received error response (uuid ~s): ~p",
               [uuid_to_str(UUID), ParsedResp]);
log_response(Resp, {ReqHdrs, ReqBody}) ->
    ?LOG_WARNING("Error sending request, error: ~p\n"
                 "headers: ~p\nbody: ~p\n", [Resp, ReqHdrs, ReqBody]).

%%--------------------------------------------------------------------
%% @private
sync_reply(Caller, _UUID, Resp) ->
    ?LOG_DEBUG("sync_reply to caller ~p", [Caller]),
    gen_fsm:reply(Caller, Resp).

%% @private
async_reply({Pid, _Tag} = Caller, UUID, Resp) ->
    ?LOG_DEBUG("async_reply for UUID ~p to caller ~p", [UUID, Caller]),
    Pid ! make_apns_response(UUID, Resp);
async_reply(Pid, UUID, Resp) when is_pid(Pid) ->
    ?LOG_DEBUG("async_reply for UUID ~p to caller ~p", [UUID, Pid]),
    Pid ! make_apns_response(UUID, Resp).

%%--------------------------------------------------------------------
%% @private
minimal_ssl_opts() ->
    [
     {honor_cipher_order, false},
     {versions, ['tlsv1.2']},
     {alpn_preferred_protocols, [<<"h2">>]}
    ].

%%--------------------------------------------------------------------
%% @private
-spec make_opts(Nf, State) -> Opts when
      Nf :: nf(), State :: state(), Opts :: send_opts().
make_opts(Nf, #?S{apns_auth=undefined}) ->
    nf_to_opts(Nf);
make_opts(Nf, #?S{apns_auth=Jwt}) ->
    [{authorization, Jwt} | nf_to_opts(Nf)].

%%--------------------------------------------------------------------
%% @private
make_apns_auth(undefined) ->
    undefined;
make_apns_auth(Context) ->
    apns_jwt:jwt(Context).

%%--------------------------------------------------------------------
%% The idea here is not to provide values that APNS will default,
%% so this could potentially return an empty list.
%% @private
nf_to_opts(#nf{} = Nf) ->
    KVs = [
     {uuid, Nf#nf.uuid},
     %% NB: APNS and apns_lib_http2 use the keyword `expiration', so
     %% this translation is necessary.
     {expiration, Nf#nf.expiry},
     {priority, Nf#nf.prio},
     {topic, Nf#nf.topic}
    ],
    [{K, V} || {K, V} <- KVs, V /= undefined].

%%--------------------------------------------------------------------
%% @private
nf_to_pl(#nf{} = Nf) ->
    [{uuid, Nf#nf.uuid},
     {expiration, Nf#nf.expiry},
     {token, Nf#nf.token},
     {topic, Nf#nf.topic},
     {json, Nf#nf.json},
     {from, Nf#nf.from},
     {priority, Nf#nf.prio}].

%%--------------------------------------------------------------------
%% @private
check_uuid(UUID, Resp) ->
    case pv_req(uuid, Resp) of
        UUID ->
            ok;
        ActualUUID ->
            ?LOG_ERROR("Unmatched UUIDs, expected: ~p actual: ~p\n",
                       [UUID, ActualUUID]),
            {error, {exp, UUID, act, ActualUUID}}
    end.

%%--------------------------------------------------------------------
%% @private
-spec send_impl(Http2Client, Req) -> Result
    when Http2Client :: pid(), Req :: apns_lib_http2:http2_req(),
         Result :: {ok, StreamId} | {error, term()}, StreamId :: term().
send_impl(Http2Client, {ReqHdrs, ReqBody}) ->
    _ = ?LOG_DEBUG("Submitting request, headers: ~p\nbody: ~p\n",
                    [ReqHdrs, ReqBody]),
    try
        Result = h2_client:send_request(Http2Client, ReqHdrs, ReqBody),
        {ok, StreamId} = Result,
        _ = ?LOG_DEBUG("Successfully submitted request on stream id ~p",
                        [StreamId]),
        Result
    catch
        What:Why ->
            ?LOG_ERROR("Exception sending request, headers: ~p\n"
                       "body: ~p\nStacktrace:~s",
                       [ReqHdrs, ReqBody, ?STACKTRACE(What, Why)]),
            Why
    end.

%%--------------------------------------------------------------------
%% @private
apns_deregister_token(Token) ->
    SvcTok = sc_push_reg_api:make_svc_tok(apns, Token),
    ok = sc_push_reg_api:deregister_svc_tok(SvcTok).

%%--------------------------------------------------------------------
%% @private
-spec tok_s(Token) -> BStr
    when Token :: nf() | undefined | binary() | string(), BStr :: bstrtok().
tok_s(#nf{token = Token}) ->
    Token;
tok_s(Token) when is_list(Token) ->
    sc_util:to_bin(Token);
tok_s(<<Token/binary>>) ->
    Token;
tok_s(_) ->
    <<"unknown_token">>.

-compile({inline, [make_apns_response/2]}).
make_apns_response(<<_:128>> = UUID, Resp) ->
    {apns_response, v3, {UUID, Resp}};
make_apns_response(UUID, Resp) ->
    make_apns_response(str_to_uuid(UUID), Resp).

%%--------------------------------------------------------------------
-spec get_default_topic(Opts) -> Result when
      Opts :: [{_,_}], Result :: {ok, binary()} | {error, term()}.
%% @private
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

%%--------------------------------------------------------------------
%% We want to default the id because it is also returned from
%% the async interface once it is validated and queued.
%% @private
get_id_opt(Opts) ->
    case pv(uuid, Opts) of
        undefined ->
            apns_lib_http2:make_uuid();
        Id ->
            validate_binary({uuid, Id})
    end.

%%--------------------------------------------------------------------
%% @private
get_token_opt(Opts) ->
    validate_binary(kv_req(token, Opts)).

%% If topic is provided in Opts, it overrides
%% topic in State, otherwise we used the State
%% optic, even if it's `undefined'.
%% @private
get_topic_opt(Opts, State) ->
    case pv(topic, Opts) of
        undefined ->
            State#?S.apns_topic;
        Topic ->
            Topic
    end.

%%--------------------------------------------------------------------
%% @private
get_json_opt(Opts) ->
    validate_binary(kv_req(json, Opts)).

%%--------------------------------------------------------------------
%% @private
get_prio_opt(Opts) ->
    pv(priority, Opts).

%%--------------------------------------------------------------------
%% We need the default here because this is checked via pattern-matching when
%% requeuing notifications.
%% @private
get_expiry_opt(Opts) ->
    pv(expiry, Opts, ?DEFAULT_EXPIRY_TIME).

%%--------------------------------------------------------------------
%% @private
sel_topic(undefined, State) ->
    State#?S.apns_topic;
sel_topic(Topic, _State) ->
    Topic.

%%--------------------------------------------------------------------
-spec handle_end_of_stream(StreamId, StateName, State) -> NewState when
      StreamId :: term(), StateName :: atom(), State :: state(),
      NewState :: state().
%% @private
handle_end_of_stream(StreamId, StateName, #?S{http2_pid = Pid} = State) ->
    case apns_get_response(Pid, StreamId) of
        {ok, Resp} ->
            RespResult = get_resp_result(Resp),
            Req = get_req(State#?S.req_store, StreamId),
            #apns_erlv3_req{nf=Nf} = Req,
            UUID = str_to_uuid(Nf#nf.uuid),
            _ = run_send_callback(Req, StateName,
                                  to_cb_result(UUID, RespResult)),
            handle_resp_result(RespResult, Req, State);
        {error, Err} ->
            ?LOG_ERROR("Error from stream id ~p: ~p", [StreamId, Err]),
            State
    end.

%%--------------------------------------------------------------------
to_cb_result(UUID, {ok, [_|_]=ParsedResp}) ->
    {ok, {UUID, ParsedResp}};
to_cb_result(UUID, {error, Reason}) ->
    {error, {UUID, Reason}}.

%%--------------------------------------------------------------------
-spec handle_resp_result(RespResult, Req, State) -> NewState when
      RespResult :: {ok, ParsedResp} | {error, term()},
      Req :: apns_erlv3_req() | undefined, State :: state(),
      ParsedResp :: apns_lib_http2:parsed_rsp(),
      NewState :: state().
%% @private
handle_resp_result({ok, [_|_] = ParsedResp}, #apns_erlv3_req{} = Req, State) ->
    handle_parsed_resp(ParsedResp, Req, State);
handle_resp_result({error, Reason}, #apns_erlv3_req{} = _Req, State) ->
    ?LOG_WARNING("Failed to send notification on APNS HTTP/2 session ~p;\n"
                 "Reason: ~p", [State#?S.name, Reason]),
    State.

%%--------------------------------------------------------------------
-spec handle_parsed_resp(ParsedResp, Req, State) -> NewState when
      ParsedResp :: apns_lib_http2:parsed_rsp(),
      Req :: apns_erlv3_req() | undefined, State :: state(),
      NewState :: state().
%% @private
handle_parsed_resp(ParsedResp, #apns_erlv3_req{} = Req,
                   #?S{jwt_ctx=JwtCtx}=State) ->
    UUID = pv_req(uuid, ParsedResp),
    Nf = req_nf(Req),
    case check_status(ParsedResp) of
        ok ->
            State;
        expired_jwt -> % Regen the jwt and try again
            ?LOG_WARNING("JWT auth token expired for APNS HTTP/2 session ~p;\n"
                         "failed to send notification ~s, token ~s",
                         [State#?S.name, UUID, tok_s(Nf)]),
            NewState = State#?S{apns_auth=make_apns_auth(JwtCtx)},
            ?LOG_DEBUG("NewState: ~s", [lager:pr(NewState, ?MODULE)]),
            ?LOG_WARNING("Recovering failed notification ~s, "
                         "token ~s, session ~p",
                         [UUID, tok_s(Nf), State#?S.name]),
            recover_notification(Nf, NewState);
        invalid_jwt ->
            Kid = apns_jwt:kid(JwtCtx),
            ?LOG_CRITICAL("ACTION REQUIRED: Invalid JWT signing key (kid: ~s)"
                          " on session ~p!\nFailed to send notification with "
                          "uuid ~s, token ~s: ~p",
                          [Kid, State#?S.name, UUID, tok_s(Nf), ParsedResp]),
            State;
        error ->
            ?LOG_WARNING("Failed to send notification on APNS HTTP/2 session"
                         " ~p, uuid: ~s, token: ~s:\nParsed resp: ~p",
                         [State#?S.name, UUID, tok_s(Nf), ParsedResp]),
            maybe_recover_notification(ParsedResp, Nf, State)
    end.

%%--------------------------------------------------------------------
%% @private
try_send(FsmRef, Mode, #nf{} = Nf) when Mode =:= sync orelse Mode =:= async ->
    try
        gen_fsm:sync_send_event(FsmRef, {send, Mode, Nf})
    catch
        exit:{timeout, _} -> {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @private
try_sync_send_all_state_event(FsmRef, Event) ->
    try
        gen_fsm:sync_send_all_state_event(FsmRef, Event)
    catch
        exit:{noproc, _}  -> {error, noproc};
        exit:{timeout, _} -> {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @private
run_send_callback(#apns_erlv3_req{} = R, StateName, RespResult) ->
    #apns_erlv3_req{nf = Nf, req = Req} = R,
    Callback = Nf#nf.cb,
    NfPL = nf_to_pl(Nf),
    try
        ?LOG_DEBUG("run_send_callback, state: ~p~nnfpl: ~p~nreq: ~p~n"
                   "respresult: ~p", [StateName, NfPL, Req, RespResult]),
        _ = Callback(NfPL, Req, RespResult),
        ok
    catch
        Class:Reason ->
            ?LOG_ERROR("Callback exception in state ~p, req: ~p\n"
                       "result: ~p\nStacktrace:~s",
                       [StateName, Req, RespResult,
                        ?STACKTRACE(Class, Reason)]),
            {error, Reason}
    end;
run_send_callback(undefined, StateName, RespResult) ->
    ?LOG_ERROR("Cannot run callback for result ~p in state ~p",
               [RespResult, StateName]),
    {error, no_req_found}.

%%--------------------------------------------------------------------
%% @private
-spec get_req(ReqStore, StreamId) -> Result when
      ReqStore :: term(), StreamId :: term(),
      Result :: apns_erlv3_req() | undefined.
get_req(ReqStore, StreamId) ->
    case req_remove(ReqStore, StreamId) of
        #apns_erlv3_req{} = Req ->
            Req;
        undefined ->
            ?LOG_WARNING("Cannot find request for stream ~p", [StreamId]),
            undefined
    end.

%%--------------------------------------------------------------------
%% @private
req_nf(#apns_erlv3_req{nf = Nf}) ->
    Nf;
req_nf(_) ->
    undefined.

%%--------------------------------------------------------------------
%% @private
req_http_req(#apns_erlv3_req{req = HttpReq}) ->
    HttpReq;
req_http_req(_) ->
    undefined.

%%--------------------------------------------------------------------
%% @private
-spec get_resp_result(Resp) -> Result when
      Resp :: apns_lib_http2:http2_rsp(),
      Result :: {ok, ParsedResp} | {error, term()},
      ParsedResp :: apns_lib_http2:parsed_rsp().
get_resp_result(Resp) ->
    try
        {ok, apns_lib_http2:parse_resp(Resp)}
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
-spec check_status(ParsedResp) -> Result when
      ParsedResp :: apns_lib_http2:parsed_rsp(), Result :: ok | error.
check_status(ParsedResp) ->
    case pv_req(status, ParsedResp) of
        <<"200">> ->
            ok;
        <<"403">> ->
            check_403(ParsedResp);
        _ErrorStatus ->
            error
    end.

%%--------------------------------------------------------------------
-spec check_403(ParsedResp) -> Result when
      ParsedResp :: apns_lib_http2:parsed_rsp(),
      Result :: expired_jwt | invalid_jwt | error.
check_403(ParsedResp) ->
    case pv_req(reason, ParsedResp) of
        <<"ExpiredProviderToken">> ->
            expired_jwt;
        <<"InvalidProviderToken">> ->
            invalid_jwt;
        _ ->
            error
    end.

%%--------------------------------------------------------------------
-spec str_to_uuid(uuid_str()) -> uuid().
str_to_uuid(UUID) ->
    uuid:string_to_uuid(UUID).

%%--------------------------------------------------------------------
-spec uuid_to_str(uuid()) -> uuid_str().
uuid_to_str(<<_:128>> = UUID) ->
    uuid:uuid_to_string(UUID, binary_standard).

%%--------------------------------------------------------------------
%% @private
req_store_new(Name) ->
    ets:new(Name, [set, protected, {keypos, #apns_erlv3_req.stream_id}]).

%% @private
req_store_delete(Tab) ->
    true = ets:delete(Tab),
    ok.

%% @private
req_add(Tab, Req) ->
    true = ets:insert(Tab, Req),
    ok.

%% @private
req_lookup(Tab, Id) ->
    case ets:lookup(Tab, Id) of
        [] ->
            undefined;
        [Req] ->
            Req
    end.

%% @private
req_remove(Tab, Id) ->
    case req_lookup(Tab, Id) of
        undefined ->
            undefined;
        Req ->
            true = ets:delete(Tab, Id),
            Req
    end.
