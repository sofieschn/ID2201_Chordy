-module(node1).
-export([start/1, start/2, node/3, stabilize/3, schedule_stabilize/0, stabilize/1, request/2, notify/3, create_probe/2, remove_probe/2, forward_probe/5]).
-define(Timeout,1000).



% starts a node without knowing any direct connections (the first node ex)
start(Id) ->
    start(Id, nil).

% starts a node with a known peer when started. Connecting to an already existing ring chord ring
start(Id, Peer) ->
    % Start the timer and spawn a process to initialize the node
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

 init(Id, Peer) ->
     %% Set the predecessor to nil
     Predecessor = nil,
 
     %% Connect to our successor
     {ok, Successor} = connect(Id, Peer),
 
     %% Schedule the stabilizing procedure; or rather making sure that we send a stabilize message to ourselves
     schedule_stabilize(),
 
     %% We then call the node/3 procedure that implements the message handling
     node(Id, Predecessor, Successor).
 
    %% This function sets our successor pointer.
    %% We are the first node


connect(Id, nil) ->
    io:format("Node ~p: No peer found, initializing as own successor~n", [Id]),
    {ok, {Id, self()}};

connect(Id, Peer) ->
    Qref = make_ref(),
    io:format("Node ~p: Attempting to connect to peer ~p with ref ~p~n", [Id, Peer, Qref]),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            io:format("Node ~p: Connected to peer. Successor key is ~p~n", [Id, Skey]),
            % Update the successor
            {ok, {Skey, Peer}}
        after 10000 ->
            io:format("Node ~p: Timeout - no response from peer ~p~n", [Id, Peer]),
            {error, timeout}
    end.



% the properties of a node in a chord ring has an ID, a predecessor (node that comes before it), and a successor (node that comes after it )
node(Id, Predecessor, Successor) ->
    receive
        % stabilize messages tell every node to check that they are in the right order in the chord
        stabilize ->
            % call stabilize function
            stabilize(Successor),
            % recursive call with the new 
            node(Id, Predecessor, Successor);
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor);
        {notify, New} ->
            Pred = notify(New, Id, Predecessor),
            node(Id, Pred, Successor);
        {request, Peer} ->
            % asks our pred
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor);
        {status, Pred} ->
            % A node will send a stabilize message to update our placement in the chord 
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ);

        % Trigger the probe process (initiate from a node)
    probe ->
        io:format("Node ~p: Creating probe~n", [Id]),
        create_probe(Id, Successor),
        node(Id, Predecessor, Successor);

    % If the probe reaches the originating node (Id matches)
    {probe, Id, Nodes, T} ->
        io:format("Node ~p: Probe returned! Nodes visited: ~p~n", [Id, Nodes]),
        remove_probe(T, Nodes),
        node(Id, Predecessor, Successor);

    % If the probe needs to be forwarded to the successor
    {probe, Ref, Nodes, T} ->
        io:format("Node ~p: Forwarding probe to successor. Probe details: Ref=~p, Nodes=~p, Time=~p~n", 
                  [Id, Ref, Nodes, T]),
        forward_probe(Ref, T, Nodes, Id, Successor),
        node(Id, Predecessor, Successor);

    % Catch-all clause to handle unexpected messages
    _Other ->
        io:format("Node ~p: Received unexpected message: ~p~n", [Id, _Other]),
        node(Id, Predecessor, Successor)
end.


% we handle the order of the chord ring. the function checks if the node is in the right spot in the ring, based on the other nodes in the 
% ring and their keys. This function is done at regular intervals to make sure that the chord ring is up to date. 

stabilize(Pred, Id, Successor) ->
    % Destructure the Successor tuple to get its Key (Skey) and Process ID (Spid)
    {Skey, Spid} = Successor,
    
    % Begin checking what the predecessor (Pred) is
    case Pred of
        % Case 1: The successor has no predecessor (Pred is nil)
        nil ->  
            io:format("Node ~p: Successor has no predecessor. Notifying successor about our existence~n", [Id]),
            % Inform the successor about our existence by sending it a notify message
            Spid ! {notify, {Id, self()}},
            % We don't change the successor in this case, so return the same Successor
            Successor;
        
        % Case 2: The predecessor is us (meaning we are already the predecessor)
        {Id, _} ->  
            io:format("Node ~p: Already the predecessor. Ring is stable.~n", [Id]),
            % The ring is stable, no need to notify, so return the current Successor
            Successor;
        
        % Case 3: The successor is pointing to itself as its predecessor (indicating a small ring or no other nodes)
        {Skey, _} ->  
            io:format("Node ~p: Successor pointing to itself. Notifying successor.~n", [Id]),
            % Notify the successor about our existence (so we can insert ourselves into the ring)
            Spid ! {notify, {Id, self()}},
            % Return the current Successor, since we just notified it
            Successor;
        
        % Case 4: The successor has another node (Xkey, Xpid) as its predecessor
        {Xkey, Xpid} ->  
            % Now we need to check if the predecessor's key (Xkey) is between our key (Id) and the successor's key (Skey)
            case key:between(Xkey, Id, Skey) of
                % If Xkey is between our key and Skey, we need to adopt Xkey as the new successor
                true ->  
                    io:format("Node ~p: Adopting Xkey ~p as the new successor.~n", [Id, Xkey]),
                    % Return the new successor as Xkey with its corresponding process ID Xpid
                    {Xkey, Xpid};
                
                % If Xkey is not between our key and Skey, we notify the successor about our existence
                false ->  
                    io:format("Node ~p: Notifying successor ~p about our existence.~n", [Id, Skey]),
                    % Send a notify message to the successor
                    Spid ! {notify, {Id, self()}},
                    % Return the current Successor because no change is needed
                    Successor
            end
    end.


% schedule_stabilize/0 sets up a timer to call the stabilize procedure every 1000 ms or changed for faster/slower upd of ring
schedule_stabilize() ->
    timer:send_interval(5000, self(), stabilize).

% stabilize/1 sends a request message to the current successor to request its predecessor
%% {_, Spid}: The Successor is a tuple {Skey, Spid} where Skey is the successor’s key, and Spid is its process ID.
%% The current node sends a {request, self()} message to the successor (Spid), asking for its predecessor.
stabilize({_, Spid}) ->
    % Ask the successor for its predecessor by sending the {request, self()} message
    Spid ! {request, self()}.
    

% a node wants to know whether its successor has a predecessor that should become its new successor (i.e., a node that is closer to it in the ring).
request(Peer, Predecessor) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil}; % If there's no predecessor, send back nil
        {Pkey, Ppid} ->
            Peer ! {status, {Pkey, Ppid}} % Send back the predecessor's key and process ID
end.


notify({Nkey, Npid}, Id, Predecessor) ->
    case Predecessor of
        % If there is no predecessor, accept the new node as the predecessor
        nil ->
            %% Npid ! {accepted, Id},
            {Nkey, Npid};
        
        % If the predecessor is already set, check if the new node should be the predecessor
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                % If the new node's key fits between the predecessor and us, accept it as the new predecessor
                true ->
                    % Npid ! {accepted, Id},
                    {Nkey, Npid};
                
                % Otherwise, keep the current predecessor and inform the new node it was not accepted
                false ->
                    % Npid ! {rejected, Id},
                    Predecessor
            end
    end.


%% Probe - verification of the chord ring connection
%%If the node receiving the probe is the originating node (I matches the node’s ID), the node records the round-trip time and reports it.
%%If the node is not the originating node, it forwards the probe to its successor and adds its own process identifier to the list of visited nodes.


% Function to create and send a probe
create_probe(Id, Successor) ->
    io:format("Node ~p: Creating probe~n", [Id]),
    Time = erlang:system_time(microsecond),  % Get the current time
    {_, Spid} = Successor,  % Extract successor process ID
    Spid ! {probe, Id, [], Time}.  % Send probe with our Id, empty list of nodes, and timestamp.

% Function to handle a returning probe (i.e., when it completes a round trip)
remove_probe(T, Nodes) ->
    TimeNow = erlang:system_time(microsecond),  % Get the current time
    TimeElapsed = TimeNow - T,  % Calculate the round-trip time
    io:format("Probe completed! Nodes visited: ~p. Round-trip time: ~p microseconds.~n", [Nodes, TimeElapsed]).

% Function to forward the probe to the next node (successor)
forward_probe(Ref, T, Nodes, Id, Successor) ->
    io:format("Node ~p: Forwarding probe to successor~n", [Id]),
    {_, Spid} = Successor,  % Get the successor's process ID
    NewNodes = [Id | Nodes],  % Add the current node to the list of visited nodes
    Spid ! {probe, Ref, NewNodes, T}.  % Forward the probe to the successor.
