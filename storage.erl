-module(storage).
-export([create/0, add/3, lookup/2, split/3, merge/2]).

%% Create a new empty store
create() ->
    [].

%% Add a key-value pair to the store
add(Key, Value, Store) ->
    %% Use lists:keyreplace to update if the key exists, or add the key-value pair if it doesn't
	[{Key, Value}|Store].

%% Lookup a key in the store
lookup(Key, Store) ->
    case lists:keyfind(Key, 1, Store) of
        false -> false;
        {Key, Value} -> {Key, Value}
    end.

%% Split the store between two key ranges
split(Id, Nkey, Store) ->
    % Split the store into two parts: the keys that should be handed over and the keys we keep
    {ToHandOver, Keep} = lists:partition(fun({Key, _}) -> key:between(Key, Id, Nkey) end, Store),
    {Keep, ToHandOver}.


%% Merge two stores (Entries and Store)
merge(Elements, Store) ->
    lists:merge(Elements, Store).