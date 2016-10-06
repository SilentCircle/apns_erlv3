-ifndef(__APNS_ERLV3_DEFS_HRL).
-define(__APNS_ERLV3_DEFS_HRL, true).

-undef(NOASSERT).
-ifndef(ASSERT).
-define(ASSERT, true).
-endif.

%% include the assert macros; ASSERT overrides NOASSERT if defined
-include_lib("stdlib/include/assert.hrl").

-define(assertMsg(BoolExpr, Fmt, Args),
        begin
            ((fun () ->
                      case (BoolExpr) of
                          true -> ok;
                          __V -> erlang:error({assertMsg,
                                               [{module, ?MODULE},
                                                {line, ?LINE},
                                                {expression, (??BoolExpr)},
                                                {expected, true},
                                                {message, lists:flatten(
                                                            io_lib:format(Fmt, Args))},
                                                case __V of false -> {value, __V};
                                                            _ -> {not_boolean,__V}
                                                end]})
                      end
              end)())
        end).

-define(name(Session), apns_erlv3_test_support:value(name, Session)).
-define(token(Session), apns_erlv3_test_support:bin_prop(token, Session)).

-define(sessions(Config), apns_erlv3_test_support:value(sessions, Config)).

-define(is_valid_mode(Mode), (Mode =:= sync orelse Mode =:= async)).
-define(is_valid_type(Type), (Type =:= session orelse Type =:= api)).
-define(is_valid_mt(Mode, Type), (?is_valid_mode(Mode) andalso
                                  ?is_valid_type(Type))).

-define(pstatus(PR), apns_erlv3_test_support:value(status, PR)).
-define(puuid(PR), apns_erlv3_test_support:value(id, PR)).
-define(preason(PR), apns_erlv3_test_support:value(reason, PR)).

-endif.
