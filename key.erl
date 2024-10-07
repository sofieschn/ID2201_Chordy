-module(key).
-export([generate/0, between/3]).

generate() ->
    random:uniform(1000000000).

%% Check if a Key is between From and To or equal to To, this is called a partly closed interval and is denoted (From, To].
between(Key, From, To) ->
	if
		%% From is less than to, and the key is between from and To, so we return true
		(From < To) and (Key > From) and (Key =< To) ->
		    true;
		%% This is the case when from is actually bigger than To, which can happen as we have a ring structure
		%% In this case, the key can either be bigger than From or smaller than To to be between these two values.
		(From > To) and ((Key > From) or (Key =< To)) ->
        	true;
		%% From and to is the same node, return true
		From == To ->
	        true;
	    true ->
	        false
    end.