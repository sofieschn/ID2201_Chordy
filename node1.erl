-module(node1).
-export([start/1, start/2, node/3, stabilize/3, schedule_stabilize/0, stabilize/1, request/2, notify/3]).

% Start a node without a peer (first node)
start(Id) ->
    start(Id, nil).

% Start a node with a known peer
start(Id, Peer) ->
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    % Set the predecessor to nil since we don't know it yet
    Predecessor = nil,
    % Connect to a peer (or initialize as the first node)
    {ok, Successor} = connect(Id, Peer),
    % Schedule the stabilization procedure
    schedule_stabilize(),
    % Start the node's main message-handling loop
    node(Id, Predecessor, Successor).

% Define our successor
connect(Id, nil) ->
    io:format("Node ~p: No peer found, initializing as own successor~n", [Id]),
    {ok, {Id, self()}};
connect(Id, Peer) ->
    Qref = make_ref(),
    io:format("Node ~p: Attempting to connect to peer ~p~n", [Id, Peer]),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            io:format("Node ~p: Connected to peer with key ~p~n", [Id, Skey]),
            {ok, {Skey, Peer}};
        after 10000 ->
            io:format("Node ~p: Timeout - no response from peer ~p~n", [Id, Peer]),
            {error, timeout}
    end.

node(Id, Predecessor, Successor) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor);
        {notify, New} ->
            Pred = notify(New, Id, Predecessor),
            node(Id, Pred, Successor);
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor);
        {status, Pred} ->
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ);
        _Other ->
            io:format("Node ~p: Received unexpected message: ~p~n", [Id, _Other]),
            node(Id, Predecessor, Successor)
    end.

stabilize(Pred, Id, Successor) ->
    {Skey, Spid} = Successor,
    case Pred of
        nil ->
            Spid ! {notify, {Id, self()}},
            Successor;
        {Id, _} ->
            Successor;
        {Skey, _} ->
            Spid ! {notify, {Id, self()}},
            Successor;
        {Xkey, Xpid} ->
            case key:between(Xkey, Id, Skey) of
                true -> {Xkey, Xpid};
                false ->
                    Spid ! {notify, {Id, self()}},
                    Successor
            end
    end.

schedule_stabilize() ->
    timer:send_interval(1000, self(), stabilize).

stabilize({_, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor) ->
    case Predecessor of
        nil -> Peer ! {status, nil};
        {Pkey, Ppid} -> Peer ! {status, {Pkey, Ppid}}
    end.

notify({Nkey, Npid}, Id, Predecessor) ->
    case Predecessor of
        nil -> {Nkey, Npid};
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                true -> {Nkey, Npid};
                false -> Predecessor
            end
    end.
