-module(coordinator).
-compile(export_all).

%-define(PRINT_TRACE, ok).
-define(DELETE_TRACE, ok).

-type internal_error() :: 'internal_concolic_error'
                        | 'internal_codeserver_error'
                        | 'internal_traceserver_error'.
-type result() :: {'ok', node(), concolic:exec_info()}
                | {'runtime_error', node(), concolic:exec_info()}
                | {internal_error(), term()}.
-type ret()    :: {'ok', {term(), term()}}       %% Successful Execution
                | {'error', term()}              %% Runtime Error
                | {'ierror', internal_error()}.  %% Internal Error

%% -----------------------------------------------------------------------------
%% Concolic Execution of an M, F, As
%% -----------------------------------------------------------------------------

-spec run(atom(), atom(), [term()]) -> ret().
run(M, F, As) ->
  process_flag(trap_exit, true),
  CoreDir = "core_temp",
  TraceDir = "traces",
  Start = now(),
  Concolic = concolic:init_server(M, F, As, CoreDir, TraceDir),
  R = receive
        {'EXIT', Concolic, Why} ->
          {'internal_concolic_error', Why};
        {Concolic, Results} ->
          Results
      end,
  End  = now(),
  Time = timer:now_diff(End, Start),
  io:format("%% Time elapsed = ~w secs~n", [Time/1000000]),
  analyze(R),
  Traces = trace_dir(R),
  lists:foreach(fun clear_dir/1, Traces),
  %% Directory will only be deleted if it's empty
  _ = file:del_dir(filename:absname(TraceDir)),
  get_result(R).
  
%% Retrieve the outcome of the concolic execution
%% from the resulting execution information
-spec get_result(result()) -> ret().

get_result({'ok', Node, R}) ->
  {ok, Info} = orddict:find(Node, R),
  {'ok', proplists:get_value('result', Info)};
get_result({'runtime_error', Node, R}) ->
  {ok, Info} = orddict:find(Node, R),
  {Node, _Who, {CErr, _Serr}} = proplists:get_value('runtime_error', Info),
  {'error', CErr};
get_result({Error, _Reason}) ->
  {'ierror', Error}.
  
%% -----------------------------------------------------------------------------
%% Run demos
%% -----------------------------------------------------------------------------
  
%% Bencherl Demos
-spec run_bencherl_demos() -> 'ok'.
run_bencherl_demos() ->
  Version = 'short',  %% Version :: short | intermediate | long
  Cores = 2,          %% Cores = erlang:system_info(schedulers_online),
  Conf = [{number_of_cores, Cores}],
%%  Benchmarks = [bang, genstress, big, ehb, ets_test, mbrot, parallel, pcmark, serialmsg, timer_wheel, ran],
  Benchmarks = [bang, genstress, big, ehb, ets_test, parallel, pcmark, serialmsg, timer_wheel],
  RunOne = 
    fun(Bench) ->
      io:format("~n===> Simulating ~w (~w, ~w) ...~n", [Bench, Version, Conf]),
      Args = Bench:bench_args(Version, Conf),
      lists:foreach(fun(A) -> run(Bench, run, [A, foo, bar]) end, Args)
    end,
  lists:foreach(RunOne, Benchmarks).
  
%% My Demos
-spec run_my_demos() -> 'ok'.
run_my_demos() ->
  Demos = [{fib, [4]}, {min, [[5,1,3]]}, {spawn_apply, [erlang,'++',[[1,2,3],[a,b,c]]]}],
  F = fun({F, As}) ->
    io:format("~n===> Simulating apply(demo, ~w, ~w) ...~n", [F, As]),
    run(demo, F, As)
  end,
  lists:foreach(F, Demos).
  
%% -----------------------------------------------------------------------------
%% Report Results
%% -----------------------------------------------------------------------------
analyze({'internal_concolic_error', Error}) ->
  io:format("%%   Internal ConcServer error : ~p~n", [Error]);
analyze({'internal_codeserver_error', Node, Results}) ->
  io:format("%%   Internal CodeServer Error in node ~p~n", [Node]),
  report(Results);
analyze({'internal_traceserver_error', Node, Results}) ->
  io:format("%%   Internal TraceServer Error in node ~p~n", [Node]),
  report(Results);
analyze({runtime_error, Node, Results}) ->
  io:format("%%   Runtime error in Node ~p~n", [Node]),
  report(Results);
analyze({ok, _Node, Results}) ->
  report(Results).
  
report(R) ->
  L = orddict:to_list(R),
  lists:foreach(fun report_node/1, L).
  
report_node({N, R}) ->
  io:format("%% Node ~w~n", [N]),
  lists:foreach(fun report_result/1, R).
  
report_result({result, {CR, SR}}) ->
  io:format("%%   Concrete Result = ~p~n", [CR]),
  io:format("%%   Symbolic Result = ~p~n", [SR]);
report_result({mapping, R}) ->
  io:format("%%   Mapping = ~p~n", [R]);
report_result({runtime_error, {_Node, Who, {CErr, SErr}}}) ->
  io:format("%%   Runtime Error in ~p~n", [Who]),
  io:format("%%   Concrete Error = ~p~n", [CErr]),
  io:format("%%   Symbolic Error = ~p~n", [SErr]);
report_result({clogs, Logs}) ->
  io:format("%%   Loaded ~w Modules: ~w~n", [length(Logs), Logs]);
report_result({tlogs, Logs}) ->
  io:format("%%   Monitored Processes : ~w~n", [proplists:get_value(procs, Logs)]),
  io:format("%%   Traces Directory : ~p~n", [proplists:get_value(dir, Logs)]);
report_result({codeserver_error, Error}) ->
  io:format("%%   CodeServer Error = ~p~n", [Error]);
report_result({traceserver_error, Error}) ->
  io:format("%%   TraceServer Error = ~p~n", [Error]);
report_result(X) ->
  io:format("Unexpected ~w~n", [X]).

%% -----------------------------------------------------------------------------

trace_dir({_Status, _Node, Results}) ->
  Ns = orddict:to_list(Results),
  Rs = lists:map(fun({_N, R}) -> R end, Ns),
  Logs = proplists:get_all_values(tlogs, lists:flatten(Rs)),
  [proplists:get_value(dir, L) || L <- Logs];
trace_dir({error, _Error}) ->
  [].
  
%% temporary deleting all traces
clear_dir(D) ->
  case filelib:is_regular(D) of
    true ->
      {ok, F} = concolic_encdec:open_file(D, read),
      print_trace(F, D),
      concolic_encdec:close_file(F),
      delete_trace(D);
    false ->
      case file:del_dir(D) of
        ok -> ok;
        {error, eexist} ->
          {ok, L} = file:list_dir(D),
          LL = lists:map(fun(X) -> D ++ "/" ++ X end, L),
          lists:foreach(fun clear_dir/1, LL),
          file:del_dir(D);
        _ -> ok
      end
  end.

-ifdef(PRINT_TRACE).
print_trace(F, D) ->
  io:format("%% Contents of ~p~n", [D]),
  concolic_encdec:pprint(F).
-else.
print_trace(_F, _D) ->
  ok.
-endif.

-ifdef(DELETE_TRACE).
delete_trace(F) ->
  file:delete(F).
-else.
delete_trace(_F) ->
  ok.
-endif.
