-module(erljson_bench).

-export([main/1]).

workers() -> 10.
iters() -> 1000.

%% Just make sure we have everythign on the
%% code path.
smoke() ->
    lists:map(fun(Module) ->
        {ok, true} = Module:decode(<<"true">>),
        {ok, <<"true">>} = Module:encode(true)
    end, [json, ejson_test]),
    lists:map(fun(Module) ->
        true = Module:decode(<<"true">>),
        <<"true">> = Module:encode(true)
    end, [jiffy, jsonx, mochijson2]).


load_doc(DocName) ->
    {ok, [Doc]} = file:consult("data/" ++ DocName),
    Doc.

load_json(DocName) ->
    Json = mochijson2:encode(load_doc(DocName)),
    iolist_to_binary(Json).


test_encode(Workers, Iters, Module, Doc) ->
    Self = self(),
    Fun = fun() -> run_encode(Self, Iters, Module, Doc, 0) end,
    [spawn(Fun) || _ <- lists:seq(1, Workers)],
    Total = collect_times(Workers, 0),
    {Total, Module}.

run_encode(Dst, 0, _, _, Total) ->
    Dst ! {time, Total};
run_encode(Dst, Iters, Module, Doc0, Total) when Module =:= jsx ->
    Doc = jsonx:decode(jsonx:encode(Doc0), [{format, proplist}]),
    {Time, _} = timer:tc(Module, encode, [Doc]),
    run_encode(Dst, Iters-1, Module, Doc, Total+Time);
run_encode(Dst, Iters, Module, Doc, Total) ->
    {Time, _} = timer:tc(Module, encode, [Doc]),
    run_encode(Dst, Iters-1, Module, Doc, Total+Time).


test_decode(Workers, Iters, Module, Json) ->
    Self = self(),
    Fun = fun() -> run_decode(Self, Iters, Module, Json, 0) end,
    [spawn(Fun) || _ <- lists:seq(1, Workers)],
    Total = collect_times(Workers, 0),
    {Total, Module}.

run_decode(Dst, 0, _, _, Total) ->
    Dst ! {time, Total};
run_decode(Dst, Iters, Module, Json, Total) ->
    {Time, _} = timer:tc(Module, decode, [Json]),
    run_decode(Dst, Iters-1, Module, Json, Total+Time).


collect_times(0, Total) ->
    Total;
collect_times(N, Total) ->
    receive
        {time, Time} -> Time
    end,
    collect_times(N-1, Total+Time).

main([]) ->
    main(["base_doc.erl"]);
main([DocName]) ->
    smoke(),

    Doc = load_doc(DocName),
    Json = load_json(DocName),

    Modules = shuffle([jiffy, jsonx, json, jsx, ejson_test, mochijson2]),

    EncodeInfo = lists:map(fun(M) ->
        test_encode(workers(), iters(), M, Doc)
    end, Modules),

    DecodeInfo = lists:map(fun(M) ->
        test_decode(workers(), iters(), M, Json)
    end, Modules),

    lists:foreach(fun({Time, Module}) ->
        io:format("encode: ~15s: ~16b~n", [Module, Time])
    end, lists:sort(EncodeInfo)),

    io:format("~n~n", []),

    lists:foreach(fun({Time, Module}) ->
        io:format("decode: ~15s: ~16b~n", [Module, Time])
    end, lists:sort(DecodeInfo)),

    ok.

shuffle(List) ->
    List2 = [{random:uniform(), M} || M <- List],
    [M || {_, M} <- lists:sort(List2)].
