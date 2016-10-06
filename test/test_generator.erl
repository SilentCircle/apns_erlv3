-module(test_generator).
-export([parse_transform/2]).

-define(is_debug, (get_debug() == true)).
%-define(dbg_do(X), (?is_debug andalso (fun() -> ok end)())).
-define(dbg_print(Fmt, Args),
        (?is_debug andalso io:format(Fmt, Args))).

%%--------------------------------------------------------------------
parse_transform(Forms, Options) ->
    put_debug(lists:member(debug, Options)),
    case ?is_debug of
        true ->
            io:format("Options: ~p~n", [Options]),
            io:format("============ Old forms ============~n"),
            [io:format("~p~n", [Form]) || Form <- Forms],
            io:format("============ New forms ============~n"),
            ok;
        false ->
            ok
    end,
    case catch forms(Forms) of
        {'EXIT', Reason} ->
            io:format("EXIT: ~p~n",[Reason]),
            exit(Reason);
        {error, Line, R} ->
            Error = {error, [{get_filename(), [{Line, ?MODULE, R}]}], []},
            io:format("~p~n", [Error]),
            Error;
        Else ->
            ?dbg_print("Transformed into: ~p~n", [Else]),
            Else
    end.

%%--------------------------------------------------------------------
forms(Forms) ->
    {ExpandedForms, Exports} = form(Forms, [], sets:new(), []),
    transform_exports(ExpandedForms, Exports).

form([{attribute, _, expand_test, Tests}|Fs], Acc, ExpandSet, Exports) ->
    form(Fs, Acc, add_tests(Tests, ExpandSet), Exports);
form([{attribute,_,file,{Filename,_}}=F|Fs], Acc, ExpandSet, Exports) ->
    put_filename(Filename),
    form(Fs, [F | Acc], ExpandSet, Exports);
form([{function, _, _Name, _Arity, _Clauses}=F|Fs], Acc, ExpandSet, Exports) ->
    {Exps, ExpFs} = maybe_expand(F, ExpandSet),
    form(Fs, ExpFs ++ Acc, ExpandSet, Exps ++ Exports);
form([F|Fs], Acc, ExpandSet, Exports) ->
    form(Fs, [F|Acc], ExpandSet, Exports);
form([], Acc, _ExpandSet, Exports) ->
    {lists:reverse(Acc), Exports}.

%%--------------------------------------------------------------------
transform_exports([{attribute,L,export,Exps}|Fs], Exports) ->
    UExps = lists:usort(Exps ++ Exports),
    [{attribute,L,export,UExps} | transform_exports(Fs, Exports)];
transform_exports([F | Fs], Exports) ->
    [F | transform_exports(Fs, Exports)];
transform_exports([], _Exports) ->
    [].    %% fail-safe, in case there is no module declaration

maybe_expand({function, _, Name, Arity, _Clauses}=F, ExpandSet) ->
    case sets:is_element({Name, Arity}, ExpandSet) of
        true ->
            Fs = expand(F),
            {func_names(Fs), Fs};
        false ->
            {[], [F]}
    end.

func_names(Funcs) ->
    [{Name, Arity} || {function,_,Name,Arity,_Clauses} <- Funcs].

%%--------------------------------------------------------------------
%% Expand Name/Arity so that if it contains a call
%% to apnsv3_test_gen:send_fun/2, it becomes
%% five functions (one each for modes sync and async,
%% types session and api, and the original one that now
%% "calls" the others by returning a suite test list,
%% e.g. Name(suite) -> [sync_session_Name_test,...]):
%%
%% - "sync_session_"  ++ Name ++ "test"
%% - "async_session_" ++ Name ++ "test"
%% - "sync_api_"      ++ Name ++ "test"
%% - "async_api_"     ++ Name ++ "test"
%%
%% Each of the above now call the local function send_fun/4
%% with args [Mode, Type] ++ Arguments.
%%
%% If Name/Arity contains no call to
%% apnsv3_test_gen:send_fun/2, it is considered to be
%% an error.
expand({function, Line, Name, Arity, Clauses}) ->
    NewFuns = [gen_function(Line, Name, Arity, Clauses, Mode, Type)
               || Mode <- [sync, async], Type <- [session, api]],
    CallingFun = gen_caller({function, Line, Name, Arity}, NewFuns),
    [CallingFun | NewFuns].

%%--------------------------------------------------------------------
gen_function(_Line, Name, Arity, Clauses, Mode, Type) ->
    L = erl_anno:new(0),
    TName = make_test_name(Name, Mode, Type),
    {function, L, TName, Arity, rewrite(Clauses, Mode, Type)}.

gen_caller({function, Line, CallerName, CallerArity}, FunsToCall) ->
    FunNames = [atom(Line, Name) || {function,_,Name,_,_} <- FunsToCall],
    {function, Line, CallerName, CallerArity,
     [
      suite_clause(Line, FunNames)
     ]}.

suite_clause(Line, FunNames) ->
    clause(Line, [atom(Line, suite)], [], [cons(Line, FunNames)]).

clause(Line, Args, Guards, Exprs) ->
    {clause, Line, Args, Guards, Exprs}.

cons(Line, [A|As]) ->
    {cons, Line, A, cons(Line, As)};
cons(Line, []) ->
    {nil, Line}.

atom(Line, A) -> {atom, Line, A}.

%%--------------------------------------------------------------------
rewrite(Clauses, Mode, Type) ->
    rewrite(Clauses, Mode, Type, []).

rewrite([{clause, Line, Args, Guards, Exprs}|Cs]=_Clauses,
        Mode, Type, Acc) ->
    ?dbg_print("rewrite(~p, ~p, ~p, ~p~n", [_Clauses, Mode, Type, Acc]),
    NewExprs = [rewrite_expr(Expr, Mode, Type) || Expr <- Exprs],
    NewAcc = [{clause, Line, Args, Guards, NewExprs} | Acc],
    rewrite(Cs, Mode, Type, NewAcc);
rewrite([], _Mode, _Type, Acc) ->
    ?dbg_print("rewrite(~p, ~p, ~p, ~p~n", [[], _Mode, _Type, Acc]),
    lists:reverse(Acc).

%%--------------------------------------------------------------------
rewrite_expr({call,_,{remote, _,
                        {atom,_,apnsv3_test_gen},
                        {atom,_,FuncName}}, [_,_] = Args}=_Expr,
              Mode, Type) ->
    ?dbg_print("rewrite_expr(~p, ~p, ~p)~n", [_Expr, Mode, Type]),
    L = erl_anno:new(0),
    %% Presend the Mode and Type args
    EArgs = [{atom, L, Mode}, {atom, L, Type} | Args],
    %% Rewrite the call
    {call, L, {atom, L, FuncName}, EArgs};
rewrite_expr(Expr, Mode, Type) when is_tuple(Expr) ->
    ?dbg_print("rewrite_expr(~p, ~p, ~p)~n", [Expr, Mode, Type]),
    list_to_tuple(rewrite_expr(tuple_to_list(Expr), Mode, Type));
rewrite_expr(Expr, Mode, Type) when is_list(Expr) ->
    ?dbg_print("rewrite_expr(~p, ~p, ~p)~n", [Expr, Mode, Type]),
    [rewrite_expr(E, Mode, Type) || E <- Expr];
rewrite_expr(Expr, _Mode, _Type) ->
    ?dbg_print("rewrite_expr(~p, ~p, ~p)~n", [Expr, _Mode, _Type]),
    Expr.

%%--------------------------------------------------------------------
%% Process dictionary functions
%%--------------------------------------------------------------------
get_filename() -> get(filename).
get_debug() -> get(verbose).
put_filename(Name) -> put(filename, Name).
put_debug(State) -> put(verbose, State).

%%--------------------------------------------------------------------
add_tests(Tests, ExpandSet) ->
    lists:foldl(fun({_Name, _Arity}=El, Set) -> sets:add_element(El, Set) end,
                ExpandSet, Tests).

%%--------------------------------------------------------------------
make_test_name(Name, Mode,
               Type) when is_atom(Name) andalso
                          (Mode =:= sync orelse Mode =:= async) andalso
                          (Type =:= session orelse Type =:= api) ->
    list_to_atom(lists:concat([atom_to_list(Mode), "_",
                               atom_to_list(Type), "_",
                               atom_to_list(Name)])).
