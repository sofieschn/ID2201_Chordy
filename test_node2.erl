-module(test_node2).
-export([start_test/4, generate_keys/1, add_keys/3, lookup_keys/2]).

% Start the test procedure. 
% It takes the NodePid (to communicate with a node), the number of keys (NumKeys),
% the ClientPid (self or another process acting as the client), and the action (add or lookup).
start_test(NodePid, NumKeys, ClientPid, Action) ->
    Keys = generate_keys(NumKeys),
    case Action of
        add ->
            add_keys(NodePid, Keys, ClientPid);
        lookup ->
            lookup_keys(NodePid, Keys)
    end.

% Function to generate a list of random keys.
generate_keys(Num) ->
    [key:generate() || _ <- lists:seq(1, Num)].

% Function to add key-value pairs to the system.
% It takes NodePid (to communicate with a node), the list of Keys, and ClientPid (client process).
add_keys(NodePid, Keys, ClientPid) ->
    StartTime = erlang:system_time(microsecond),
    lists:foreach(fun(Key) ->
        Value = <<(random:uniform(1000)):16>>,
        Qref = make_ref(),
        NodePid ! {add, Key, Value, Qref, ClientPid},
        receive
            {Qref, ok} ->
                io:format("Key ~p added successfully~n", [Key])
        after 5000 ->
            io:format("Timeout adding key ~p~n", [Key])
        end
    end, Keys),
    EndTime = erlang:system_time(microsecond),
    TotalTime = EndTime - StartTime,
    io:format("Added ~p keys in ~p microseconds~n", [length(Keys), TotalTime]).

% Function to look up key-value pairs from the system.
% It takes NodePid (to communicate with a node) and the list of Keys.
lookup_keys(NodePid, Keys) ->
    StartTime = erlang:system_time(microsecond),
    lists:foreach(fun(Key) ->
        Qref = make_ref(),
        NodePid ! {lookup, Key, Qref, self()},
        receive
            {Qref, {Key, Value}} ->
                io:format("Lookup successful for Key ~p: Value ~p~n", [Key, Value]);
            {Qref, false} ->
                io:format("Lookup failed for Key ~p~n", [Key])
        after 5000 ->
            io:format("Timeout during lookup for Key ~p~n", [Key])
        end
    end, Keys),
    EndTime = erlang:system_time(microsecond),
    TotalTime = EndTime - StartTime,
    io:format("Lookup of ~p keys completed in ~p microseconds~n", [length(Keys), TotalTime]).
