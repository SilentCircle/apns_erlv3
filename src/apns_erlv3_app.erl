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

-module(apns_erlv3_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

-include_lib("lager/include/lager.hrl").

%% ===================================================================
%% Application callbacks
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc Start the `apns_erlv3' application.
%% @end
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    {ok, App} = application:get_application(?MODULE),
    Env = application:get_all_env(App),
    lager:info("Starting app ~p with env: ~p", [App, Env]),
    Sessions = sc_util:req_val(sessions, Env),
    Service = sc_util:req_val(service, Env),
    case sc_push_svc_apnsv3:start_link(Sessions) of
        {ok, _} = Res ->
            ok = sc_push_lib:register_service(Service),
            Res;
        Err ->
            Err
    end.

%%--------------------------------------------------------------------
%% @doc Stop the `apns_erlv3' application.
%% @end
%%--------------------------------------------------------------------
stop(_State) ->
    try
        {ok, App} = application:get_application(?MODULE),
        Opts = application:get_all_env(App),
        Service = sc_util:req_val(service, Opts),
        SvcName = sc_util:req_val(name, Service),
        sc_push_lib:unregister_service(SvcName)
    catch
        Class:Reason ->
            lager:error("Unable to deregister apns v3 service: ~p",
                        [{Class, Reason}])
    end,
    ok.
