-ifndef(__APNS_ERLV3_DEFS_HRL).
-define(__APNS_ERLV3_DEFS_HRL, true).

-define(assertMsg(Cond, Fmt, Args),
        case (Cond) of
        true ->
            ok;
        false ->
            ct:fail("Assertion failed: ~p~n" ++ Fmt, [??Cond] ++ Args)
    end
       ).

-define(assert(Cond), ?assertMsg((Cond), "", [])).

-endif.
