-module(key).
-export([generate/0, between/3]).

generate() ->
    random:uniform(1000000000).


% checks if Key is between From and To on the Chord ring
between(Key, From, To) when From == To ->
    true; % If From == To, it means the full circle, so everything is between

between(Key, From, To) when From < To ->
    Key > From andalso Key =< To; % Normal case: From < To

between(Key, From, To) when From > To ->
    Key > From orelse Key =< To. % The ring wraps around, so we check if Key is > From or <= To
