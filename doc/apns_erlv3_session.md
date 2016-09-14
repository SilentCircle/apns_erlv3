

# Module apns_erlv3_session #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

APNS V3 (HTTP/2) server session.

Copyright (c) (C) 2012-2016 Silent Circle LLC

__Behaviours:__ [`gen_fsm`](gen_fsm.md).

__Authors:__ Edwin Fine ([`efine@silentcircle.com`](mailto:efine@silentcircle.com)).

<a name="description"></a>

## Description ##

There must be one session per App Bundle ID and certificate (Development or
Production) combination. Sessions must have unique (i.e. they are
registered) names within the node.

When connecting or disconnecting, all the notifications received by the
session are put in the input queue. When the connection is established, all
the queued notifications are sent to the APNS server.

When failing to connect, the delay between retries will grow exponentially
up to a configurable maximum value. The delay is reset when successfully
reconnecting.

When the session receives an error from APNS servers, it unregisters the
token if the error was due to a bad token.

Process configuration:


<dt><code>host</code>:</dt>




<dd>is the hostname of the APNS HTTP/2 service as a binary string. This may
be omitted as long as <code>apns_env</code> is present. In this case, the code will
choose a default host using <code>apns_lib_http2:host_port/1</code> based on the
environment.
</dd>



<dt><code>port</code>:</dt>




<dd>is the port of the APNS HTTP/2 service as a positive integer. This may
be omitted as long as <code>apns_env</code> is present. In this case, the code will
choose a default port using <code>apns_lib_http2:host_port/1</code> based on the
environment.
</dd>



<dt><code>apns_env</code>:</dt>




<dd>is the push notification environment. This can be either <code>'dev'</code>
or <code>'prod'</code>. This is *mandatory* if either <code>host</code> or <code>port</code> are
omitted. If
</dd>



<dt><code>bundle_seed_id</code>:</dt>




<dd>is the APNS bundle seed identifier as a binary. This is used to
validate the APNS certificate unless <code>disable_apns_cert_validation</code>
is <code>true</code>.
</dd>



<dt><code>apns_topic</code>:</dt>




<dd><p>is the <b>default</b> APNS topic to which to push notifications. If a
topic is provided in the notification, it always overrides the default.
This must be one of the topics in <code>certfile</code>, otherwise the notifications
will all fail, unless the topic is explicitly provided in the
notifications.
<br />
If this is omitted and the certificate is a multi-topic certificate, the
notification will fail unless the topic is provided in the actual push
notification. Otherwise, with regular single-topic certificates, the
first app bundle id in <code>certfile</code> is used.</p><p></p>Default value:
<ul>
<li>If multi-topic certificate: none (notification will fail)</li>
<li>If NOT multi-topic certificate: First app bundle ID in <code>certfile</code></li>
</ul>
</dd>



<dt><code>retry_delay</code>:</dt>




<dd><p>is the minimum time in milliseconds the session will wait before
reconnecting to APNS servers as an integer; when reconnecting multiple
times this value will be multiplied by 2 for every attempt.</p><p></p><p>Default value: <code>1000</code>.</p><p></p></dd>



<dt><code>retry_max</code>:</dt>




<dd><p>is the maximum amount of time in milliseconds that the session will wait
before reconnecting to the APNS servers.</p><p></p><p>Default value: <code>60000</code>.</p><p></p></dd>



<dt><code>disable_apns_cert_validation</code>:</dt>




<dd><p>is <code>true</code> is APNS certificate validation against its bundle id
should be disabled, <code>false</code> if the validation should be done.
This option exists to allow for changes in APNS certificate layout
without having to change code.</p><p></p>Default value: <code>false</code>.
</dd>



<dt><code>ssl_opts</code>:</dt>




<dd>is the property list of SSL options including the certificate file path.
</dd>




#### <a name="Example_configuration">Example configuration</a> ####


```
       [{host, "api.development.push.apple.com"},
        {port, 443},
        {apns_env, dev},
        {bundle_seed_id, <<"com.example.MyApp">>},
        {apns_topic, <<"com.example.MyApp">>},
        {retry_delay, 1000},
        {disable_apns_cert_validation, false},
        {ssl_opts,
         [{certfile, "/some/path/com.example.MyApp--DEV.cert.pem"},
          {keyfile, "/some/path/com.example.MyApp--DEV.key.unencrypted.pem"},
          {honor_cipher_order, false},
          {versions, ['tlsv1.2']},
          {alpn_preferred_protocols, [<<"h2">>]}].
         ]}
       ]
```


<a name="types"></a>

## Data Types ##




### <a name="type-bstrtok">bstrtok()</a> ###


<pre><code>
bstrtok() = binary()
</code></pre>

 binary of string rep of APNS token.



### <a name="type-fsm_ref">fsm_ref()</a> ###


<pre><code>
fsm_ref() = atom() | pid()
</code></pre>




### <a name="type-option">option()</a> ###


<pre><code>
option() = {host, string()} | {port, non_neg_integer()} | {bundle_seed_id, binary()} | {apns_env, prod | dev} | {apns_topic, binary()} | {ssl_opts, list()} | {retry_delay, non_neg_integer()} | {retry_max, pos_integer()}
</code></pre>




### <a name="type-options">options()</a> ###


<pre><code>
options() = [<a href="#type-option">option()</a>]
</code></pre>




### <a name="type-send_opt">send_opt()</a> ###


<pre><code>
send_opt() = {token, <a href="#type-bstrtok">bstrtok()</a>} | {topic, binary()} | {id, <a href="/home/efine/work/sc/open_source/apns_erlv3/_build/default/lib/apns_erl_util/doc/apns_lib_http2.md#type-uuid_str">apns_lib_http2:uuid_str()</a>} | {priority, integer()} | {expiry, integer()} | {json, binary()}
</code></pre>




### <a name="type-send_opts">send_opts()</a> ###


<pre><code>
send_opts() = [<a href="#type-send_opt">send_opt()</a>]
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#async_send-2">async_send/2</a></td><td>Asynchronously send notification in <code>Opts</code>.</td></tr><tr><td valign="top"><a href="#async_send-3">async_send/3</a></td><td></td></tr><tr><td valign="top"><a href="#async_send-4">async_send/4</a></td><td>Send a push notification asynchronously.</td></tr><tr><td valign="top"><a href="#async_send-5">async_send/5</a></td><td>Send a push notification asynchronously.</td></tr><tr><td valign="top"><a href="#code_change-4">code_change/4</a></td><td></td></tr><tr><td valign="top"><a href="#connected-2">connected/2</a></td><td></td></tr><tr><td valign="top"><a href="#connected-3">connected/3</a></td><td></td></tr><tr><td valign="top"><a href="#connecting-2">connecting/2</a></td><td></td></tr><tr><td valign="top"><a href="#connecting-3">connecting/3</a></td><td></td></tr><tr><td valign="top"><a href="#disconnecting-2">disconnecting/2</a></td><td></td></tr><tr><td valign="top"><a href="#disconnecting-3">disconnecting/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_state-1">get_state/1</a></td><td></td></tr><tr><td valign="top"><a href="#get_state_name-1">get_state_name/1</a></td><td></td></tr><tr><td valign="top"><a href="#handle_event-3">handle_event/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-3">handle_info/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_sync_event-4">handle_sync_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_connected-1">is_connected/1</a></td><td></td></tr><tr><td valign="top"><a href="#send-2">send/2</a></td><td></td></tr><tr><td valign="top"><a href="#send-3">send/3</a></td><td>Equivalent to <a href="#send-4"><tt>send(FsmRef, 2147483647, Token, JSON)</tt></a>.</td></tr><tr><td valign="top"><a href="#send-4">send/4</a></td><td>Send a notification specified by APS <code>JSON</code> to <code>Token</code> via
<code>FsmRef</code>.</td></tr><tr><td valign="top"><a href="#send-5">send/5</a></td><td>Send a notification specified by APS <code>JSON</code> to <code>Token</code> via
<code>FsmRef</code>.</td></tr><tr><td valign="top"><a href="#start-2">start/2</a></td><td>Start a named session as described by the options <code>Opts</code>.</td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td>Start a named session as described by the options <code>Opts</code>.</td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td>Stop session.</td></tr><tr><td valign="top"><a href="#terminate-3">terminate/3</a></td><td></td></tr><tr><td valign="top"><a href="#validate_binary-2">validate_binary/2</a></td><td></td></tr><tr><td valign="top"><a href="#validate_boolean-2">validate_boolean/2</a></td><td></td></tr><tr><td valign="top"><a href="#validate_integer-2">validate_integer/2</a></td><td></td></tr><tr><td valign="top"><a href="#validate_list-2">validate_list/2</a></td><td></td></tr><tr><td valign="top"><a href="#validate_non_neg-2">validate_non_neg/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="async_send-2"></a>

### async_send/2 ###

<pre><code>
async_send(FsmRef, Opts) -&gt; {ok, UUID} | {error, term()}
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Opts = <a href="#type-send_opts">send_opts()</a></code></li><li><code>UUID = <a href="/home/efine/work/sc/open_source/apns_erlv3/_build/default/lib/apns_erl_util/doc/apns_lib_http2.md#type-uuid_str">apns_lib_http2:uuid_str()</a></code></li></ul>

Asynchronously send notification in `Opts`.
Return UUID of request or error. If `id` is not provided in `Opts`,
generate a UUID for this request.

<a name="async_send-3"></a>

### async_send/3 ###

<pre><code>
async_send(FsmRef, Token, JSON) -&gt; ok
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Token = binary()</code></li><li><code>JSON = binary()</code></li></ul>

<a name="async_send-4"></a>

### async_send/4 ###

<pre><code>
async_send(FsmRef, Expiry, Token, JSON) -&gt; ok
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Expiry = non_neg_integer()</code></li><li><code>Token = binary()</code></li><li><code>JSON = binary()</code></li></ul>

Send a push notification asynchronously. See send/4 for details.

<a name="async_send-5"></a>

### async_send/5 ###

<pre><code>
async_send(FsmRef, Expiry, Token, JSON, Prio) -&gt; ok
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Expiry = non_neg_integer()</code></li><li><code>Token = binary()</code></li><li><code>JSON = binary()</code></li><li><code>Prio = non_neg_integer()</code></li></ul>

Send a push notification asynchronously. See send/5 for details.

<a name="code_change-4"></a>

### code_change/4 ###

`code_change(OldVsn, StateName, State, Extra) -> any()`

<a name="connected-2"></a>

### connected/2 ###

`connected(Event, State) -> any()`

<a name="connected-3"></a>

### connected/3 ###

`connected(Event, From, State) -> any()`

<a name="connecting-2"></a>

### connecting/2 ###

`connecting(Event, State) -> any()`

<a name="connecting-3"></a>

### connecting/3 ###

`connecting(Event, From, State) -> any()`

<a name="disconnecting-2"></a>

### disconnecting/2 ###

`disconnecting(Event, State) -> any()`

<a name="disconnecting-3"></a>

### disconnecting/3 ###

`disconnecting(Event, From, State) -> any()`

<a name="get_state-1"></a>

### get_state/1 ###

`get_state(FsmRef) -> any()`

<a name="get_state_name-1"></a>

### get_state_name/1 ###

`get_state_name(FsmRef) -> any()`

<a name="handle_event-3"></a>

### handle_event/3 ###

`handle_event(Event, StateName, State) -> any()`

<a name="handle_info-3"></a>

### handle_info/3 ###

`handle_info(Info, StateName, ?S) -> any()`

<a name="handle_sync_event-4"></a>

### handle_sync_event/4 ###

`handle_sync_event(Event, From, StateName, State) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="is_connected-1"></a>

### is_connected/1 ###

`is_connected(FsmRef) -> any()`

<a name="send-2"></a>

### send/2 ###

<pre><code>
send(FsmRef, Opts) -&gt; Result
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Opts = <a href="#type-send_opts">send_opts()</a></code></li><li><code>Result = {ok, undefined | UUID} | {error, Reason}</code></li><li><code>UUID = <a href="/home/efine/work/sc/open_source/apns_erlv3/_build/default/lib/apns_erl_util/doc/apns_lib_http2.md#type-uuid_str">apns_lib_http2:uuid_str()</a></code></li><li><code>Reason = term()</code></li></ul>

<a name="send-3"></a>

### send/3 ###

<pre><code>
send(FsmRef, Token, JSON) -&gt; {ok, undefined | UUID} | {error, Reason}
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Token = binary()</code></li><li><code>JSON = binary()</code></li><li><code>UUID = <a href="/home/efine/work/sc/open_source/apns_erlv3/_build/default/lib/apns_erl_util/doc/apns_lib_http2.md#type-uuid_str">apns_lib_http2:uuid_str()</a></code></li><li><code>Reason = term()</code></li></ul>

Equivalent to [`send(FsmRef, 2147483647, Token, JSON)`](#send-4).

<a name="send-4"></a>

### send/4 ###

<pre><code>
send(FsmRef, Expiry, Token, JSON) -&gt; {ok, undefined | UUID} | {error, Reason}
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Expiry = non_neg_integer()</code></li><li><code>Token = binary()</code></li><li><code>JSON = binary()</code></li><li><code>UUID = <a href="/home/efine/work/sc/open_source/apns_erlv3/_build/default/lib/apns_erl_util/doc/apns_lib_http2.md#type-uuid_str">apns_lib_http2:uuid_str()</a></code></li><li><code>Reason = term()</code></li></ul>

Send a notification specified by APS `JSON` to `Token` via
`FsmRef`. Expire the notification after the epoch `Expiry`.
For JSON format, see
[
Local and Push Notification Programming Guide
](https://developer.apple.com/library/ios/#documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/) (requires Apple Developer login).

It the notification has been sent to an APNS server, the function returns
its UUID, if it has been queued but could not be sent before
the default timeout (5000 ms) it returns undefined.

<a name="send-5"></a>

### send/5 ###

<pre><code>
send(FsmRef, Expiry, Token, JSON, Prio) -&gt; Result
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li><li><code>Expiry = non_neg_integer()</code></li><li><code>Token = binary()</code></li><li><code>JSON = binary()</code></li><li><code>Prio = non_neg_integer()</code></li><li><code>Result = {ok, Resp} | {error, Reason}</code></li><li><code>Resp = <a href="/home/efine/work/sc/open_source/apns_erlv3/_build/default/lib/apns_erl_util/doc/apns_lib_http2.md#type-parsed_rsp">apns_lib_http2:parsed_rsp()</a></code></li><li><code>Reason = term()</code></li></ul>

Send a notification specified by APS `JSON` to `Token` via
`FsmRef`. Expire the notification after the epoch `Expiry`.
Set the priority to a valid value of `Prio` (currently 5 or 10,
10 may not be used to push notifications without alert, badge or sound).

If the notification has been sent to an APNS server, the function returns
its UUID, if it has been queued but could not be sent before
the default timeout (5000 ms) it returns undefined.

<a name="start-2"></a>

### start/2 ###

<pre><code>
start(Name, Opts) -&gt; {ok, Pid} | ignore | {error, Error}
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Opts = <a href="#type-options">options()</a></code></li><li><code>Pid = pid()</code></li><li><code>Error = term()</code></li></ul>

Start a named session as described by the options `Opts`.  The name
`Name` is registered so that the session can be referenced using the name to
call functions like send/3. Note that this function is only used
for testing; see start_link/2.

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Name, Opts) -&gt; {ok, Pid} | ignore | {error, Error}
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Opts = <a href="#type-options">options()</a></code></li><li><code>Pid = pid()</code></li><li><code>Error = term()</code></li></ul>

Start a named session as described by the options `Opts`.  The name
`Name` is registered so that the session can be referenced using the name to
call functions like send/3.

<a name="stop-1"></a>

### stop/1 ###

<pre><code>
stop(FsmRef) -&gt; ok
</code></pre>

<ul class="definitions"><li><code>FsmRef = <a href="#type-fsm_ref">fsm_ref()</a></code></li></ul>

Stop session.

<a name="terminate-3"></a>

### terminate/3 ###

`terminate(Reason, StateName, State) -> any()`

<a name="validate_binary-2"></a>

### validate_binary/2 ###

<pre><code>
validate_binary(Name, Value) -&gt; Value
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Value = binary()</code></li></ul>

<a name="validate_boolean-2"></a>

### validate_boolean/2 ###

<pre><code>
validate_boolean(Name, Value) -&gt; Value
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Value = boolean()</code></li></ul>

<a name="validate_integer-2"></a>

### validate_integer/2 ###

<pre><code>
validate_integer(Name, Value) -&gt; Value
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Value = term()</code></li></ul>

<a name="validate_list-2"></a>

### validate_list/2 ###

<pre><code>
validate_list(Name, Value) -&gt; Value
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Value = list()</code></li></ul>

<a name="validate_non_neg-2"></a>

### validate_non_neg/2 ###

<pre><code>
validate_non_neg(Name, Value) -&gt; Value
</code></pre>

<ul class="definitions"><li><code>Name = atom()</code></li><li><code>Value = non_neg_integer()</code></li></ul>

