-module(test_generator_test).
-compile({parse_transform, test_generator}).
-export([clear_badge_test/1]).

-expand_test([
              clear_badge_test/1
             ]).

clear_badge_test(doc) -> ["Clear badge"];
clear_badge_test(suite) -> [];
clear_badge_test(Config) ->
    F = apnsv3_test_gen:send_fun(#{badge => 0}, success),
    for_all_sessions(F, proplists:get_value(sessions, Config)).

send_fun(Mode, Type, #{} = Map, ExpStatus) ->
    io:format("send_fun(~p, ~p, ~p, ~p)~n", [Mode, Type, Map, ExpStatus]).

for_all_sessions(Fun, Sessions) when is_function(Fun, 1), is_list(Sessions) ->
    [Fun(Session) || Session <- Sessions].
