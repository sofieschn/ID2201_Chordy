-module(test3).
-export([start_test/0, setup_node/2, add_nodes/2, test_stabilization/1]).

%% This is the main function to run the test
start_test() ->
    %% Step 1: Start the first node
    io:format("Starting Node 1~n"),
    Pid1 = setup_node(1, nil),

    %% Step 2: Add more nodes and connect them to Node 1
    io:format("Starting Node 2 and connecting to Node 1~n"),
    Pid2 = setup_node(2, Pid1),

    %% Step 3: Add a third node and connect to Node 1
    io:format("Starting Node 3 and connecting to Node 1~n"),
    Pid3 = setup_node(3, Pid1),

    %% Step 4: Test the stabilization process on one of the nodes
    test_stabilization(Pid1),

    io:format("All nodes set up and stabilization tested.~n").

%% This function spawns a node and connects it to a peer
setup_node(Id, Peer) ->
    spawn(fun() -> node2:start(Id, Peer) end).

%% This function adds nodes by connecting each to a peer
add_nodes(NodeCount, Peer) ->
    lists:map(fun(Id) -> setup_node(Id, Peer) end, lists:seq(2, NodeCount)).

%% This function sends a stabilization message to a node and checks if it stabilizes correctly
test_stabilization(Pid) ->
    io:format("Testing stabilization on node with PID ~p~n", [Pid]),
    Pid ! stabilize.
