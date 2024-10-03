-module(node1).
-export([]).



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
        % Catch-all clause to handle unexpected messages
        _Other ->
            io:format("Received unexpected message: ~p~n", [_Other]),
            node(Id, Predecessor, Successor)
    end.


% we handle the order of the chord ring. the function checks if the node is in the right spot in the ring, based on the other nodes in the 
% ring and their keys. 

    stabilize(Pred, Id, Successor) ->
        % Destructure the Successor tuple to get its Key (Skey) and Process ID (Spid)
        {Skey, Spid} = Successor,
        
        % Begin checking what the predecessor (Pred) is
        case Pred of
            % Case 1: The successor has no predecessor (Pred is nil)
            nil ->  
                % Inform the successor about our existence by sending it a notify message
                Spid ! {notify, {Id, self()}},
                % We don't change the successor in this case, so return the same Successor
                Successor;
            
            % Case 2: The predecessor is us (meaning we are already the predecessor)
            {Id, _} ->  
                % The ring is stable, no need to notify, so return the current Successor
                Successor;
            
            % Case 3: The successor is pointing to itself as its predecessor (indicating a small ring or no other nodes)
            {Skey, _} ->  
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
                        % Return the new successor as Xkey with its corresponding process ID Xpid
                        {Xkey, Xpid};
                    
                    % If Xkey is not between our key and Skey, we notify the successor about our existence
                    false ->  
                        % Send a notify message to the successor
                        Spid ! {notify, {Id, self()}},
                        % Return the current Successor because no change is needed
                        Successor
                end
        end.
    