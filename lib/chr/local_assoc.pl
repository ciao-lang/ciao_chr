%   File   : ASSOC.PL
%   Author : R.A.O'Keefe
%   Updated: 9 November 1983
%   Purpose: Binary tree implementation of "association lists".

%   Note   : the keys should be ground, the associated values need not be.

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Adapted for SWI-Prolog by Jan Wielemaker, January 2004.

To the best of my knowledge, this file   is in the public domain and can
therefore safely be distributed with SWI-Prolog and used in applications
without restrictions.

Various versions of this file exists. This   one  is copied from the YAP
library. The SICStus library contains  one   using  AVL  trees to ensure
proper balancing. Although based  on  this   library  they  changed  the
argument order of some of the predicates.

Richard O'Keefe has told me he  is  working   on  a  new version of this
library. This new version, as it becomes available, is likely to replace
this one.

If you wish to use this library  in   an  application, be aware that its
interface may change. If the new version   becomes  available it will be
documented in the SWI-Prolog Reference Manual.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */


/*
Balancing code merged from L.Damas, V.S.Costa, AVL trees in YAP.
Tree is either:

*) empty (t/0)  or
*) t(Key,Value,Balance,Left,Right)
   Left,Right: trees
   Balance: <, -, or > denoting |L|-|R| = 1, 0, or -1, respectively

TODO: is_assoc/1, get_next_assoc/4, get_prev_assoc/4,
      del_assoc/4, del_min_assoc/4, del_max_assoc/4 for SICStus compatibility

TODO: exploit order in ord_list_to_assoc/2

*/



:- module(local_assoc,
	  [ assoc_to_list/2,		% +Assoc, ?List
	    empty_assoc/1,		% -Assoc
	    gen_assoc/3,		% ?Key, +Assoc, ?Value
	    get_assoc/3,		% +Key, +Assoc, ?Value
	    get_assoc/5,		% +Key, +Assoc, ?Old, ?NewAssoc, +New
	    list_to_assoc/2,		% +List, ?Assoc
%% Ciao begin
%	    map_assoc/2,		% :Goal, +Assoc
%	    map_assoc/3,		% :Goal, +AssocIn, ?AssocOut
%% Ciao end
	    max_assoc/3,		% +Assoc, ?Key, ?Value
	    min_assoc/3,		% +Assoc, ?Key, ?Value
	    ord_list_to_assoc/2,	% +List, ?Assoc
	    put_assoc/4			% +Key, +Assoc, +Value, ?NewAssoc
	  ]).

%:- meta_predicate map_assoc(:, ?).
%:- meta_predicate map_assoc(:, ?, ?).

%% Ciao begin
% :- module_transparent
% 	map_assoc/2,
% 	map_assoc/3,
% 	map_assoc_/2,
% 	map_assoc_/3.
:- push_prolog_flag( multi_arity_warnings , off ).
%% Ciao end

empty_assoc(t).


assoc_to_list(Assoc, List) :-
	assoc_to_list(Assoc, List, []).

assoc_to_list(t(Key,Val,_,L,R), List, Rest) :-
	assoc_to_list(L, List, [Key-Val|More]),
	assoc_to_list(R, More, Rest).
assoc_to_list(t, List, List).


gen_assoc(Key, t(_,_,_,L,_), Val) :-
	gen_assoc(Key, L, Val).
gen_assoc(Key, t(Key,Val,_,_,_), Val).
gen_assoc(Key, t(_,_,_,_,R), Val) :-
	gen_assoc(Key, R, Val).


get_assoc(Key, t(K,V,_,L,R), Val) :-
	compare(Rel, Key, K),
	get_assoc(Rel, Key, V, L, R, Val).

get_assoc(=, _, Val, _, _, Val).
get_assoc(<, Key, _, Tree, _, Val) :-
	get_assoc(Key, Tree, Val).
get_assoc(>, Key, _, _, Tree, Val) :-
	get_assoc(Key, Tree, Val).


get_assoc(Key, t(K,V,B,L,R), Val, t(K,NV,B,NL,NR), NVal) :-
	compare(Rel, Key, K),
	get_assoc(Rel, Key, V, L, R, Val, NV, NL, NR, NVal).

get_assoc(=, _, Val, L, R, Val, NVal, L, R, NVal).
get_assoc(<, Key, V, L, R, Val, V, NL, R, NVal) :-
	get_assoc(Key, L, Val, NL, NVal).
get_assoc(>, Key, V, L, R, Val, V, L, NR, NVal) :-
	get_assoc(Key, R, Val, NR, NVal).


list_to_assoc(List, Assoc) :-
	list_to_assoc(List, t, Assoc).

list_to_assoc([], Assoc, Assoc).
list_to_assoc([Key-Val|List], Assoc0, Assoc) :-
	put_assoc(Key, Assoc0, Val, AssocI),
	list_to_assoc(List, AssocI, Assoc).


ord_list_to_assoc(Keys, Assoc) :-
	list_to_assoc(Keys, Assoc).


%% Ciao begin
% map_assoc(Pred, T) :-
% 	map_assoc_(T, Pred).

% map_assoc_(t, _).
% map_assoc_(t(_,Val,_,L,R), Pred) :-
% 	map_assoc_(L, Pred),
% 	call(Pred, Val),
% 	map_assoc_(R, Pred).


% map_assoc(Pred, T0, T) :-
% 	map_assoc_(T0, Pred, T).

% map_assoc_(t, _, t).
% map_assoc_(t(Key,Val,B,L0,R0), Pred, t(Key,Ans,B,L1,R1)) :-
% 	map_assoc_(L0, Pred, L1),
% 	call(Pred, Val, Ans),
% 	map_assoc_(R0, Pred, R1).
%% Ciao end


max_assoc(t(K,V,_,_,R), Key, Val) :-
	max_assoc(R, K, V, Key, Val).

max_assoc(t, K, V, K, V).
max_assoc(t(K,V,_,_,R), _, _, Key, Val) :-
	max_assoc(R, K, V, Key, Val).


min_assoc(t(K,V,_,L,_), Key, Val) :-
	min_assoc(L, K, V, Key, Val).

min_assoc(t, K, V, K, V).
min_assoc(t(K,V,_,L,_), _, _, Key, Val) :-
	min_assoc(L, K, V, Key, Val).


put_assoc(Key, A0, Value, A) :-
	insert(A0, Key, Value, A, _).

insert(t, Key, Val, t(Key,Val,-,t,t), yes).
insert(t(Key,Val,B,L,R), K, V, NewTree, WhatHasChanged) :-
	compare(Rel, K, Key),
	insert(Rel, t(Key,Val,B,L,R), K, V, NewTree, WhatHasChanged).

insert(=, t(Key,_,B,L,R), _, V, t(Key,V,B,L,R), no).
insert(<, t(Key,Val,B,L,R), K, V, NewTree, WhatHasChanged) :-
	insert(L, K, V, NewL, LeftHasChanged),
	adjust(LeftHasChanged, t(Key,Val,B,NewL,R), left, NewTree, WhatHasChanged).
insert(>, t(Key,Val,B,L,R), K, V, NewTree, WhatHasChanged) :-
	insert(R, K, V, NewR, RightHasChanged),
	adjust(RightHasChanged, t(Key,Val,B,L,NewR), right, NewTree, WhatHasChanged).

adjust(no, Oldree, _, Oldree, no).
adjust(yes, t(Key,Val,B0,L,R), LoR, NewTree, WhatHasChanged) :-
	table(B0, LoR, B1, WhatHasChanged, ToBeRebalanced),
	rebalance(ToBeRebalanced, t(Key,Val,B0,L,R), B1, NewTree).

%     balance  where     balance  whole tree  to be
%     before   inserted  after    increased   rebalanced
table(-      , left    , <      , yes       , no    ) :- !.
table(-      , right   , >      , yes       , no    ) :- !.
table(<      , left    , -      , no        , yes   ) :- !.
table(<      , right   , -      , no        , no    ) :- !.
table(>      , left    , -      , no        , no    ) :- !.
table(>      , right   , -      , no        , yes   ) :- !.

rebalance(no, t(K,V,_,L,R), B, t(K,V,B,L,R)).
rebalance(yes, OldTree, _, NewTree) :-
	avl_geq(OldTree, NewTree).

avl_geq(t(A,VA,>,Alpha,t(B,VB,>,Beta,Gamma)),
	t(B,VB,-,t(A,VA,-,Alpha,Beta),Gamma)) :- !.
avl_geq(t(B,VB,<,t(A,VA,<,Alpha,Beta),Gamma),
	t(A,VA,-,Alpha,t(B,VB,-,Beta,Gamma))) :- !.
avl_geq(t(A,VA,>,Alpha,t(B,VB,<,t(X,VX,B1,Beta,Gamma),Delta)),
	t(X,VX,-,t(A,VA,B2,Alpha,Beta),t(B,VB,B3,Gamma,Delta))) :- !,
	table2(B1, B2, B3).
avl_geq(t(B,VB,<,t(A,VA,>,Alpha,t(X,VX,B1,Beta,Gamma)),Delta),
	t(X,VX,-,t(A,VA,B2,Alpha,Beta),t(B,VB,B3,Gamma,Delta))) :- !,
	table2(B1, B2, B3).

table2(< ,- ,> ).
table2(> ,< ,- ).
table2(- ,- ,- ).


%% Ciao begin
:- pop_prolog_flag( multi_arity_warnings ).
%% Ciao end
