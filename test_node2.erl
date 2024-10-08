-module(test_node2).
-export([start_test/2, add_elements/4, lookup_elements/3]).

% Start the test procedure by adding and then looking up key-value pairs.
start_test(Node, NumElements) ->
    % Add key-value pairs to the distributed store and keep track of the keys
    Keys = add_elements(Node, NumElements, 1, []),
    
    % Perform lookups on all the added keys and measure the time it takes
    {ok, StartTime} = timer:tc(?MODULE, lookup_elements, [Node, Keys, NumElements]),
    io:format("Lookup completed in ~p microseconds~n", [StartTime]).

% Add random key-value pairs to the node
add_elements(Node, NumElements, Current, Keys) when Current =< NumElements ->
    Key = random:uniform(100000),  % Generate a random key
    Value = "Value-" ++ integer_to_list(Key),  % Generate a value based on the key using string concatenation
    Ref = make_ref(),  % Create a unique reference for the request
    Node ! {add, Key, Value, Ref, self()},  % Send add request to the node
    receive
        {Ref, ok} ->  % Wait for the node to acknowledge the add operation
            io:format("Added key ~p with value ~p~n", [Key, Value]),
            add_elements(Node, NumElements, Current + 1, [Key | Keys])
    end;
add_elements(_, NumElements, Current, Keys) when Current > NumElements ->
    Keys.  % Return the list of added keys

% Lookup all keys and measure the time
lookup_elements(Node, [Key | Rest], TotalKeys) ->
    Ref = make_ref(),  % Create a unique reference for the lookup
    Node ! {lookup, Key, Ref, self()},  % Send lookup request to the node
    receive
        {Ref, Value} ->  % Wait for the node to return the result
            io:format("Looked up key ~p and found value ~p~n", [Key, Value]),
            lookup_elements(Node, Rest, TotalKeys)
    end;
lookup_elements(_, [], _) ->
    ok.  % All lookups completed
