-module(test_node2).
-compile(export_all).

%% The Timeout for receive operations
-define(Timeout, 1000).

%% Start a set of nodes and connect them in a ring
start_test() ->
    %% Start the first node
    io:format("Starting Node 1~n"),
    Pid1 = node2:start(1),
    io:format("Node 1 started with PID ~p~n", [Pid1]),

    %% Start Node 2 and connect to Node 1
    io:format("Starting Node 2 and connecting to Node 1~n"),
    Pid2 = node2:start(2, Pid1),
    io:format("Node 2 started with PID ~p~n", [Pid2]),

    %% Start Node 3 and connect to Node 1
    io:format("Starting Node 3 and connecting to Node 1~n"),
    Pid3 = node2:start(3, Pid1),
    io:format("Node 3 started with PID ~p~n", [Pid3]),

    %% Test Stabilization
    test_stabilize([Pid1, Pid2, Pid3]),

    %% Test Add and Lookup operations
    test_add_lookup(Pid1, Pid2, Pid3),

    %% Test Handover between nodes
    test_handover(Pid1, Pid2),

    %% Return result after testing
    io:format("All nodes set up and storage/lookup/handover tested.~n"),
    ok.

%% Test Stabilization by sending a stabilize message to all nodes
test_stabilize([]) ->
    ok;
test_stabilize([Pid | Rest]) ->
    io:format("Testing stabilization on node with PID ~p~n", [Pid]),
    Pid ! stabilize,
    test_stabilize(Rest).

%% Test Add and Lookup operations
test_add_lookup(Pid1, Pid2, Pid3) ->
    %% Add a key-value pair to Node 1
    io:format("Testing Add/Lookup on Node 1~n"),
    test_add_lookup_on_node(Pid1),
    
    %% Add a key-value pair to Node 2
    io:format("Testing Add/Lookup on Node 2~n"),
    test_add_lookup_on_node(Pid2),
    
    %% Add a key-value pair to Node 3
    io:format("Testing Add/Lookup on Node 3~n"),
    test_add_lookup_on_node(Pid3).

%% Test Add/Lookup operations for a given node
test_add_lookup_on_node(Pid) ->
    Key = key:generate(),
    Value = <<"TestValue">>,
    
    %% Add Key-Value
    io:format("Adding key-value pair to Node with PID ~p: ~p => ~p~n", [Pid, Key, Value]),
    Pid ! {add, Key, Value, make_ref(), self()},

    %% Wait for confirmation
    receive
        {_, ok} ->
            io:format("Successfully added key ~p to Node with PID ~p~n", [Key, Pid])
    after ?Timeout ->
        io:format("Failed to add key ~p to Node with PID ~p (timeout)~n", [Key, Pid])
    end,

    %% Lookup Key
    io:format("Looking up key ~p from Node with PID ~p~n", [Key, Pid]),
    Pid ! {lookup, Key, make_ref(), self()},
    
    %% Wait for lookup result
    receive
        {_, {Key, LookupValue}} ->
            io:format("Successfully found key ~p with value ~p on Node with PID ~p~n", [Key, LookupValue, Pid])
    after ?Timeout ->
        io:format("Lookup failed for key ~p on Node with PID ~p (timeout)~n", [Key, Pid])
    end.

%% Test Handover of key-value pairs between two nodes
test_handover(Pid1, Pid2) ->
    %% Simulate a handover
    io:format("Simulating handover from Node 1 to Node 2~n"),
    Pid1 ! {handover, [{1234, <<"Value for 1234">>}, {5678, <<"Value for 5678">>}]},

    %% Check if Node 2 has received the handover data
    io:format("Looking up handover key on Node 2~n"),
    Pid2 ! {lookup, 1234, make_ref(), self()},
    
    %% Wait for lookup result
    receive
        {_, {1234, LookupValue}} ->
            io:format("Node 2 successfully received handover: key 1234 with value ~p~n", [LookupValue])
    after ?Timeout ->
        io:format("Handover failed for key 1234 on Node 2 (timeout)~n")
    end.
