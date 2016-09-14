

# Module sc_push_svc_apnsv3 #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

Apple Push Notification Service (APNS) API.

__Behaviours:__ [`supervisor`](supervisor.md).

__Authors:__ Edwin Fine ([`efine@silentcircle.com`](mailto:efine@silentcircle.com)).

<a name="description"></a>

## Description ##

This is the API to the Apple Push Notification Service Provider.


### <a name="Synopsis">Synopsis</a> ###



#### <a name="Starting_a_session">Starting a session</a> ####


```
   Opts = [
               {host, "api.development.push.apple.com"},
               {port, 443},
               {bundle_seed_id, <<"com.example.Push">>},
               {bundle_id, <<"com.example.Push">>},
               {ssl_opts, [
                   {certfile, "/somewhere/cert.pem"},
                   {keyfile, "/somewhere/key.unencrypted.pem"}
                   ]
               }
           ],
   {ok, Pid} = sc_push_svc_apnsv3:start_session(my_push_tester, Opts).
```


#### <a name="Sending_an_alert_via_the_API">Sending an alert via the API</a> ####


```
   Notification = [{alert, Alert}, {token, <<"e7b300...a67b">>}],
   {ok, SeqNo} = sc_push_svc_apnsv3:send(my_push_tester, Notification).
```


#### <a name="Sending_an_alert_via_a_session_(for_testing_only)">Sending an alert via a session (for testing only)</a> ####


```
   JSON = get_json_payload(), % See APNS docs for format
   {ok, SeqNo} = apns_erlv3_session:send(my_push_tester, Token, JSON).
```


#### <a name="Stopping_a_session">Stopping a session</a> ####


```
   ok = sc_push_svc_apnsv3:stop_session(my_push_tester).
```

<a name="types"></a>

## Data Types ##




### <a name="type-gen_proplist">gen_proplist()</a> ###


<pre><code>
gen_proplist() = <a href="sc_types.md#type-proplist">sc_types:proplist</a>(atom(), term())
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#async_send-2">async_send/2</a></td><td>Asynchronously sends a notification specified by proplist <code>Notification</code>
to <code>SvrRef</code>; Same as <a href="#send-2"><code>send/2</code></a> beside returning only 'ok' for success.</td></tr><tr><td valign="top"><a href="#async_send-3">async_send/3</a></td><td>Asynchronously sends a notification specified by proplist <code>Notification</code>
to <code>SvrRef</code>; Same as <a href="#send-3"><code>send/3</code></a> beside returning only 'ok' for success.</td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#send-2">send/2</a></td><td>Send a notification specified by proplist <code>Notification</code>
to <code>SvrRef</code>.</td></tr><tr><td valign="top"><a href="#send-3">send/3</a></td><td>Send a notification specified by proplist <code>Notification</code>
via <code>SvrRef</code> using options <code>Opts</code>.</td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td><code>Opts</code> is a list of proplists.</td></tr><tr><td valign="top"><a href="#start_session-2">start_session/2</a></td><td>Start named session for specific host and certificate as
supplied in the proplist <code>Opts</code>.</td></tr><tr><td valign="top"><a href="#stop_session-1">stop_session/1</a></td><td>Stop named session.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="async_send-2"></a>

### async_send/2 ###

<pre><code>
async_send(Name::term(), Notification::<a href="#type-gen_proplist">gen_proplist()</a>) -&gt; ok | {error, Reason::term()}
</code></pre>
<br />

Asynchronously sends a notification specified by proplist `Notification`
to `SvrRef`; Same as [`send/2`](#send-2) beside returning only 'ok' for success.

<a name="async_send-3"></a>

### async_send/3 ###

<pre><code>
async_send(Name::term(), Notification::<a href="#type-gen_proplist">gen_proplist()</a>, Opts::<a href="#type-gen_proplist">gen_proplist()</a>) -&gt; ok | {error, Reason::term()}
</code></pre>
<br />

Asynchronously sends a notification specified by proplist `Notification`
to `SvrRef`; Same as [`send/3`](#send-3) beside returning only 'ok' for success.

<a name="init-1"></a>

### init/1 ###

`init(Opts) -> any()`

<a name="send-2"></a>

### send/2 ###

<pre><code>
send(Name::term(), Notification::<a href="#type-gen_proplist">gen_proplist()</a>) -&gt; {ok, Ref::term()} | {error, Reason::term()}
</code></pre>
<br />

Send a notification specified by proplist `Notification`
to `SvrRef`.

Set the notification to expire in a very very long time.


#### <a name="Example">Example</a> ####

Send an alert with a sound and extra data

```
  Name = 'com.example.AppId',
  Notification = [
     {alert, <<"Hello">>},
     {token, <<"ea3f...">>},
     {aps, [
       {sound, <<"bang">>},
       {extra, [{a, 1}]}]}
  ],
  sc_push_svc_apnsv3:send(Name, Notification).
```

__See also:__ [send/3](#send-3).

<a name="send-3"></a>

### send/3 ###

<pre><code>
send(Name::term(), Notification::<a href="#type-gen_proplist">gen_proplist()</a>, Opts::<a href="#type-gen_proplist">gen_proplist()</a>) -&gt; {ok, Ref::term()} | {error, Reason::term()}
</code></pre>
<br />

Send a notification specified by proplist `Notification`
via `SvrRef` using options `Opts`.
Note that `Opts` currently has no supported actions.

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Opts::list()) -&gt; {ok, pid()} | {error, term()}
</code></pre>
<br />

`Opts` is a list of proplists.
Each proplist is a session definition containing
name, mod, and config keys.

<a name="start_session-2"></a>

### start_session/2 ###

<pre><code>
start_session(Name::atom(), Opts::list()) -&gt; {ok, pid()} | {error, already_started} | {error, Reason::term()}
</code></pre>
<br />

Start named session for specific host and certificate as
supplied in the proplist `Opts`.

__See also:__ [apns_erlv3_session_sup:start_child/2](apns_erlv3_session_sup.md#start_child-2).

<a name="stop_session-1"></a>

### stop_session/1 ###

<pre><code>
stop_session(Name::atom()) -&gt; ok | {error, Reason::term()}
</code></pre>
<br />

Stop named session.

