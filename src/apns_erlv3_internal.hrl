-ifndef(__APNS_ERLV3_INTERNAL_HRL).
-define(__APNS_ERLV3_INTERNAL_HRL, true).

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

-define(LOG_GENERAL(Level, Fmt, Args), lager:Level(Fmt, Args)).

-ifdef(INCLUDE_TRACE_LOGGING).
-define(LOG_TRACE(Fmt, Args), ?LOG_DEBUG(Fmt, Args)).
-else.
-define(LOG_TRACE(_Fmt, _Args), (_ = ok)).
-endif.

-define(LOG_DEBUG(Fmt, Args),     ?LOG_GENERAL(debug, Fmt, Args)).
-define(LOG_INFO(Fmt, Args),      ?LOG_GENERAL(info, Fmt, Args)).
-define(LOG_NOTICE(Fmt, Args),    ?LOG_GENERAL(notice, Fmt, Args)).
-define(LOG_WARNING(Fmt, Args),   ?LOG_GENERAL(warning, Fmt, Args)).
-define(LOG_ERROR(Fmt, Args),     ?LOG_GENERAL(error, Fmt, Args)).
-define(LOG_CRITICAL(Fmt, Args),  ?LOG_GENERAL(critical, Fmt, Args)).
-define(LOG_ALERT(Fmt, Args),     ?LOG_GENERAL(alert, Fmt, Args)).
-define(LOG_EMERGENCY(Fmt, Args), ?LOG_GENERAL(emergency, Fmt, Args)).

-define(STACKTRACE(Class, Reason),
        lager:pr_stacktrace(erlang:get_stacktrace(), {Class, Reason})).

-ifdef(namespaced_queues).
-type sc_queue() :: queue:queue().
-else.
-type sc_queue() :: queue().
-endif.


-endif.

