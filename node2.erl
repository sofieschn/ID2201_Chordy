-module(node2).
-export([start/1, start/2, node/4, stabilize/3, schedule_stabilize/0, stabilize/1, request/2, notify/4, 
         create_probe/2, remove_probe/2, forward_probe/5]).
-define(Timeout, 1000).

% Starts a node without knowing any direct connections (the first node)
start(Id) ->
    start(Id, nil).

% Starts a node with a known peer when started, connecting to an already existing Chord ring
start(Id, Peer) ->
    % Start the timer and spawn a process to initialize the node
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    % Set the predecessor to nil
    Predecessor = nil,
    
    % Connect to our successor
    {ok, Successor} = connect(Id, Peer),

    io:format("Node ~p: Successor initialized as ~p~n", [Id, Successor]),
    
    % Schedule the stabilizing procedure
    schedule_stabilize(),
    
    % Call the node/3 procedure that implements the message handling
    node(Id, Predecessor, Successor, storage:create()).

% This function sets our successor pointer.
% We are the first node.
connect(Id, nil) ->
    {ok, {Id, self()}};
% we are connecting to another peer 
connect(_Id, Peer) ->
    Qref = make_ref(), % create a unique reference for a request
    Peer ! {key, Qref, self()}, % send peer a message with our key, the reference and out pid
    receive
        {Qref, Skey} -> % response from peer is the request reference and the peers key (identifyer)
            {ok, {Skey, Peer}} % return connection to init function
    after 10000 ->
        io:format("Timeout: no response!~n") % no response = failed connection
    end.



% The properties of a node in a Chord ring: an ID, a predecessor (previous node), and a successor (next node), and a store of the the nodes key values
node(Id, Predecessor, Successor, Store) ->
    receive
        % Stabilize messages tell every node to check that they are in the right order in the Chord
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store);

        % A peer needs to know our key
        % each time a new node connects to chord with us as the known peer
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store);

        % A new node informs us of its existence
        {notify, New} ->
            Pred = notify(New, Id, Predecessor, Store), % call the notify function with the new nodes {key and id} and the id, predecessor and store 
            node(Id, Pred, Successor, Store); % recursive call to our node fun with the new predecessor (if it is the new predecessor, otherwise Pred will be our og predecessor)

        % A peer asks for our predecessor, core function of the stabilize process
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor, Store);

        % Our successor informs us about its predecessor
        % when a request has been send to another node, and they respond, it comes back as a status where we see their predecessor
        {status, Pred} ->
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ, Store);

        % Trigger the probe process (initiate from a node)
        probe ->
            io:format("Node ~p: Creating probe~n", [Id]),
            create_probe(Id, Successor),
            node(Id, Predecessor, Successor, Store);

        % If the probe reaches the originating node (Id matches)
        {probe, Id, Nodes, T} ->
            io:format("Node ~p: Probe returned! Nodes visited: ~p~n", [Id, Nodes]),
            remove_probe(T, Nodes),
            node(Id, Predecessor, Successor, Store);

        % If the probe needs to be forwarded to the successor
        {probe, Ref, Nodes, T} ->
            io:format("Node ~p: Forwarding probe to successor. Probe details: Ref=~p, Nodes=~p, Time=~p~n", 
                      [Id, Ref, Nodes, T]),
            forward_probe(Ref, T, Nodes, Id, Successor),
            node(Id, Predecessor, Successor, Store);

        % adding a new key to our store 
        {add, Key, Value, Qref, Client} ->
            NewStore = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, NewStore);

        % looking up a new key in our store 
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Store);

        % handing over elements we are no longer responsible for once a new node enters the ring 
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            node(Id, Predecessor, Successor, Merged);

        state ->
            io:format("NodeID= ~w   Pred=~w Succ=~w  Storage: ~w~n", [Id,Predecessor,Successor, Store]),
            node(Id, Predecessor, Successor, Store);

        % Catch-all clause to handle unexpected messages
        _Other ->
            io:format("Node ~p: Received unexpected message: ~p~n", [Id, _Other]),
            node(Id, Predecessor, Successor, Store)
    end.

% Stabilize function checks if the node is in the right spot in the ring based on other nodes
stabilize(Pred, Id, Successor) ->
    {Skey, Spid} = Successor,
    case Pred of
        % Case 1: The successor has no predecessor
        nil ->
            io:format("Node ~p: Successor has no predecessor. Notifying successor about our existence~n", [Id]),
            Spid ! {notify, {Id, self()}},
            Successor;

        % Case 2: The predecessor is us
        {Id, _} ->
            io:format("Node ~p: Already the predecessor. Ring is stable.~n", [Id]),
            Successor;

        % Case 3: The successor is pointing to itself as its predecessor
        {Skey, _} ->
            io:format("Node ~p: Successor pointing to itself. Notifying successor.~n", [Id]),
            Spid ! {notify, {Id, self()}},
            Successor;

        % Case 4: The successor has another node (Xkey, Xpid) as its predecessor
        % checks if Xkey (the key of the successor's predecessor) is between the current node's ID and its successor's key.
        {Xkey, Xpid} ->
            case key:between(Xkey, Id, Skey) of
                true ->
                    io:format("Node ~p: Adopting Xkey ~p as the new successor.~n", [Id, Xkey]),
                    {Xkey, Xpid}; % returns the successors predecessor as our NEW successor

                % the successors predecessor is not bigger than us (we are closer to the successor), meaning we should be the successors new predecessor
                false ->
                    io:format("Node ~p: Notifying successor ~p about our existence.~n", [Id, Skey]),
                    Spid ! {notify, {Id, self()}}, % tell the successor that we exist
                    Successor % return the old successor as our successor
            end
    end.

% Schedule the stabilize procedure to run at regular intervals
schedule_stabilize() ->
    timer:send_interval(1000, self(), stabilize).

% Stabilize by requesting the successor's predecessor
stabilize({Skey, Spid}) ->
    % Handle valid process ID case
    Spid ! {request, self()}.




% A peer asks for our predecessor
request(Peer, Predecessor) ->
    case Predecessor of
        nil -> % in case there is no predecessor, send back this info
            Peer ! {status, nil};
        {Pkey, Ppid} -> % in case we have a predecessor send back a status message with our predecessor
            Peer ! {status, {Pkey, Ppid}}
    end.

% Notify function: Being notified of a node is a way for it to propose to be our predecessor
notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        % if the old predecessor does not exist, we will directly make the new one our predecessor
        nil ->
            Keep = handover(Id, Store, Nkey, Npid), % we keep the part of the responsibilities that are ours, and hand over the rest to the new predecessor
            {Nkey, Npid};  % Return the new predecessor, not a nested tuple.
        {Pkey, _} ->
            % call key between function to see if the new predecessor key is closer to us than the old one
            case key:between(Nkey, Pkey, Id) of
                true ->
                    Keep = handover(Id, Store, Nkey, Npid), 
                    {Nkey, Npid};  % Return the new predecessor.
                false ->
                    {Predecessor, Store}  % Keep the current predecessor.
            end
    end.



% Function to create and send a probe to verify the ring connection
create_probe(Id, Successor) ->
    io:format("Node ~p: Creating probe~n", [Id]),
    Time = erlang:system_time(microsecond), % captures current time when probe is started
    {_, Spid} = Successor, % extracts the pid of the successor
    Spid ! {probe, Id, [], Time}. % sends the successor node a probe message icluding the time of the created probe

% Function to handle a returning probe (i.e., when it completes a round trip)
remove_probe(T, Nodes) ->
    TimeNow = erlang:system_time(microsecond), % takes the current time 
    TimeElapsed = TimeNow - T, % checks elapsed time by taking current time - time when probe started
    io:format("Probe completed! Nodes visited: ~p. Round-trip time: ~p microseconds.~n", [Nodes, TimeElapsed]).

% Function to forward the probe to the next node (successor)
forward_probe(Ref, T, Nodes, Id, Successor) -> 
    io:format("Node ~p: Forwarding probe to successor~n", [Id]),
    {_, Spid} = Successor, % extracts pid of the successor
    NewNodes = [Id | Nodes], % adds this id to list of current visited node id's
    Spid ! {probe, Ref, NewNodes, T}. % forward probe to successor 


add(Key, Value, Qref, Client, Id, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(Key, Pkey, Id) of
        % in case the key is within our responsibility (between our key and our predecessors key), we will add it to our store
        true ->
            io:format("Node ~p: Adding key ~p with value ~p to store~n", [Id, Key, Value]),
            Client ! {Qref, ok},
            storage:add(Key, Value, Store);
        % if the key is not within our responsibility, we will forward it to the next node in the chord (successor)
        false ->
            io:format("Node ~p: Forwarding add request for key ~p to successor~n", [Id, Key]),
            Spid ! {add, Key, Value, Qref, Client},
            Store
    end.


lookup(Key, Qref, Client, Id, {Pkey, _}, {Skey, Spid}, Store) ->
    case key:between(Key, Pkey, Id) of
        true ->
            Result = storage:lookup(Key, Store),
            io:format("Node ~p: Lookup result for key ~p: ~p~n", [Id, Key, Result]),
            Client ! {Qref, Result};
        false ->
            io:format("Node ~p: Forwarding lookup request for key ~p to successor~n", [Id, Key]),
            Spid ! {lookup, Key, Qref, Client}
    end.

handover(Id, Store, Nkey, Npid) ->
    {Keep, Rest} = storage:split(Id, Nkey, Store),
    % Send the part of the store that should be handed over to the new predecessor
    Npid ! {handover, Rest},
    Keep.  % Return the part of the store that we keep
