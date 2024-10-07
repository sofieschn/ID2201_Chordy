-module(test2).
-export([add_elements/4, lookup_elements/3, run_test/4]).

% Generates random key-value pairs, adds them to the system, and returns the list of keys.
% Module - the module handling the Chord system
% Node - the node to which we're adding elements
% NumElements - number of key-value pairs to add
% Client - the client process that receives responses
add_elements(Module, Node, NumElements, Client) ->
    Keys = generate_random_keys(NumElements),
    StartTime = erlang:monotonic_time(microsecond),
    lists:foreach(fun(Key) -> 
        % Construct the value as a list and convert it to a binary
        ValueString = ["Value for key ", integer_to_list(Key)],
        Value = erlang:iolist_to_binary(ValueString),
        Node ! {add, Key, Value, make_ref(), Client}
    end, Keys),
    EndTime = erlang:monotonic_time(microsecond),
    TotalTime = EndTime - StartTime,
    io:format("Added ~p elements in ~p microseconds.~n", [NumElements, TotalTime]),
    Keys.  % Return the list of keys for later lookup.




% Looks up all elements using the keys in the list and measures the time.
% Module - the module handling the Chord system
% Node - the node to contact for lookups
% Keys - the list of keys to look up
lookup_elements(Module, Node, Keys) ->
    StartTime = erlang:monotonic_time(microsecond),
    lists:foreach(fun(Key) -> 
        Node ! {lookup, Key, make_ref(), self()}
    end, Keys),
    EndTime = erlang:monotonic_time(microsecond),
    TotalTime = EndTime - StartTime,
    io:format("Looked up ~p elements in ~p microseconds.~n", [length(Keys), TotalTime]).

% Runs the test: adds elements, then looks them up and measures the total time.
% Module - the module handling the Chord system
% Node - the node to contact for add/lookup
% NumElements - number of key-value pairs to add and lookup
% Client - the client process
run_test(Module, Node, NumElements, Client) ->
    io:format("Running test with ~p elements on node ~p~n", [NumElements, Node]),
    Keys = add_elements(Module, Node, NumElements, Client),
    io:format("Starting lookup of ~p elements...~n", [NumElements]),
    lookup_elements(Module, Node, Keys).
    
% Generates a list of random keys using key:generate/0
generate_random_keys(Num) ->
    lists:map(fun(_) -> key:generate() end, lists:seq(1, Num)).
