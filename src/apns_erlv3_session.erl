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
%%%   key id corresponding to the signing key.  `KeyFile' is the name of the
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
%%% <dt>`jwt_max_age_secs'</dt>
%%%   <dd>The number of seconds, measured from the "issued at" (iat)
%%%   JWT POSIX time, after which the JWT should be preemptively reissued.
%%%   The reissuance occurs just prior to the next notification transmission.
%%%   <br/>
%%%   Default value: 3300 seconds (55 minutes).
%%%   </dd>
%%%
%%% <dt>`keepalive_interval'</dt>
%%%   <dd>The number of seconds after which a PING should be sent to the
%%%   peer host.
%%%   <br/>
%%%   Default value: 300 seconds (5 minutes).
%%%   </dd>
%%%
%%% <dt>`queue_limit'</dt>
%%%   <dd>The maximum number of notifications that can be queued before
%%%   getting a `try_again_later' backpressure error. Must be at least 1.
%%%   <br/>
%%%   Default value: 5000.
%%%   </dd>
%%%
%%% <dt>`burst_size'</dt>
%%%   <dd>The maximum number of notification requests that will be made to the
%%%   HTTP/2 client in an uninterrupted burst. This must be greater than zero.
%%%
%%%   Setting this to a very small number is likely to impact performance
%%%   negatively. The same is true for a very large number, because the
%%%   FSM is blocked while the HTTP/2 requests are being made. Note that the
%%%   HTTP/2 requests are being made asynchronously, so the FSM is not
%%%   blocked on actually sending the request over the wire, just on the HTTP/2
%%%   client accepting the request.
%%%   <br/>
%%%   Default value: 500.
%%%   </dd>
%%%
%%% <dt>`kick_sender_interval'</dt>
%%%   <dd>The number of milliseconds to wait before polling the input queue and
%%%   potentially sending a burst of requests. If this is made too small, it
%%%   could consume more CPU than desired. If too large, the notifications may
%%%   be delayed too long, which could cause timeout issues. Must be more than
%%%   zero.
%%%   <br/>
%%%   Default value: 100.
%%%   </dd>
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
%%%  {jwt_max_age_secs, 3300},
%%%  {keepalive_interval, 300},
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
-include_lib("chatterbox/include/http2.hrl").
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
         async_send_callback/3,
         kick_sender/1,
         ping/1,
         disconnect/1
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
         draining/2, draining/3,
         disconnecting/2, disconnecting/3]).

%%% "Internal" exports
-export([validate_binary/1]).
-export([validate_boolean/1]).
-export([validate_integer/1]).
-export([validate_list/1]).
-export([validate_non_neg/1]).
-export([validate_pos/1]).
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
-define(DEFAULT_JWT_MAX_AGE_SECS, 60*55).
-define(DEFAULT_KEEPALIVE_INTVL, 60*5).

-define(DEFAULT_FLUSH_STRATEGY, on_reconnect). % ***DEBUG ONLY***, undocumented
-define(DEFAULT_REQUEUE_STRATEGY, always). % ***DEBUG ONLY***, undocumented

-define(DEFAULT_QUEUE_LIMIT, 5000). % Maximum number of messages that can be queued
-define(DEFAULT_BURST_MAX, 500). % Maximum number of notifications to burst to HTTP/2.
-define(DEFAULT_KICK_SENDER_INTVL, 100). % ms

-define(QUEUE_FULL(State), (State#?S.queue_len >= State#?S.queue_limit)).
-define(QUIESCED(State), (State#?S.quiesced == true)).

-define(REQ_STORE, ?MODULE).

-define(HTTP2_PING_FRAME, 16#6).

%%% ==========================================================================
%%% Types
%%% ==========================================================================

-type state_name() :: connecting | connected | draining | disconnecting.

-type cb_req() :: apns_lib_http2:http2_req().
-type cb_result() :: {ok, {uuid(), apns_lib_http2:parsed_rsp()}}
                   | {error, term()}.
-type send_callback() :: fun((list(), cb_req(), cb_result()) -> term()).
-type caller() :: pid() | {pid(), term()}.
-type uuid() :: binary(). % 128-bit raw UUID
-type uuid_str() :: apns_lib_http2:uuid_str().
-type reply_fun() :: fun((caller(), uuid(), cb_result()) -> none()).

-type flush_strategy_opt() :: on_reconnect | debug_clear.
-type requeue_strategy_opt() :: always | debug_never.

-type option() :: {host, binary()} |
                  {port, non_neg_integer()} |
                  {app_id_suffix, binary()} |
                  {team_id, binary()} |
                  {apns_env, prod | dev} |
                  {apns_topic, binary()} |
                  {disable_apns_cert_validation, boolean()} |
                  {jwt_max_age_secs, non_neg_integer()} |
                  {keepalive_interval, non_neg_integer()} |
                  {ssl_opts, list()} |
                  {retry_delay, non_neg_integer()} |
                  {retry_max, pos_integer()} |
                  {retry_strategy, fixed | exponential} |
                  {flush_strategy, flush_strategy_opt()} |
                  {requeue_strategy, requeue_strategy_opt()} |
                  {queue_limit, pos_integer()} |
                  {burst_size, pos_integer()} |
                  {kick_sender_interval, pos_integer()}
                  .

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


-type queued_result() :: {queued, uuid()}. % This result is returned when
                                           % the notification is queued.
                                           % The APNS response will be sent
                                           % to the caller's process as a
                                           % message in the following format:
                                           % `{apns_response, v3,
                                           % {uuid(), Resp :: cb_result()}}'

-type sync_result() :: {uuid(), apns_lib_http2:parsed_rsp()}. % Returned from a
                                                              % synchronous send.

-type async_send_result() :: queued_result().
-type sync_send_result() :: sync_result().
-type sync_send_reply() :: {ok, sync_send_result()} | {error, term()}.
-type async_send_reply() :: {ok, async_send_result()} | {error, term()}.

%%% ==========================================================================
%%% Records
%%% ==========================================================================

-type jwt_ctx() :: apns_jwt:context().

%%% Process state
-record(?S,
        {name                 = undefined                  :: atom(),
         http2_pid            = undefined                  :: pid() | undefined,
         protocol             = h2                         :: h2 | h2c,
         host                 = ""                         :: string(),
         port                 = ?DEFAULT_APNS_PORT         :: non_neg_integer(),
         app_id_suffix        = <<>>                       :: binary(),
         apns_auth            = undefined                  :: undefined | binary(), % current JWT
         apns_env             = undefined                  :: prod | dev,
         apns_topic           = <<>>                       :: undefined | binary(),
         jwt_ctx              = undefined                  :: undefined | jwt_ctx(),
         jwt_iat              = undefined                  :: non_neg_integer() | undefined,
         jwt_max_age_secs     = ?DEFAULT_JWT_MAX_AGE_SECS  :: non_neg_integer(),
         ssl_opts             = []                         :: list(),
         retry_strategy       = ?DEFAULT_RETRY_STRATEGY    :: exponential | fixed,
         retry_delay          = ?DEFAULT_RETRY_DELAY       :: non_neg_integer(),
         retry_max            = ?DEFAULT_RETRY_MAX         :: non_neg_integer(),
         keepalive_ref        = undefined                  :: reference() | undefined,
         keepalive_interval   = ?DEFAULT_KEEPALIVE_INTVL   :: non_neg_integer(),
         retry_ref            = undefined                  :: reference() | undefined,
         retries              = 1                          :: non_neg_integer(),
         queue                = undefined                  :: sc_queue() | undefined,
         queue_limit          = ?DEFAULT_QUEUE_LIMIT       :: pos_integer(),
         queue_len            = 0                          :: non_neg_integer(), % because queue:len/1 is O(N)
         stop_callers         = []                         :: list(),
         quiesced             = false                      :: boolean(),
         req_store            = undefined                  :: term(),
         flush_strategy       = ?DEFAULT_FLUSH_STRATEGY    :: flush_strategy_opt(),
         requeue_strategy     = ?DEFAULT_REQUEUE_STRATEGY  :: requeue_strategy_opt(),
         burst_max            = ?DEFAULT_BURST_MAX         :: pos_integer(),
         kick_sender_ref      = undefined                  :: reference() | undefined,
         kick_sender_interval = ?DEFAULT_KICK_SENDER_INTVL :: non_neg_integer()
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
         req            = {[], <<>>}             :: apns_lib_http2:http2_req(),
         last_mod_time  = sc_util:posix_time()   :: non_neg_integer() % POSIX time
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
%% callback function. If `id' is not provided in `Opts', generate a UUID
%% and use that instead.
%%
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
%%
%% If the session is not quiesced, and the notification passes preliminary
%% validation, attempts to send will receive a response `{ok, {queued, UUID ::
%% binary()}}'.
%%
%% The `queued' status means that the notification is being held until the
%% session is able to send it to APNS.
%%
%% If the queue has reached its configured limit, attempts to send will
%% receive `{error, try_again_later}' and the notification will not be
%% queued. The caller needs to resubmit the notification after backing off
%% for some time.
%%
%% == Timeouts ==
%%
%% There are multiple kinds of timeouts.
%%
%% If the session itself is so busy that the send request cannot be processed
%% in time, a timeout error will occur. The default Erlang call timeout is
%% applicable here.
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

%%--------------------------------------------------------------------
%% @doc Kick off an HTTP/2 PING.
%% @end
%%--------------------------------------------------------------------
-spec ping(FsmRef) -> ok when FsmRef :: term().
ping(FsmRef) ->
    gen_fsm:send_event(FsmRef, ping).

%%--------------------------------------------------------------------
%% @doc Wake up the sender to start sending queued notifications.
%% @end
%%--------------------------------------------------------------------
-spec kick_sender(FsmRef) -> ok when FsmRef :: term().
kick_sender(FsmRef) ->
    gen_fsm:send_event(FsmRef, kick_sender).

%%--------------------------------------------------------------------
%% @doc Make session disconnect
%% @end
%%--------------------------------------------------------------------
-spec disconnect(FsmRef) -> ok when FsmRef :: term().
disconnect(FsmRef) ->
    gen_fsm:send_event(FsmRef, disconnect).


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

%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
%% @private
handle_event(Event, StateName, State) ->
    ?LOG_WARNING("Received unexpected event while ~p: ~p", [StateName, Event]),
    continue(StateName, State).


%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
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
    handle_end_of_stream(StreamId, StateName, State);
handle_info(Info, StateName, State) ->
    ?LOG_WARNING("Unexpected message received in state ~p: ~p",
                 [StateName, Info]),
    continue(StateName, State).


%%--------------------------------------------------------------------
%% @private
terminate(Reason, StateName, State) ->
    WaitingCallers = State#?S.stop_callers,
    QueueLen = queue_len(State),
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


%%--------------------------------------------------------------------
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
    ok = apns_disconnect(State#?S.http2_pid),
    #?S{name = Name,
        protocol = Proto,
        host = Host,
        port = Port,
        ssl_opts = Opts} = State,
    Scheme = scheme_for_protocol(Proto),
    ?LOG_INFO("Connecting APNS HTTP/2 session ~p to ~p://~s:~w",
              [Name, Scheme, Host, Port]),
    case apns_connect(Proto, Host, Port, Opts) of
        {ok, Pid} ->
            ?LOG_INFO("Connected APNS HTTP/2 session ~p to ~p://~s:~w "
                      "on HTTP/2 client pid ~p",
                      [Name, Scheme, Host, Port, Pid]),
            next(connecting, connected, State#?S{http2_pid = Pid});
        {error, {{badmatch, Reason}, _}} ->
            ?LOG_CRITICAL("Connection failed for APNS HTTP/2 session ~p, "
                          "~p://~s:~w, probable configuration error: ~p",
                          [Name, Scheme, Host, Port, Reason]),
            stop(connecting, Reason, State);
        {error, Reason} ->
            ?LOG_ERROR("Connection failed for APNS HTTP/2 session ~p, "
                       "~p://~s:~w\nReason: ~p",
                       [Name, Scheme, Host, Port, Reason]),
            next(connecting, connecting, State)
    end;
connecting(kick_sender, State0) ->
    continue(connecting, cancel_kick_sender(State0));

connecting(Event, State) ->
    handle_event(Event, connecting, State).

%%--------------------------------------------------------------------
%% @private
connecting({send, _Mode, _=#nf{}}, _From, State) when ?QUIESCED(State) ->
    reply({error, quiesced}, connecting, State);
connecting({send, _Mode, _=#nf{}}, _From, State) when ?QUEUE_FULL(State) ->
    reply({error, try_again_later}, connecting, State);
connecting({send, sync, #nf{} = Nf}, From, State) ->
    continue(connecting, queue_nf(update_nf(Nf, State, From), State));
connecting({send, async, #nf{} = Nf}, From, State) ->
    reply({ok, {queued, str_to_uuid(Nf#nf.uuid)}}, connecting,
          queue_nf(update_nf(Nf, State, From), State));
connecting(Event, From, State) ->
    handle_sync_event(Event, From, connecting, State).


%% -----------------------------------------------------------------
%% Connected State
%% -----------------------------------------------------------------

%% @private
connected(ping, State) ->
    send_ping(State#?S.http2_pid),
    continue(connected, schedule_ping(State));
connected(kick_sender, State0) ->
    {_, State} = send_burst(State0),
    continue(connected, State);
connected(Event, State) ->
    handle_event(Event, connected, State).


%%--------------------------------------------------------------------
%% @private
connected({send, _Mode, _ = #nf{}}, _From, State) when ?QUIESCED(State) ->
    reply({error, quiesced}, connected, State);
connected({send, _Mode, #nf{}}, _From, State) when ?QUEUE_FULL(State) ->
    reply({error, try_again_later}, connected, State);
connected({send, sync, #nf{} = Nf}, From, State) ->
    continue(connected, queue_nf(update_nf(Nf, State, From), State));
connected({send, async, #nf{} = Nf}, From, State) ->
    reply({ok, {queued, str_to_uuid(Nf#nf.uuid)}}, connected,
          queue_nf(update_nf(Nf, State, From), State));
connected(Event, From, State) ->
    handle_sync_event(Event, From, connected, State).


%% -----------------------------------------------------------------
%% Draining State
%% -----------------------------------------------------------------

%% @private
draining(drained, State) ->
    next(draining, connecting, State);
draining(ping, State) ->
    continue(draining, cancel_ping(State));
draining(kick_sender, State0) ->
    {_, State} = send_burst(State0),
    continue(draining, State);
draining(Event, State) ->
    handle_event(Event, draining, State).


%%--------------------------------------------------------------------
%% @private
draining({send, _Mode, _=#nf{}}, _From, State) when ?QUIESCED(State) ->
    reply({error, quiesced}, draining, State);
draining({send, _Mode, _=#nf{}}, _From, State) when ?QUEUE_FULL(State) ->
    reply({error, try_again_later}, draining, State);
draining({send, sync, #nf{} = Nf}, From, State) ->
    continue(draining, queue_nf(update_nf(Nf, State, From), State));
draining({send, async, #nf{} = Nf}, From, State) ->
    reply({ok, {queued, str_to_uuid(Nf#nf.uuid)}}, draining,
          queue_nf(update_nf(Nf, State, From), State));
draining(Event, From, State) ->
    handle_sync_event(Event, From, draining, State).

%% -----------------------------------------------------------------
%% Disconnecting State
%% -----------------------------------------------------------------

%% @private
disconnecting(disconnect, State) ->
    apns_disconnect(State#?S.http2_pid),
    continue(disconnecting, State);
disconnecting(Event, State) ->
    handle_event(Event, disconnecting, State).


%%--------------------------------------------------------------------
%% @private
disconnecting({send, _Mode, _=#nf{}}, _From, State) when ?QUIESCED(State) ->
    reply({error, quiesced}, disconnecting, State);
disconnecting({send, _Mode, _=#nf{}}, _From, State) when ?QUEUE_FULL(State) ->
    reply({error, try_again_later}, disconnecting, State);
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

send_burst(#?S{burst_max=BurstMax}=State0) ->
    {Res, State} = send_burst(BurstMax, State0),
    {Res, schedule_kick_sender(State)}.

send_burst(0, State) ->
    {ok, State};
send_burst(BurstMax, #?S{queue=Queue0}=State0) when is_integer(BurstMax),
                                                    BurstMax > 0 ->
    Time = sc_util:posix_time(),
    case queue:out(Queue0) of
        {empty, Queue} ->
            {ok, set_queue(Queue, State0)};
        {{value, #nf{}=Nf}, Queue} when Nf#nf.expiry > Time ->
            case send_notification(Nf, async, set_queue(Queue, State0)) of
                {ok, _Resp, State} ->
                    send_burst(BurstMax - 1, State);
                {error, ErrorInfo, State} ->
                    {{error, ErrorInfo}, State}
            end;
        {{value, #nf{} = Nf}, Queue} ->
            ?LOG_NOTICE("Notification ~s with token ~s expired",
                        [Nf#nf.uuid, tok_b(Nf)]),
            notify_failure(Nf, expired),
            send_burst(BurstMax - 1, State0#?S{queue=Queue})
    end.

%%--------------------------------------------------------------------
%% @private
-spec send_notification(Nf, Mode, State) -> Result when
      Nf :: nf(), Mode :: async | sync, State :: state(),
      Result :: {ok, {submitted, UUID}, NewState} |
                {error, {UUID, {badmatch, Reason}}, NewState} |
                {error, {UUID, Reason}, NewState},
      UUID :: uuid(), NewState :: state(), Reason :: term().
send_notification(#nf{uuid = UUIDStr} = Nf, Mode, State0) ->
    ?LOG_DEBUG("Sending ~p notification: ~p", [Mode, Nf]),
    UUID = str_to_uuid(UUIDStr),
    case apns_send(Nf, State0) of
        {{ok, StreamId}, State} ->
            ?LOG_DEBUG("Submitted ~p notification ~s on stream ~p",
                       [Mode, UUIDStr, StreamId]),
            {ok, {submitted, UUID}, State};
        {{error, ?REFUSED_STREAM}, State} ->
            ?LOG_WARNING("Exceeded max # of HTTP/2 streams "
                         "sending ~s on session ~p with token ~s",
                         [UUIDStr, State#?S.name, tok_b(Nf)]),
            {error, {UUID, try_again_later}, requeue_nf(Nf, State)};
        {{error, {{badmatch, _} = Reason, _}}, State} ->
            ?LOG_ERROR("Crashed on notification ~w, APNS HTTP/2 session ~p"
                       " with token ~s: ~p",
                       [UUIDStr, State#?S.name, tok_b(Nf), Reason]),
            {error, {UUID, Reason}, requeue_nf(Nf, State)};
        {{error, Reason}, State} ->
            ?LOG_WARNING("Failed to send notification ~s on APNS HTTP/2 "
                         "session ~p with token ~s:\n~p",
                         [UUIDStr, State#?S.name, tok_b(Nf), Reason]),
            {error, {UUID, Reason}, requeue_nf(Nf, State)}
    end.


%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
%% @private
format_props(Props) ->
    iolist_to_binary(string:join([io_lib:format("~w=~p", [K, V])
                                  || {K, V} <- Props], ", ")).

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
%% Possibly change the current state without triggering any transition.
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

leave(connected, State) ->
    % Cancel any scheduled pings.
    cancel_ping(State);

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
transition(connected,     draining,      State) -> State;
transition(draining,      draining,      State) -> State;
transition(draining,      connecting,    State) -> State#?S{retries=0}; % Want immediate reconnect
transition(disconnecting, connecting,    State) -> State.


%% -----------------------------------------------------------------
%% Performs actions when entering a state.
%% -----------------------------------------------------------------

-spec enter(StateName, State) -> State
    when StateName :: state_name(), State ::state().

%% @private
enter(connecting, State) ->
    % Requeue all pending notifications that have been transmitted but have not
    % yet received a response.
    % Then trigger the connection after an exponential delay.
    schedule_reconnect(requeue_pending_nfs(State));

enter(connected, State) ->
    % Send a ping immediately to force any connection errors
    % and start the keepalive schedule
    ping(self()),
    % Kick the sender and reset the exponential delay
    schedule_kick_sender(reset_delay(State));

enter(draining, State) ->
    State;

enter(disconnecting, State) ->
    % Trigger the disconnection when disconnecting.
    disconnect(self()),
    State.


%%--------------------------------------------------------------------
%% @private
init_state(Name, Opts) ->
    {Host, Port, ApnsEnv} = validate_host_port_env(Opts),
    AppIdSuffix = validate_app_id_suffix(Opts),
    Protocol = validate_protocol(Opts),
    {ok, ApnsTopic} = get_default_topic(Protocol, Opts),
    TeamId = validate_team_id(Opts),
    {SslOpts, JwtCtx} = get_auth_info(Protocol, AppIdSuffix, TeamId, Opts),

    RetryStrategy = validate_retry_strategy(Opts),
    RetryDelay = validate_retry_delay(Opts),
    RetryMax = validate_retry_max(Opts),
    JwtMaxAgeSecs = validate_jwt_max_age_secs(Opts),
    KeepaliveInterval = validate_keepalive_interval(Opts),
    FlushStrategy = validate_flush_strategy(Opts),
    RequeueStrategy = validate_requeue_strategy(Opts),
    BurstMax = validate_burst_max(Opts),
    QueueLimit = validate_queue_limit(Opts),
    KickSenderInterval = validate_kick_sender_interval(Opts),

    ?LOG_DEBUG("With options: host=~p, port=~w, "
               "retry_strategy=~w, retry_delay=~w, retry_max=~p, "
               "jwt_max_age_secs=~w, keepalive_interval=~w, "
               "app_id_suffix=~p, apns_topic=~p, burst_max=~w, "
               "queue_limit=~w, kick_sender_interval=~w",
               [Host, Port,
                RetryStrategy, RetryDelay, RetryMax,
                JwtMaxAgeSecs, KeepaliveInterval,
                TeamId, ApnsTopic, BurstMax, QueueLimit,
                KickSenderInterval]),
    ?LOG_DEBUG("With SSL options: ~s", [format_props(SslOpts)]),

    State = #?S{name = Name,
                protocol = Protocol,
                host = binary_to_list(Host), % h2_client requires a list
                port = Port,
                apns_env = ApnsEnv,
                apns_topic = ApnsTopic,
                app_id_suffix = AppIdSuffix,
                jwt_ctx = JwtCtx,
                jwt_max_age_secs = JwtMaxAgeSecs,
                keepalive_interval = KeepaliveInterval,
                ssl_opts = SslOpts,
                retry_strategy = RetryStrategy,
                retry_delay = RetryDelay,
                retry_max = RetryMax,
                req_store = req_store_new(?REQ_STORE),
                flush_strategy = FlushStrategy,
                requeue_strategy = RequeueStrategy,
                burst_max = BurstMax,
                queue_limit = QueueLimit,
                kick_sender_interval = KickSenderInterval
               },

    new_apns_auth(State).


%%--------------------------------------------------------------------
-spec get_auth_info(Protocol, AppIdSuffix, TeamId, Opts) -> Result when
      Protocol :: h2 | h2c,
      AppIdSuffix :: binary(), TeamId :: binary(), Opts :: send_opts(),
      Result :: {SslOpts, JwtCtx},
      SslOpts :: list(), JwtCtx :: undefined | jwt_ctx().
get_auth_info(Protocol, AppIdSuffix, TeamId, Opts) ->
    case pv(apns_jwt_info, Opts) of
        {<<Kid/binary>>, <<KeyFile/binary>>} ->
            SigningKey = validate_jwt_keyfile(KeyFile),
            JwtCtx = apns_jwt:new(Kid, TeamId, SigningKey),
            SslOpts = minimal_ssl_opts(Protocol),
            {SslOpts, JwtCtx};
        undefined when Protocol == h2 ->
            {SslOpts, CertData} = validate_ssl_opts(pv_req(ssl_opts, Opts)),
            maybe_validate_apns_cert(Opts, CertData, AppIdSuffix, TeamId),
            {SslOpts, undefined};
        undefined when Protocol == h2c ->
            {minimal_ssl_opts(Protocol), undefined}
    end.

%%% --------------------------------------------------------------------------
%%% Option Validation Functions
%%% --------------------------------------------------------------------------

%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
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

%%--------------------------------------------------------------------
validate_jwt_keyfile(KeyFile) ->
    ?assertReadFile(sc_util:to_list(KeyFile)).

%%--------------------------------------------------------------------
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



%%--------------------------------------------------------------------
-spec validate_boolean_opt(Name, Opts, Default) -> Value
    when Name :: atom(), Opts :: proplists:proplist(),
         Default :: boolean(), Value :: boolean().
%% @private
validate_boolean_opt(Name, Opts, Default) ->
    validate_boolean(kv(Name, Opts, Default)).

%%--------------------------------------------------------------------
-spec validate_boolean({Name, Value}) -> boolean()
    when Name :: atom(), Value :: atom().
%% @private
validate_boolean({_Name, true})  -> true;
validate_boolean({_Name, false}) -> false;
validate_boolean({Name, _Value}) ->
    throw({bad_options, {not_a_boolean, Name}}).

%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
-spec validate_list({Name, Value}) -> Value
    when Name :: atom(), Value :: list().
%% @private
validate_list({_Name, List}) when is_list(List) ->
    List;
validate_list({Name, _Other}) ->
    throw({bad_options, {not_a_list, Name}}).


%%--------------------------------------------------------------------
-spec validate_binary({Name, Value}) -> Value
    when Name :: atom(), Value :: binary().
%% @private
validate_binary({_Name, Bin}) when is_binary(Bin) -> Bin;
validate_binary({Name, _Other}) ->
    throw({bad_options, {not_a_binary, Name}}).

%%--------------------------------------------------------------------
-spec validate_integer({Name, Value}) -> Value
    when Name :: atom(), Value :: term().
%% @private
validate_integer({_Name, Value}) when is_integer(Value) -> Value;
validate_integer({Name, _Other}) ->
    throw({bad_options, {not_an_integer, Name}}).

%%--------------------------------------------------------------------
-spec validate_non_neg({Name, Value}) -> Value
    when Name :: atom(), Value :: non_neg_integer().
%% @private
validate_non_neg({_Name, Int}) when is_integer(Int), Int >= 0 -> Int;
validate_non_neg({Name, Int}) when is_integer(Int) ->
    throw({bad_options, {negative_integer, Name}});
validate_non_neg({Name, _Other}) ->
    throw({bad_options, {not_an_integer, Name}}).

%%--------------------------------------------------------------------
-spec validate_pos({Name, Value}) -> Value
    when Name :: atom(), Value :: pos_integer().
%% @private
validate_pos({_Name, Int}) when is_integer(Int),
                                Int > 0 ->
    Int;
validate_pos({Name, Int}) when is_integer(Int) ->
    throw({bad_options, {not_pos_integer, Name}});
validate_pos({Name, _Other}) ->
    throw({bad_options, {not_an_integer, Name}}).

%%--------------------------------------------------------------------

%% @private
validate_app_id_suffix(Opts) ->
    validate_binary(kv_req(app_id_suffix, Opts)).

%%--------------------------------------------------------------------
%% @private
validate_team_id(Opts) ->
    validate_binary(kv_req(team_id, Opts)).

%%--------------------------------------------------------------------
%% @private
validate_retry_delay(Opts) ->
    validate_non_neg(kv(retry_delay, Opts, ?DEFAULT_RETRY_DELAY)).

%%--------------------------------------------------------------------
%% @private
validate_retry_strategy(Opts) ->
    validate_enum(kv(retry_strategy, Opts, ?DEFAULT_RETRY_STRATEGY),
                  [exponential, fixed]).

%%--------------------------------------------------------------------
%% @private
validate_retry_max(Opts) ->
    validate_non_neg(kv(retry_max, Opts, ?DEFAULT_RETRY_MAX)).

%%--------------------------------------------------------------------
%% @private
validate_jwt_max_age_secs(Opts) ->
    validate_non_neg(kv(jwt_max_age_secs, Opts, ?DEFAULT_JWT_MAX_AGE_SECS)).

%%--------------------------------------------------------------------
%% @private
validate_keepalive_interval(Opts) ->
    validate_non_neg(kv(keepalive_interval, Opts, ?DEFAULT_KEEPALIVE_INTVL)).

%%--------------------------------------------------------------------
%% @private
validate_flush_strategy(Opts) ->
    validate_enum(kv(flush_strategy, Opts, ?DEFAULT_FLUSH_STRATEGY),
                  [on_reconnect, debug_clear]).

%%--------------------------------------------------------------------
%% @private
validate_requeue_strategy(Opts) ->
    validate_enum(kv(requeue_strategy, Opts, ?DEFAULT_REQUEUE_STRATEGY),
                  [always, debug_never]).

%%--------------------------------------------------------------------
%% @private
validate_burst_max(Opts) ->
    validate_pos(kv(burst_max, Opts, ?DEFAULT_BURST_MAX)).

%%--------------------------------------------------------------------
%% @private
validate_queue_limit(Opts) ->
    validate_pos(kv(queue_limit, Opts, ?DEFAULT_QUEUE_LIMIT)).

%%--------------------------------------------------------------------
%% @private
validate_kick_sender_interval(Opts) ->
    validate_pos(kv(kick_sender_interval, Opts, ?DEFAULT_KICK_SENDER_INTVL)).

%%--------------------------------------------------------------------
%% @private
validate_protocol(Opts) ->
    validate_enum(kv(protocol, Opts, h2), [h2, h2c]).

%%--------------------------------------------------------------------
%% @private
pv(Key, PL) ->
    pv(Key, PL, undefined).


%%--------------------------------------------------------------------
%% @private
pv(Key, PL, Default) ->
    element(2, kv(Key, PL, Default)).

%%--------------------------------------------------------------------
%% @private
pv_req(Key, PL) ->
    element(2, kv_req(Key, PL)).

%%--------------------------------------------------------------------
%% @private
kv(Key, PL, Default) ->
    case lists:keysearch(Key, 1, PL) of
        {value, {_K, _V}=KV} ->
            KV;
        _ ->
            {Key, Default}
    end.

%%--------------------------------------------------------------------
%% @private
kv_req(Key, PL) ->
    case lists:keysearch(Key, 1, PL) of
        {value, {_K, _V}=KV} ->
            KV;
        _ ->
            key_not_found_error(Key)
    end.

%%--------------------------------------------------------------------
%% @private
key_not_found_error(Key) ->
    throw({key_not_found, Key}).

%%% --------------------------------------------------------------------------
%%% Notification Creation Functions
%%% --------------------------------------------------------------------------

%%--------------------------------------------------------------------
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

%%--------------------------------------------------------------------
%% @private
update_nf(#nf{topic = Topic, from = NfFrom} = Nf, State, From) ->
    %% Don't override the notification's from PID if it's already
    %% defined - it might have been set explicitly by a caller.
    UseFrom = case is_pid(NfFrom) of
                  true -> NfFrom;
                  false -> From
              end,
    Nf#nf{topic = sel_topic(Topic, State), from = UseFrom}.

%%--------------------------------------------------------------------
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
    set_queue(queue:new(), State).

%%--------------------------------------------------------------------
%% @private
terminate_queue(#?S{queue = Queue} = State) when Queue =/= undefined ->
    State#?S{queue = undefined}.


%%--------------------------------------------------------------------
%% @private
queue_len(State) ->
    queue:len(State#?S.queue).

-compile({inline, [queue_len/1]}).

%%--------------------------------------------------------------------
%% @private
set_queue(Queue, #?S{}=State) ->
    State#?S{queue=Queue, queue_len=queue:len(Queue)}.

-compile({inline, [set_queue/2]}).

%%--------------------------------------------------------------------
%% @private
set_queue(Queue, Len, #?S{}=State) ->
    State#?S{queue=Queue, queue_len=Len}.

-compile({inline, [set_queue/3]}).

%%--------------------------------------------------------------------
%% @private
queue_nf(#nf{}=Nf, #?S{queue = Queue,
                       queue_len = QL} = State) ->
    set_queue(queue:in(Nf, Queue), QL + 1, State).


%%--------------------------------------------------------------------
%% @private
requeue_nf(#nf{}=Nf, #?S{queue = Queue, queue_len = QL,
                         requeue_strategy = always} = State) ->
    set_queue(queue:in_r(Nf, Queue), QL + 1, State);
requeue_nf(#nf{}=Nf, #?S{requeue_strategy = debug_never} = State) ->
    ?LOG_WARNING("*** requeue_strategy = debug_never, not requeuing:\n~p",
                 [Nf]),
    State.

%%--------------------------------------------------------------------
%% @private
%% @doc Take all currently queued notifications, and all pending
%% notifications in the request store, sort them by timestamp
%% so that the oldest one is at the top of the list, and
%% replace the queue with this list. Ignore queue maxima under these
%% circumstances.

requeue_pending_nfs(#?S{queue=Queue, req_store=ReqStore,
                        requeue_strategy=always}=State) ->
    OldestFirst = fun(#apns_erlv3_req{last_mod_time=LmtL},
                      #apns_erlv3_req{last_mod_time=LmtR}) ->
                          LmtL =< LmtR
                  end,
    Nfs = [#nf{} = Req#apns_erlv3_req.nf ||
           Req <- lists:sort(OldestFirst,
                             drop_expired_nfs(req_remove_all_reqs(ReqStore)))],
    ?LOG_DEBUG("Pending nfs to requeue:\n~p", [Nfs]),
    NewQueue = queue:join(Queue, queue:from_list(Nfs)),
    State#?S{queue = NewQueue, queue_len = queue:len(NewQueue)};
requeue_pending_nfs(#?S{req_store=ReqStore,
                        requeue_strategy=debug_never}=State) ->
    ?LOG_WARNING("*** requeue_strategy = debug_never, emptying request store.",
                 []),
    req_delete_all_reqs(ReqStore),
    State.

%%% --------------------------------------------------------------------------
%%% Reconnection Delay Functions
%%% --------------------------------------------------------------------------

%% @private
schedule_reconnect(#?S{retry_ref = Ref} = State) ->
    _ = (catch gen_fsm:cancel_timer(Ref)),
    {Delay, NewState} = next_delay(State),
    ?LOG_INFO("Reconnecting APNS HTTP/2 session ~p in ~w ms",
              [State#?S.name, Delay]),
    NewRef = gen_fsm:send_event_after(Delay, connect),
    NewState#?S{retry_ref = NewRef}.


%%--------------------------------------------------------------------
%% @private
cancel_reconnect(#?S{retry_ref = Ref} = State) ->
    catch gen_fsm:cancel_timer(Ref),
    State#?S{retry_ref = undefined}.

%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
%% @private
reset_delay(State) ->
    % Reset to 1 so the first reconnection is always done after the retry delay.
    State#?S{retries = 1}.

%%--------------------------------------------------------------------
%% @private
zero_delay(State) ->
    % Reset to 0 so the first reconnection is always done immediately.
    State#?S{retries = 0}.

%%--------------------------------------------------------------------
%% @private
schedule_ping(#?S{keepalive_ref=Ref,
                  keepalive_interval=KI}=State) ->
    _ = (catch gen_fsm:cancel_timer(Ref)),
    Delay = KI * 1000,
    ?LOG_DEBUG("Scheduling PING frame (session ~p) in ~w ms",
              [State#?S.name, Delay]),
    NewRef = gen_fsm:send_event_after(Delay, ping),
    State#?S{keepalive_ref = NewRef}.

%%--------------------------------------------------------------------
%% @private
cancel_ping(#?S{keepalive_ref=Ref}=State) ->
    _ = (catch gen_fsm:cancel_timer(Ref)),
    State#?S{keepalive_ref = undefined}.

%%--------------------------------------------------------------------
%% @private
schedule_kick_sender(#?S{kick_sender_ref=Ref,
                         kick_sender_interval=KI}=State) ->
    _ = (catch gen_fsm:cancel_timer(Ref)),
    ?LOG_TRACE("Scheduling kick_sender (session ~p) in ~w ms",
               [State#?S.name, KI]),
    NewRef = gen_fsm:send_event_after(KI, kick_sender),
    State#?S{kick_sender_ref = NewRef}.

%%--------------------------------------------------------------------
%% @private
cancel_kick_sender(#?S{kick_sender_ref=Ref}=State) ->
    _ = (catch gen_fsm:cancel_timer(Ref)),
    State#?S{kick_sender_ref = undefined}.

%%% --------------------------------------------------------------------------
%%% APNS Handling Functions
%%% --------------------------------------------------------------------------

%% @private
apns_connect(Proto, Host, Port, SslOpts) ->
    h2_client:start_link(scheme_for_protocol(Proto), Host, Port, SslOpts).

%%--------------------------------------------------------------------
%% @private
apns_disconnect(undefined) ->
    ok;
apns_disconnect(Http2Client) when is_pid(Http2Client) ->
    ok = h2_client:stop(Http2Client).

%%--------------------------------------------------------------------
%% @private
-spec apns_send(Nf, State) -> Result when
      Nf :: nf(), State :: state(), Result :: {Resp, NewState},
      Resp :: {ok, StreamId} | {error, term()}, StreamId :: term(),
      NewState :: state().
apns_send(#nf{}=Nf, #?S{protocol=Proto}=State) ->
    {Opts, NewState} = make_opts(Nf, State),
    Req = make_req(Proto, Nf#nf.token, Nf#nf.json, Opts),
    Resp = case send_impl(NewState#?S.http2_pid, Req) of
               {ok, StreamId} = Result ->
                   ReqInfo = #apns_erlv3_req{stream_id=StreamId,
                                             nf=Nf, req=Req},
                   ok = req_add(NewState#?S.req_store, ReqInfo),
                   Result;
               {error, _Reason}=Error ->
                   Error
           end,
    {Resp, NewState}.

%%--------------------------------------------------------------------
%% @private
-spec apns_get_response(Http2Client, StreamId) -> Result when
      Http2Client :: pid(), StreamId :: term(),
      Result :: {ok, Resp} | not_ready, Resp :: apns_lib_http2:http2_rsp().
apns_get_response(Http2Client, StreamId) ->
    h2_connection:get_response(Http2Client, StreamId).

-compile({inline, [apns_get_response/2]}).

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

%%--------------------------------------------------------------------
%% @private
async_reply({Pid, _Tag} = Caller, UUID, Resp) ->
    ?LOG_DEBUG("async_reply for UUID ~p to caller ~p", [UUID, Caller]),
    Pid ! make_apns_response(UUID, Resp);
async_reply(Pid, UUID, Resp) when is_pid(Pid) ->
    ?LOG_DEBUG("async_reply for UUID ~p to caller ~p", [UUID, Pid]),
    Pid ! make_apns_response(UUID, Resp).
%%--------------------------------------------------------------------
%% @private
scheme_for_protocol(h2)  -> https;
scheme_for_protocol(h2c) -> http.

%%--------------------------------------------------------------------
%% @private
minimal_ssl_opts(h2) ->
    [
     {honor_cipher_order, false},
     {versions, ['tlsv1.2']},
     {alpn_preferred_protocols, [<<"h2">>]}
    ];
minimal_ssl_opts(h2c) ->
    [].

%%--------------------------------------------------------------------
%% @private
-spec make_opts(Nf, State) -> {Opts, NewState} when
      Nf :: nf(), State :: state(), Opts :: send_opts(), NewState :: state().
make_opts(Nf, #?S{apns_auth=undefined}=State) ->
    {nf_to_opts(Nf), State};
make_opts(Nf, #?S{}=State) ->
    NewState = maybe_refresh_apns_auth(State),
    NewAuth = NewState#?S.apns_auth,
    Opts = [{authorization, NewAuth} | nf_to_opts(Nf)],
    {Opts, NewState}.

%%--------------------------------------------------------------------
%% @private
make_req(h2, Token, Json, Opts) ->
    apns_lib_http2:make_req(Token, Json, Opts);
make_req(h2c, Token, Json, Opts) ->
    {ReqHdrs, ReqBody} = make_req(h2, Token, Json, Opts),
    Key = <<":method:">>,
    {lists:keystore(Key, 1, ReqHdrs, {Key, <<"http">>}), ReqBody}.

%%--------------------------------------------------------------------
%% @private
maybe_refresh_apns_auth(#?S{apns_auth=undefined}=State) ->
    State;
maybe_refresh_apns_auth(#?S{jwt_max_age_secs=MaxAgeSecs}=State) ->
    case jwt_age(State) >= MaxAgeSecs of
        true -> % Create fresh JWT
            new_apns_auth(State);
        false ->
            State
    end.

%%--------------------------------------------------------------------
%% @private
new_apns_auth(#?S{jwt_ctx=undefined}=State) ->
    State;
new_apns_auth(#?S{jwt_ctx=JwtCtx}=State) ->
    AuthJWT = apns_jwt:jwt(JwtCtx),
    State#?S{apns_auth=AuthJWT, jwt_iat=jwt_iat(AuthJWT)}.

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
nf_to_map(#nf{} = Nf) ->
    maps:from_list(nf_to_pl(Nf)).

%%--------------------------------------------------------------------
%% @private
is_nf_expired(#nf{expiry=PosixExp}, PosixNow) ->
    PosixNow >= PosixExp.

-compile({inline, [is_nf_expired/2]}).

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
    try h2_client:send_request(Http2Client, ReqHdrs, ReqBody) of
        {ok, StreamId}=Result ->
            _ = ?LOG_DEBUG("Successfully submitted request on stream id ~p",
                           [StreamId]),
            Result;
        {error, Code}=Error ->
            _ = ?LOG_ERROR("HTTP/2 client error code ~w sending request",
                           [Code]),
            Error
    catch
        What:Why ->
            ?LOG_ERROR("Exception sending request, headers: ~p\n"
                       "body: ~p\nStacktrace:~s",
                       [ReqHdrs, ReqBody, ?STACKTRACE(What, Why)]),
            Why
    end.

%%--------------------------------------------------------------------
%% @private
send_ping(Http2Client) ->
    PingFrame = http2_ping_frame(),
    _ = ?LOG_DEBUG("Sending PING frame to peer: ~p", [PingFrame]),
    ok = h2_connection:send_frame(Http2Client, PingFrame).

%%--------------------------------------------------------------------
%% @private
http2_ping_frame() ->
    Flags = 0,
    StreamId = 0, % MUST be 0 according to RFC 7540
    Payload = crypto:rand_bytes(8),
    http2_frame(?HTTP2_PING_FRAME, Flags, StreamId, Payload).

%%--------------------------------------------------------------------
%% @private
http2_frame(Type, Flags, StreamId, <<Payload/binary>>) ->
    <<(byte_size(Payload)):24, Type:8, Flags:8, 0:1, StreamId:31,
      Payload/binary>>.

-compile({inline, [http2_frame/4,
                   http2_ping_frame/0]}).

%%--------------------------------------------------------------------
%% @private
apns_deregister_token(Token) ->
    SvcTok = sc_push_reg_api:make_svc_tok(apns, Token),
    ok = sc_push_reg_api:deregister_svc_tok(SvcTok).

%%--------------------------------------------------------------------
%% @private
-spec tok_b(Token) -> BStr
    when Token :: nf() | undefined | binary() | string(), BStr :: bstrtok().
tok_b(#nf{token = Token}) ->
    Token;
tok_b(Token) when is_list(Token) ->
    sc_util:to_bin(Token);
tok_b(<<Token/binary>>) ->
    Token;
tok_b(_) ->
    <<"unknown_token">>.

%%--------------------------------------------------------------------
%% @private
make_apns_response(<<_:128>> = UUID, Resp) ->
    {apns_response, v3, {UUID, Resp}};
make_apns_response(UUID, Resp) ->
    make_apns_response(str_to_uuid(UUID), Resp).

-compile({inline, [make_apns_response/2]}).

%%--------------------------------------------------------------------
-spec get_default_topic(Protocol, Opts) -> Result when
      Protocol :: h2 | h2c,
      Opts :: [{_,_}], Result :: {ok, binary()} | {error, term()}.
%% @private
get_default_topic(h2c, Opts) ->
    {ok, pv_req(apns_topic, Opts)};
get_default_topic(h2, Opts) ->
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

%%--------------------------------------------------------------------
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
%% @private
-spec handle_end_of_stream(StreamId, StateName, State) -> Result when
      StreamId :: term(), StateName :: atom(), State :: state(),
      Result :: {next_state, StateName, NewState}, NewState :: state().
handle_end_of_stream(StreamId, StateName, #?S{http2_pid = Pid,
                                              req_store = ReqStore} = State) ->
    Result = case apns_get_response(Pid, StreamId) of
                 {ok, Resp} ->
                     RespResult = get_resp_result(Resp),
                     Req = remove_req(ReqStore, StreamId),
                     #apns_erlv3_req{nf=Nf} = Req,
                     UUID = str_to_uuid(Nf#nf.uuid),
                     _ = run_send_callback(Req, StateName,
                                           to_cb_result(UUID, RespResult)),
                     handle_resp_result(RespResult, Req, StateName, State);
                 not_ready -> % This should not happen, because this is the end of stream
                     ?LOG_CRITICAL("Internal error: not_ready after end "
                                   "of stream id ~p in state ~p",
                                   [StreamId, StateName]),
                     erlang:error({internal_error, not_ready})
             end,
    {next_state, NewStateName, _} = Result,
    notify_drained(NewStateName, req_count(ReqStore)),
    Result.

%%--------------------------------------------------------------------
%% @private
notify_drained(draining, 0) ->
    gen_fsm:send_event(self(), drained);
notify_drained(_StateName, _ReqCount) ->
    ok.

%%--------------------------------------------------------------------
%% @private
to_cb_result(UUID, {ok, [_|_]=ParsedResp}) ->
    {ok, {UUID, ParsedResp}};
to_cb_result(UUID, {error, Reason}) ->
    {error, {UUID, Reason}}.

%%--------------------------------------------------------------------
-spec handle_resp_result(RespResult, Req, StateName, State) -> Result when
      RespResult :: {ok, ParsedResp} | {error, term()},
      Req :: apns_erlv3_req() | undefined, StateName :: atom(),
      State :: state(), ParsedResp :: apns_lib_http2:parsed_rsp(),
      Result :: {next_state, NewStateName, NewState},
      NewStateName :: atom(), NewState :: state().
%% @private
handle_resp_result({ok, [_|_] = ParsedResp}, #apns_erlv3_req{} = Req,
                   StateName, State) ->
    handle_parsed_resp(ParsedResp, Req, StateName, State);
handle_resp_result({error, Reason}, #apns_erlv3_req{} = _Req,
                   StateName, State) ->
    ?LOG_WARNING("Failed to send notification on APNS HTTP/2 session ~p;\n"
                 "Reason: ~p", [State#?S.name, Reason]),
    continue(StateName, State).

%%--------------------------------------------------------------------
-spec handle_parsed_resp(ParsedResp, Req, StateName, State) -> Result when
      ParsedResp :: apns_lib_http2:parsed_rsp(),
      Req :: apns_erlv3_req() | undefined, StateName :: atom(),
      State :: state(), Result :: {next_state, NewStateName, NewState},
      NewStateName :: atom(), NewState :: state().
%% @private
handle_parsed_resp(ParsedResp, #apns_erlv3_req{} = Req, StateName,
                   #?S{}=State0) ->
    case check_status(ParsedResp) of
        ok ->
            continue(StateName, State0);
        expired_jwt -> % Regen the jwt and try again
            continue(StateName,
                     handle_expired_jwt(ParsedResp, Req, State0));
        invalid_jwt ->
            continue(StateName,
                     handle_invalid_jwt(ParsedResp, Req, State0));
        unregistered_token ->
            continue(StateName,
                     handle_unregistered_token(ParsedResp, Req, State0));
        internal_server_error ->
            State = handle_internal_server_error(ParsedResp, Req, State0),
            next(StateName, connecting_or_draining(State), zero_delay(State));
        broken_session ->
            State = handle_broken_session(ParsedResp, Req, State0),
            next(StateName, connecting_or_draining(State), zero_delay(State));
        error ->
            continue(StateName,
                     handle_parsed_resp_error(ParsedResp, Req, State0))
    end.

%%--------------------------------------------------------------------
%% @private
%% Return draining state if there are pending responses, otherwise
%% connecting state.
connecting_or_draining(State) ->
    case req_count(State#?S.req_store) of
        0 ->
            connecting;
        _ ->
            draining
    end.

%%--------------------------------------------------------------------
%% @private
-spec check_status(ParsedResp) -> Result when
      ParsedResp :: apns_lib_http2:parsed_rsp(), Result :: atom().
check_status(ParsedResp) ->
    case pv_req(status, ParsedResp) of
        <<"200">> ->
            ok;
        _Other ->
            check_fail_status(ParsedResp)
    end.

%%--------------------------------------------------------------------
%% @private
-spec check_fail_status(ParsedResp) -> Result when
      ParsedResp :: apns_lib_http2:parsed_rsp(),
      Result :: expired_jwt
              | invalid_jwt
              | internal_server_error
              | broken_session
              | unregistered_token
              | error.
check_fail_status(ParsedResp) ->
    case pv_req(reason, ParsedResp) of
        <<"BadCertificate">> ->
            error;
        <<"BadCertificateEnvironment">> ->
            error;
        <<"BadCollapseId">> ->
            error;
        <<"BadDeviceToken">> ->
            error;
        <<"BadExpirationDate">> ->
            error;
        <<"BadMessageId">> ->
            error;
        <<"BadPath">> ->
            error;
        <<"BadPriority">> ->
            error;
        <<"BadTopic">> ->
            error;
        <<"DeviceTokenNotForTopic">> ->
            error;
        <<"DuplicateHeaders">> ->
            error;
        <<"ExpiredProviderToken">> ->
            expired_jwt;
        <<"Forbidden">> ->
            error;
        <<"IdleTimeout">> ->
            broken_session;
        <<"InternalServerError">> ->
            internal_server_error;
        <<"InvalidProviderToken">> ->
            invalid_jwt;
        <<"MethodNotAllowed">> ->
            error;
        <<"MissingDeviceToken">> ->
            error;
        <<"MissingProviderToken">> ->
            error;
        <<"MissingTopic">> ->
            error;
        <<"PayloadEmpty">> ->
            error;
        <<"PayloadTooLarge">> ->
            error;
        <<"ServiceUnavailable">> ->
            broken_session;
        <<"Shutdown">> ->
            broken_session;
        <<"TooManyProviderTokenUpdates">> ->
            broken_session;
        <<"TooManyRequests">> ->
            error;
        <<"TopicDisallowed">> ->
            error;
        <<"Unregistered">> ->
            unregistered_token;
        _ ->
            error
    end.

%%--------------------------------------------------------------------
%% @private
handle_expired_jwt(ParsedResp, Req, State0) ->
    UUID = pv_req(uuid, ParsedResp),
    Nf = req_nf(Req),
    ?LOG_WARNING("Failed to send notification due to expired JWT "
                 "auth token, APNS HTTP/2 session ~p;\n"
                 "notification uuid ~s, token ~s",
                 [State0#?S.name, UUID, tok_b(Nf)]),

    State1 = maybe_recreate_auth_token(Req, State0),

    ?LOG_WARNING("Requeuing notification uuid ~s, token ~s, session ~p",
                 [UUID, tok_b(Nf), State1#?S.name]),
    State = requeue_nf(Nf, State1),
    kick_sender(self()),
    State.

%%--------------------------------------------------------------------
%% @private
handle_invalid_jwt(ParsedResp, Req, #?S{jwt_ctx=JwtCtx}=State0) ->
    Kid = apns_jwt:kid(JwtCtx),
    UUID = pv_req(uuid, ParsedResp),
    Nf = req_nf(Req),
    ?LOG_CRITICAL("ACTION REQUIRED: Invalid JWT signing key (kid: ~s)"
                  " on session ~p!\nFailed to send notification with "
                  "uuid ~s, token ~s: ~p",
                  [Kid, State0#?S.name, UUID, tok_b(Nf), ParsedResp]),
    %% FIXME: Should maybe crash session, but that will eventually crash the
    %% supervisor and all the other sessions that might have valid signing
    %% keys. Another option is to put the session into a "service unavailable"
    %% state, which will reject all requests with an invalid apns auth key
    %% error.
    State0.

%%--------------------------------------------------------------------
%% @private
handle_unregistered_token(ParsedResp, Req, State0) ->
    UUID = pv_req(uuid, ParsedResp),
    Token = tok_b(req_nf(Req)),
    ?LOG_WARNING("Failed to send notification due to invalid APNS token, "
                 "APNS HTTP/2 session ~p;\nnotification uuid ~s, token ~s",
                 [State0#?S.name, UUID, Token]),
    apns_deregister_token(Token),
    ?LOG_INFO("Deregistered token ~s", [Token]),
    State0.

%%--------------------------------------------------------------------
%% @private
handle_internal_server_error(ParsedResp, Req, State0) ->
    UUID = pv_req(uuid, ParsedResp),
    Nf = req_nf(Req),
    ?LOG_WARNING("Internal server error: Failed to send notification on ~p,"
                 " uuid: ~s, token: ~s:\nParsed resp: ~p",
                 [State0#?S.name, UUID, tok_b(Nf), ParsedResp]),
    requeue_nf(Nf, State0).

%%--------------------------------------------------------------------
%% @private
handle_broken_session(ParsedResp, Req, State0) ->
    UUID = pv_req(uuid, ParsedResp),
    Nf = req_nf(Req),
    ?LOG_WARNING("Broken session: Failed to send notification on ~p,"
                 " uuid: ~s, token: ~s:\nParsed resp: ~p",
                 [State0#?S.name, UUID, tok_b(Nf), ParsedResp]),
    requeue_nf(Nf, State0).

%%--------------------------------------------------------------------
%% @private
%% Drop the notification because it is unrecoverable
handle_parsed_resp_error(ParsedResp, Req, State0) ->
    UUID = pv_req(uuid, ParsedResp),
    Nf = req_nf(Req),
    ?LOG_WARNING("Failed to send notification on APNS HTTP/2 session"
                 " ~p, uuid: ~s, token: ~s:\nParsed resp: ~p",
                 [State0#?S.name, UUID, tok_b(Nf), ParsedResp]),
    State0.

%%--------------------------------------------------------------------
%% @private
maybe_recreate_auth_token(_Req, #?S{jwt_iat=undefined}=State) ->
    State;
maybe_recreate_auth_token(#apns_erlv3_req{last_mod_time=ReqModTime},
                          #?S{jwt_iat=IssuedAt}=State) ->
    %% Only create a new jwt if the current one is older than the
    %% failed request, because it is quite possible that a number of
    %% consecutive requests will fail because of the expired jwt, and
    %% we only want to recreate it on the first expiry error.
    case IssuedAt < ReqModTime of
        true ->
            NewState = new_apns_auth(State),
            ?LOG_DEBUG("NewState: ~p", [lager:pr(NewState, ?MODULE)]),
            NewState;
        false ->
            State
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
-spec remove_req(ReqStore, StreamId) -> Result when
      ReqStore :: term(), StreamId :: term(),
      Result :: apns_erlv3_req() | undefined.
remove_req(ReqStore, StreamId) ->
    case req_remove(ReqStore, StreamId) of
        #apns_erlv3_req{} = Req ->
            Req;
        undefined ->
            ?LOG_WARNING("Cannot find request for stream ~p", [StreamId]),
            undefined
    end.

%%--------------------------------------------------------------------
%% @private
drop_expired_nfs([#apns_erlv3_req{}|_]=L) ->
    PosixTime = sc_util:posix_time(),
    lists:filter(fun(#apns_erlv3_req{nf=Nf}) ->
                         not is_nf_expired(Nf, PosixTime)
                 end, L);
drop_expired_nfs([]) ->
    [].

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

-compile({inline, [req_nf/1, req_http_req/1]}).

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
-spec str_to_uuid(uuid_str()) -> uuid().
str_to_uuid(UUID) ->
    uuid:string_to_uuid(UUID).

%%--------------------------------------------------------------------
%% @private
-spec uuid_to_str(uuid()) -> uuid_str().
uuid_to_str(<<_:128>> = UUID) ->
    uuid:uuid_to_string(UUID, binary_standard).

-compile({inline, [str_to_uuid/1, uuid_to_str/1]}).

%%--------------------------------------------------------------------
%% @private
req_store_new(Name) ->
    ets:new(Name, [set, protected, {keypos, #apns_erlv3_req.stream_id}]).

%%--------------------------------------------------------------------
%% @private
req_store_delete(Tab) ->
    true = ets:delete(Tab),
    ok.

%%--------------------------------------------------------------------
%% @private
req_add(Tab, Req) ->
    true = ets:insert(Tab, Req),
    ok.

%%--------------------------------------------------------------------
%% @private
req_lookup(Tab, Id) ->
    case ets:lookup(Tab, Id) of
        [] ->
            undefined;
        [Req] ->
            Req
    end.

%%--------------------------------------------------------------------
%% @private
req_remove(Tab, Id) ->
    case ets:take(Tab, Id) of
        [] ->
            undefined;
        [Req] ->
            Req
    end.

%%--------------------------------------------------------------------
%% @private
req_count(Tab) ->
    ets:info(Tab, size).

-compile({inline, [req_add/2, req_lookup/2, req_remove/2, req_count/1]}).

%%--------------------------------------------------------------------
%% @private
req_remove_all_reqs(Tab) ->
    L = ets:tab2list(Tab),
    req_delete_all_reqs(Tab),
    L.

%%--------------------------------------------------------------------
%% @private
req_delete_all_reqs(Tab) ->
    true = ets:delete_all_objects(Tab).

%%--------------------------------------------------------------------
%% @private
-spec base64urldecode(Data) -> Result when
      Data :: list() | binary(), Result :: binary().
base64urldecode(Data) when is_list(Data) ->
    base64urldecode(list_to_binary(Data));
base64urldecode(<<Data/binary>>) ->
    Extra = case byte_size(Data) rem 3 of
                0 -> <<>>;
                1 -> <<"=">>;
                2 -> <<"==">>
            end,
    B64Encoded = << << case Byte of $- -> $+; $_ -> $/; _ -> Byte end >>
                    || <<Byte>> <= <<Data/binary, Extra/binary>> >>,
    base64:decode(B64Encoded).

%%--------------------------------------------------------------------
%% @private
jwt_iat(<<JWT/binary>>) ->
    [_, Body, _] = string:tokens(binary_to_list(JWT), "."),
    JSON = jsx:decode(base64urldecode(Body)),
    sc_util:req_val(<<"iat">>, JSON);
jwt_iat(undefined) ->
    undefined.

%%--------------------------------------------------------------------
%% @private
jwt_age(#?S{jwt_iat=undefined}) ->
    0;
jwt_age(#?S{jwt_iat=IssuedAt}) ->
    sc_util:posix_time() - IssuedAt.

