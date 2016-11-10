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

-module(apns_erlv3_session_sup).

-behaviour(supervisor).

%% API
-export([
          start_link/1
        , start_child/2
        , stop_child/1
        , is_child_alive/1
        , get_child_pid/1
    ]).

%% Supervisor callbacks
-export([init/1]).

-include_lib("lager/include/lager.hrl").

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

%% @doc `Sessions' looks like this:
%%
%% ```
%% [
%%     [
%%         {name, 'apns-com.example.MyApp'},
%%         {config, [
%%             {host, "api.push.apple.com" | "api.development.push.apple.com"},
%%             {port, 443 | 2197},
%%             {app_id_suffix, <<"com.example.MyApp">>},
%%             {apns_env, prod},
%%             {apns_topic, <<"com.example.MyApp">>},
%%             {retry_delay, 1000},
%%             {disable_apns_cert_validation, false},
%%             {ssl_opts, [
%%                     {certfile, "/some/path/com.example.MyApp.cert.pem"},
%%                     {keyfile, "/some/path/com.example.MyApp.key.unencrypted.pem"},
%%                     {honor_cipher_order, false},
%%                     {versions, ['tlsv1.2']},
%%                     {alpn_preferred_protocols, [<<"h2">>]}
%%                 ]
%%             }
%%          ]}
%%     ] %, ...
%% ]
%% '''
%% @end
start_link(Sessions) when is_list(Sessions) ->
    case supervisor:start_link({local, ?SERVER}, ?MODULE, []) of
        {ok, _Pid} = Res ->
            % Start children
            [{ok, _} = start_child(Opts) || Opts <- Sessions],
            Res;
        Error ->
            Error
    end.

%% @doc Start a child session.
%% == Parameters ==
%% <ul>
%%  <li>`Name' - Session name (atom)</li>
%%  <li>`Opts' - Options, see {@link apns_erlv3_session} for more details</li>
%% </ul>
start_child(Name, Opts) when is_atom(Name), is_list(Opts) ->
    supervisor:start_child(?SERVER, [Name, Opts]).

stop_child(Name) when is_atom(Name) ->
    case get_child_pid(Name) of
        Pid when is_pid(Pid) ->
            supervisor:terminate_child(?SERVER, Pid);
        undefined ->
            {error, not_started}
    end.

is_child_alive(Name) when is_atom(Name) ->
    get_child_pid(Name) =/= undefined.

get_child_pid(Name) when is_atom(Name) ->
    erlang:whereis(Name).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    Session = {
        apns_erlv3_session,
        {apns_erlv3_session, start_link, []},
        transient,
        brutal_kill,
        worker,
        [apns_erlv3_session]
    },
    Children = [Session],
    MaxR = 20,
    MaxT = 20,
    RestartStrategy = {simple_one_for_one, MaxR, MaxT},
    {ok, {RestartStrategy, Children}}.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
start_child(Opts) ->
    lager:info("Starting APNSv3 (HTTP/2) session with opts: ~p", [Opts]),
    Name = sc_util:req_val(name, Opts),
    SessCfg = sc_util:req_val(config, Opts),
    start_child(Name, SessCfg).

