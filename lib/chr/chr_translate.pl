/*  $Id: chr_translate.chr,v 1.56 2006/04/14 11:56:20 toms Exp $

    Part of CHR (Constraint Handling Rules)

    Author:        Tom Schrijvers
    E-mail:        Tom.Schrijvers@cs.kuleuven.be
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2003-2004, K.U. Leuven

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%   ____ _   _ ____     ____                      _ _
%%  / ___| | | |  _ \   / ___|___  _ __ ___  _ __ (_) | ___ _ __
%% | |   | |_| | |_) | | |   / _ \| '_ ` _ \| '_ \| | |/ _ \ '__|
%% | |___|  _  |  _ <  | |__| (_) | | | | | | |_) | | |  __/ |
%%  \____|_| |_|_| \_\  \____\___/|_| |_| |_| .__/|_|_|\___|_|
%%                                          |_|
%%
%% hProlog CHR compiler:
%%
%%	* by Tom Schrijvers, K.U. Leuven, Tom.Schrijvers@cs.kuleuven.be
%%
%%	* based on the SICStus CHR compilation by Christian Holzbaur
%%
%% First working version: 6 June 2003
%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% URGENTLY TODO
%%
%%	* add groundness info to a.i.-based observation analysis
%%	* proper fd/index analysis
%%	* re-add generation checking
%%	* untangle CHR-level and traget source-level generation & optimization
%%	
%% AGGRESSIVE OPTIMISATION IDEAS
%%
%%	* continuation optimization
%%	* analyze history usage to determine whether/when 
%%	  cheaper suspension is possible
%%	* store constraint unconditionally for unconditional propagation rule,
%%	  if first, i.e. without checking history and set trigger cont to next occ
%%	* get rid of suspension passing for never triggered constraints,
%%	   up to allocation occurrence
%%	* get rid of call indirection for never triggered constraints
%%	  up to first allocation occurrence.
%%	* get rid of unnecessary indirection if last active occurrence
%%	  before unconditional removal is head2, e.g.
%%		a \ b <=> true.
%%		a <=> true.
%%	* Eliminate last clause of never stored constraint, if its body
%%	  is fail.
%%	* Specialize lookup operations and indexes for functional dependencies.
%%
%% MORE TODO
%%
%%	* generate code to empty all constraint stores of a module (Bart Demoen)
%%	* map A \ B <=> true | true rules
%%	  onto efficient code that empties the constraint stores of B
%%	  in O(1) time for ground constraints where A and B do not share
%%	  any variables
%%	* ground matching seems to be not optimized for compound terms
%%	  in case of simpagation_head2 and propagation occurrences
%%	* Do not unnecessarily generate store operations.
%%	* analysis for storage delaying (see primes for case)
%%	* internal constraints declaration + analyses?
%%	* Do not store in global variable store if not necessary
%%		NOTE: affects show_store/1
%%	* multi-level store: variable - ground
%%	* Do not maintain/check unnecessary propagation history
%%		for rules that cannot be applied more than once
%%		for reasons of anti-monotony 
%%	* Strengthen storage analysis for propagation rules
%%		reason about bodies of rules only containing constraints
%%		-> fixpoint with observation analysis
%%	* instantiation declarations
%%		POTENTIAL GAIN:
%%			VARIABLE (never bound)
%%			
%%	* make difference between cheap guards		for reordering
%%	                      and non-binding guards	for lock removal
%%	* unqiue -> once/[] transformation for propagation
%%	* cheap guards interleaved with head retrieval + faster
%%	  via-retrieval + non-empty checking for propagation rules
%%	  redo for simpagation_head2 prelude
%%	* intelligent backtracking for simplification/simpagation rule
%%		generator_1(X),'_$savecp'(CP_1),
%%              ... 
%%              if( (
%%			generator_n(Y), 
%%		     	test(X,Y)
%%		    ),
%%		    true,
%%		    ('_$cutto'(CP_1), fail)
%%		),
%%		...
%%
%%	  or recently developped cascading-supported approach 
%%      * intelligent backtracking for propagation rule
%%          use additional boolean argument for each possible smart backtracking
%%          when boolean at end of list true  -> no smart backtracking
%%                                      false -> smart backtracking
%%          only works for rules with at least 3 constraints in the head
%%	* (set semantics + functional dependency) declaration + resolution
%%
%%
%%	* identify cases where prefixes of partner lookups for subsequent occurrences can be
%%	  merged
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%:- module(chr_translate,
%	  [ chr_translate/2		% +Decls, -TranslatedDecls
%	  , type_definition/2
%	  , constraint_type/2
%	  , store_type/2
%	  , constraint_mode/2
%	  , functional_dependency_analysis/1
%	  ]).



%% SICStus begin
%% :- use_module(library(lists),[memberchk/2,is_list/1]).
%% SICStus end


%% for release 4 SICStus begin
%% :- use_module(library(samsort)).
%% for release 4 SICStus end

%% Ciao begin
:- use_module(library(chr/pairlist)).
:- use_module(library(chr/hprolog)).
:- use_module(library(sets)).
:- use_module(library(chr/a_star)).
:- use_module(library(chr/listmap)).
:- use_module(library(chr/clean_code)).
:- use_module(library(chr/builtins)).
:- use_module(library(chr/chr_find)).
%:- use_module(library(chr/guard_entailment)).
%:- use_module(library(chr/chr_compiler_options)).
:- use_module(library(chr/chr_compiler_utility)).
:- use_module(library(chr/chr_compiler_errors)).
:- push_prolog_flag( multi_arity_warnings , off ).
:- include(library(chr/chr_op)).

:- use_module(library(lists),[append/3,reverse/2, length/2, last/2]).
:- use_module(library(write), [write/1]).
:- use_module(library(iso_misc), [once/1]).

:- multifile initial_gv_value/2.
%% Ciao end

:- op(1150, fx, chr_type).
:- op(1130, xfx, --->).
:- op(980, fx, (+)).
:- op(980, fx, (-)).
:- op(980, fx, (?)).
:- op(1150, fx, constraints).
:- op(1150, fx, chr_constraint).

:- chr_option(debug,off).
% :- chr_option(optimize,full).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
:- chr_constraint 
	target_module/1,			% target_module(Module)
	get_target_module/1,

	indexed_argument/2,			% argument instantiation may enable applicability of rule
	is_indexed_argument/2,

	constraint_mode/2,
	get_constraint_mode/2,

	may_trigger/1,
	only_ground_indexed_arguments/1,
	none_suspended_on_variables/0,
	are_none_suspended_on_variables/0,
	
	store_type/2,
	get_store_type/2,
	update_store_type/2,
	actual_store_types/2,
	assumed_store_type/2,
	validate_store_type_assumption/1,

	rule_count/1,
	inc_rule_count/1,

	passive/2,
	is_passive/2,
	any_passive_head/1,

	new_occurrence/3,
	occurrence/4,
	get_occurrence/4,

	max_occurrence/2,
	get_max_occurrence/2,

	allocation_occurrence/2,
	get_allocation_occurrence/2,
	rule/2,
	get_rule/2,
	least_occurrence/2,
	is_least_occurrence/1
	. 

:- chr_option(check_guard_bindings,off).

:- chr_option(mode,target_module(+)).
:- chr_option(mode,indexed_argument(+,+)).
:- chr_option(mode,constraint_mode(+,+)).
:- chr_option(mode,may_trigger(+)).
:- chr_option(mode,store_type(+,+)).
:- chr_option(mode,actual_store_types(+,+)).
:- chr_option(mode,assumed_store_type(+,+)).
:- chr_option(mode,rule_count(+)).
:- chr_option(mode,passive(+,+)).
:- chr_option(mode,occurrence(+,+,+,+)).
:- chr_option(mode,max_occurrence(+,+)).
:- chr_option(mode,allocation_occurrence(+,+)).
:- chr_option(mode,rule(+,+)).
:- chr_option(mode,least_occurrence(+,+)).
:- chr_option(mode,is_least_occurrence(+)).

:- chr_option(type_definition,type(list,[ [], [any|list] ])).
:- chr_option(type_definition,type(constraint,[ any / any ])).

:- chr_option(type_declaration,constraint_mode(constraint,list)).

target_module(_) \ target_module(_) <=> true.
target_module(Mod) \ get_target_module(Query)
	<=> Query = Mod .
get_target_module(Query)
	<=> Query = user.

indexed_argument(FA,I) \ indexed_argument(FA,I) <=> true.
indexed_argument(FA,I) \ is_indexed_argument(FA,I) <=> true.
is_indexed_argument(_,_) <=> fail.

%%% C O N S T R A I N T   M O D E %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

constraint_mode(FA,_) \ constraint_mode(FA,_) <=> true.
constraint_mode(FA,Mode) \ get_constraint_mode(FA,Q) <=>
	Q = Mode.
get_constraint_mode(FA,Q) <=>
	FA = _ / N,
	replicate(N,(?),Q).

%%% M A Y   T R I G G E R %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

may_trigger(FA) <=> \+ has_active_occurrence(FA) | fail.
constraint_mode(FA,Mode), indexed_argument(FA,I) \ may_trigger(FA) <=> 
  nth(I,Mode,M),
  M \== (+) |
  is_stored(FA). 
may_trigger(FA) <=> chr_pp_flag(debugable,on).	% in debug mode, we assume everything can be triggered

constraint_mode(FA,Mode), indexed_argument(FA,I) \ only_ground_indexed_arguments(FA)
	<=>
		nth(I,Mode,M),
		M \== (+)
	|
		fail.
only_ground_indexed_arguments(_) <=>
	true.

none_suspended_on_variables \ none_suspended_on_variables <=> true.
none_suspended_on_variables \ are_none_suspended_on_variables <=> true.
are_none_suspended_on_variables <=> fail.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

store_type(FA,atom_hash(Index)) <=> store_type(FA,multi_hash([Index])).
store_type(FA,Store) \ get_store_type(FA,Query)
	<=> Query = Store.
assumed_store_type(FA,Store) \ get_store_type(FA,Query)
	<=> Query = Store.
get_store_type(_,Query) 
	<=> Query = default.

actual_store_types(C,STs) \ update_store_type(C,ST)
	<=> member(ST,STs) | true.
update_store_type(C,ST), actual_store_types(C,STs)
	<=> 
		actual_store_types(C,[ST|STs]).
update_store_type(C,ST)
	<=> 
		actual_store_types(C,[ST]).

% refine store type assumption
validate_store_type_assumption(C), actual_store_types(C,STs), assumed_store_type(C,_) 	% automatic assumption
	<=> 
		store_type(C,multi_store(STs)).
validate_store_type_assumption(C), actual_store_types(C,STs), store_type(C,_) 		% user assumption
	<=> 
		store_type(C,multi_store(STs)).
validate_store_type_assumption(C), assumed_store_type(C,_)				% no lookups on constraint
	<=> store_type(C,global_ground).
validate_store_type_assumption(C) 
	<=> true.

rule_count(C), inc_rule_count(NC)
	<=> NC is C + 1, rule_count(NC).
inc_rule_count(NC)
	<=> NC = 1, rule_count(NC).

%%% P A S S I V E %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
passive(R,ID) \ passive(R,ID) <=> true.

passive(RuleNb,ID) \ is_passive(RuleNb,ID) <=> true.
is_passive(_,_) <=> fail.

passive(RuleNb,_) \ any_passive_head(RuleNb)
	<=> true.
any_passive_head(_)
	<=> fail.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

max_occurrence(C,N) \ max_occurrence(C,M)
	<=> N >= M | true.

max_occurrence(C,MO), new_occurrence(C,RuleNb,ID) <=>
	NO is MO + 1, 
	occurrence(C,NO,RuleNb,ID), 
	max_occurrence(C,NO).
new_occurrence(C,RuleNb,ID) <=>
	chr_error(internal,'new_occurrence: missing max_occurrence for ~w in rule ~w\n',[C,RuleNb]).

max_occurrence(C,MON) \ get_max_occurrence(C,Q)
	<=> Q = MON.
get_max_occurrence(C,Q)
	<=> chr_error(internal,'get_max_occurrence: missing max occurrence for ~w\n',[C]).

occurrence(C,ON,Rule,ID) \ get_occurrence(C,ON,QRule,QID)
	<=> Rule = QRule, ID = QID.
get_occurrence(C,O,_,_)
	<=> chr_error(internal,'get_occurrence: missing occurrence ~w:~w\n',[]).

% A L L O C C A T I O N   O C C U R R E N C E %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	% cannot store constraint at passive occurrence
occurrence(C,O,RuleNb,ID), passive(RuleNb,ID) \ allocation_occurrence(C,O)
	<=> NO is O + 1, allocation_occurrence(C,NO). 
	% need not store constraint that is removed
rule(RuleNb,Rule), occurrence(C,O,RuleNb,ID) \ allocation_occurrence(C,O)
	<=> Rule = pragma(_,ids(IDs1,_),_,_,_), member(ID,IDs1) 
	| NO is O + 1, allocation_occurrence(C,NO).
	% need not store constraint when body is true
rule(RuleNb,Rule), occurrence(C,O,RuleNb,_) \ allocation_occurrence(C,O)
	<=> Rule = pragma(rule(_,_,_,true),_,_,_,_)
	| NO is O + 1, allocation_occurrence(C,NO).
	% need not store constraint if does not observe itself
rule(RuleNb,Rule), occurrence(C,O,RuleNb,_) \ allocation_occurrence(C,O)
	<=> Rule = pragma(rule([_|_],_,_,_),_,_,_,_), \+ is_observed(C,O)
	| NO is O + 1, allocation_occurrence(C,NO).
	% need not store constraint if does not observe itself and cannot trigger
rule(RuleNb,Rule), occurrence(C,O,RuleNb,_), least_occurrence(RuleNb,[])
	\ allocation_occurrence(C,O)
	<=> Rule = pragma(rule([],Heads,_,_),_,_,_,_), \+ is_observed(C,O)
	| NO is O + 1, allocation_occurrence(C,NO).

rule(RuleNb,Rule), occurrence(C,O,RuleNb,ID), allocation_occurrence(C,AO)
	\ least_occurrence(RuleNb,[ID|IDs]) 
	<=> AO >= O, \+ may_trigger(C) |
	least_occurrence(RuleNb,IDs).
rule(RuleNb,Rule), passive(RuleNb,ID)
	\ least_occurrence(RuleNb,[ID|IDs]) 
	<=> least_occurrence(RuleNb,IDs).

rule(RuleNb,Rule)
	==> Rule = pragma(rule([],_,_,_),ids([],IDs),_,_,_) |
	least_occurrence(RuleNb,IDs).
	
least_occurrence(RuleNb,[]) \ is_least_occurrence(RuleNb) 
	<=> true.
is_least_occurrence(_)
	<=> fail.
	
allocation_occurrence(C,O) \ get_allocation_occurrence(C,Q)
	<=> Q = O.
get_allocation_occurrence(_,Q)
	<=> chr_pp_flag(late_allocation,off), Q=0.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rule(RuleNb,Rule) \ get_rule(RuleNb,Q)
	<=> Q = Rule.
get_rule(_,_)
	<=> fail.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% C O N S T R A I N T   I N D E X %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
:- chr_constraint
	constraint_index/2,			% constraint_index(F/A,DefaultStoreAndAttachedIndex)
	get_constraint_index/2,			
	get_indexed_constraint/2,
	max_constraint_index/1,			% max_constraint_index(MaxDefaultStoreAndAttachedIndex)
	get_max_constraint_index/1.

:- chr_option(mode,constraint_index(+,+)).
:- chr_option(mode,max_constraint_index(+)).

constraint_index(C,Index) \ get_constraint_index(C,Query)
	<=> Query = Index.
get_constraint_index(C,Query)
	<=> fail.

constraint_index(C,Index) \ get_indexed_constraint(Index,Q)
	<=> Q = C.
get_indexed_constraint(Index,Q)
	<=> fail.

max_constraint_index(Index) \ get_max_constraint_index(Query)
	<=> Query = Index.
get_max_constraint_index(Query)
	<=> Query = 0.

set_constraint_indices(Constraints) :-
	set_constraint_indices(Constraints,1).
set_constraint_indices([],M) :-
	N is M - 1,
	max_constraint_index(N).
set_constraint_indices([C|Cs],N) :-
	( ( chr_pp_flag(debugable, on) ; \+ only_ground_indexed_arguments(C), is_stored(C) ;  is_stored(C), get_store_type(C,default)) ->
		constraint_index(C,N),
		M is N + 1,
		set_constraint_indices(Cs,M)
	;
		set_constraint_indices(Cs,N)
	).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Translation

chr_translate(Declarations,NewDeclarations) :-
	chr_info(banner,'\tThe K.U.Leuven CHR System\t\n\t\tContributors:\tTom Schrijvers, Jon Sneyers, Bart Demoen,\n\t\t\t\tJan Wielemaker\n\t\tCopyright:\tK.U.Leuven, Belgium\n\t\tURL:\t\thttp://www.cs.kuleuven.be/~~toms/CHR/\n',[]),
	init_chr_pp_flags,
	partition_clauses(Declarations,Constraints0,Rules0,OtherClauses),
	check_declared_constraints(Constraints0),
	generate_show_constraint(Constraints0,Constraints,Rules0,Rules),
	add_constraints(Constraints),
	add_rules(Rules),
	% start analysis
	check_rules(Rules,Constraints),
	add_occurrences(Rules),
	time(fd_analysis,functional_dependency_analysis(Rules)),
	time(set_semantics_rules,set_semantics_rules(Rules)),
	time(symmetry_analysis,symmetry_analysis(Rules)),
%	time(guard_simplification,guard_simplification),
	time(storage_analysis,storage_analysis(Constraints)),
	time(observation_analysis,observation_analysis(Constraints)),
	time(ai_observation_analysis,ai_observation_analysis(Constraints)),
	time(late_allocation_analysis,late_allocation_analysis(Constraints)),
	time(assume_constraint_stores,assume_constraint_stores(Constraints)),
	time(set_constraint_indices,set_constraint_indices(Constraints)),
	% end analysis
	time(constraints_code,constraints_code(Constraints,ConstraintClauses)),
	time(validate_store_type_assumptions,validate_store_type_assumptions(Constraints)),
	phase_end(validate_store_type_assumptions),
	time(store_management_preds,store_management_preds(Constraints,StoreClauses)),	% depends on actual code used
	insert_declarations(OtherClauses, Clauses0),
%	chr_module_declaration(CHRModuleDeclaration),
	append([Clauses0,
		StoreClauses,
		ConstraintClauses,
%		CHRModuleDeclaration,
		[end_of_file]
	       ],
	       NewDeclarations).

store_management_preds(Constraints,Clauses) :-
		generate_attach_detach_a_constraint_all(Constraints,AttachAConstraintClauses),
		% generate_indexed_variables_clauses(Constraints,IndexedClauses),
		generate_attach_increment(AttachIncrementClauses),
		generate_attr_unify_hook(AttrUnifyHookClauses),
		generate_extra_clauses(Constraints,ExtraClauses),
		generate_insert_delete_constraints(Constraints,DeleteClauses),
		generate_attach_code(Constraints,StoreClauses),
		generate_counter_code(CounterClauses),
		append([AttachAConstraintClauses
		       ,IndexedClauses
		       ,AttachIncrementClauses
		       ,AttrUnifyHookClauses
		       ,ExtraClauses
		       ,DeleteClauses
		       ,StoreClauses
		       ,CounterClauses
		       ]
		      ,Clauses).

%% SWI begin
% extra_declaration([ :- use_module(chr(chr_runtime))
% 		  , :- use_module(chr(chr_hashtable_store))
% 		  , :- use_module(chr(chr_integertable_store))
% 		  , :- use_module(library(clp/clp_events))
% 		  ]).

extra_declaration( [] ).
%% SWI end

%% SICStus begin
%% extra_declaration([(:- use_module(library(chr/hprolog),[term_variables/3]))]).
%% SICStus end



insert_declarations(Clauses0, Clauses) :-
	extra_declaration(Decls),
	append(Clauses0, Decls, Clauses).

generate_counter_code(Clauses) :-
	( chr_pp_flag(store_counter,on) ->
		Clauses = [
			('$counter_init'(N1) :- nb_setval(N1,0)) ,
			('$counter'(N2,X1) :- nb_getval(N2,X1)),
			('$counter_inc'(N) :- nb_getval(N,X), Y is X + 1, nb_setval(N,Y)),
			(:- '$counter_init'('$insert_counter')),
			(:- '$counter_init'('$delete_counter')),
			('$insert_counter_inc' :- '$counter_inc'('$insert_counter')),
			('$delete_counter_inc' :- '$counter_inc'('$delete_counter')),
			( counter_stats(I,D) :- '$counter'('$insert_counter',I),'$counter'('$delete_counter',D))
		]
	;
		Clauses = []
	).

% for systems with multifile declaration
chr_module_declaration(CHRModuleDeclaration) :-
	get_target_module(Mod),
	( Mod \== chr_translate, chr_pp_flag(toplevel_show_store,on) ->
		CHRModuleDeclaration = [
			(:- multifile chr:'$chr_module'/1),
			chr:'$chr_module'(Mod)	
		]
	;
		CHRModuleDeclaration = []
	).	


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Partitioning of clauses into constraint declarations, chr rules and other 
%% clauses

partition_clauses([],[],[],[]).
partition_clauses([C|Cs],Ds,Rs,OCs) :-
  (   parse_rule(C,R) ->
      Ds = RDs,
      Rs = [R | RRs], 
      OCs = ROCs
  ;   is_declaration(C,D) ->
      append(D,RDs,Ds),
      Rs = RRs,
      OCs = ROCs
  ;   is_module_declaration(C,Mod) ->
      target_module(Mod),
      Ds = RDs,
      Rs = RRs,
      OCs = [C|ROCs]
  ;   is_type_definition(C) ->
      Ds = RDs,
      Rs = RRs,
      OCs = ROCs
  ;   C = (handler _) ->
      chr_warning(deprecated(C),'Backward compatibility: ignoring handler/1 declaration.\n',[]),
      Ds = RDs,
      Rs = RRs,
      OCs = ROCs
  ;   C = (rules _) ->
      chr_warning(deprecated(C),'Backward compatibility: ignoring rules/1 declaration.\n',[]),
      Ds = RDs,
      Rs = RRs,
      OCs = ROCs
  ;   C = option(OptionName,OptionValue) ->
      chr_warning(deprecated(C),'Instead use :- chr_option(~w,~w).\n',[OptionName,OptionValue]),
      handle_option(OptionName,OptionValue),
      Ds = RDs,
      Rs = RRs,
      OCs = ROCs
  ;   C = (:- chr_option(OptionName,OptionValue)) ->
      handle_option(OptionName,OptionValue),
      Ds = RDs,
      Rs = RRs,
      OCs = ROCs
  ;   Ds = RDs,
      Rs = RRs,
      OCs = [C|ROCs]
  ),
  partition_clauses(Cs,RDs,RRs,ROCs).

is_declaration(D, Constraints) :-		%% constraint declaration
	( D = (:- Decl), Decl =.. [F,Cs], F == (chr_constraint) ->
  		conj2list(Cs,Constraints0)
	;
		( D = (:- Decl) ->
			Decl =.. [constraints,Cs]
		;
			D =.. [constraints,Cs]
		),
  		conj2list(Cs,Constraints0),
		chr_warning(deprecated(D),'Instead use :- chr_constraint ~w.\n',[Cs])
	),
	extract_type_mode(Constraints0,Constraints).

extract_type_mode([],[]).
extract_type_mode([F/A|R],[F/A|R2]) :- !,extract_type_mode(R,R2).
extract_type_mode([C|R],[C2|R2]) :- 
	functor(C,F,A),C2=F/A,
	C =.. [_|Args],
	extract_types_and_modes(Args,ArgTypes,ArgModes),
	constraint_type(F/A,ArgTypes),
	constraint_mode(F/A,ArgModes),
	extract_type_mode(R,R2).

extract_types_and_modes([],[],[]).
extract_types_and_modes([+(T)|R],[T|R2],[(+)|R3]) :- !,extract_types_and_modes(R,R2,R3).
extract_types_and_modes([?(T)|R],[T|R2],[(?)|R3]) :- !,extract_types_and_modes(R,R2,R3).
extract_types_and_modes([-(T)|R],[T|R2],[(?)|R3]) :- !,extract_types_and_modes(R,R2,R3).
extract_types_and_modes([(+)|R],[any|R2],[(+)|R3]) :- !,extract_types_and_modes(R,R2,R3).
extract_types_and_modes([(?)|R],[any|R2],[(?)|R3]) :- !,extract_types_and_modes(R,R2,R3).
extract_types_and_modes([(-)|R],[any|R2],[(?)|R3]) :- !,extract_types_and_modes(R,R2,R3).
extract_types_and_modes([Illegal|R],_,_) :- 
    chr_error(syntax(Illegal),'Illegal mode/type declaration.\n\tCorrect syntax is +type, -type or ?type\n\tor +, - or ?.\n',[]).

is_type_definition(D) :-
  ( D = (:- TDef) ->
	true
  ;
	D = TDef
  ),
  TDef =.. [chr_type,TypeDef],
  ( TypeDef = (Name ---> Def) ->
	tdisj2list(Def,DefList),
  	type_definition(Name,DefList)
  ;
	( TypeDef = (Alias == Name) ->
  	    type_alias(Alias,Name)
  	;
	    chr_warning(syntax,'Illegal type definition "~w".\n\tIgnoring this malformed type definition.\n',[TypeDef])
	)
  ).

% no removal of fails, e.g. :- type bool --->  true ; fail.
tdisj2list(Conj,L) :-
  tdisj2list(Conj,L,[]).
tdisj2list(Conj,L,T) :-
  Conj = (G1;G2), !,
  tdisj2list(G1,L,T1),
  tdisj2list(G2,T1,T).
tdisj2list(G,[G | T],T).


%% Data Declaration
%%
%% pragma_rule 
%%	-> pragma(
%%		rule,
%%		ids,
%%		list(pragma),
%%		yesno(string),		:: maybe rule nane
%%		int			:: rule number
%%		)
%%
%% ids	-> ids(
%%		list(int),
%%		list(int)
%%		)
%%		
%% rule -> rule(
%%		list(constraint),	:: constraints to be removed
%%		list(constraint),	:: surviving constraints
%%		goal,			:: guard
%%		goal			:: body
%%	 	)

parse_rule(RI,R) :-				%% name @ rule
	RI = (Name @ RI2), !,
	rule(RI2,yes(Name),R).
parse_rule(RI,R) :-
	rule(RI,no,R).

rule(RI,Name,R) :-
	RI = (RI2 pragma P), !,			%% pragmas
	( var(P) ->
		Ps = [_]			% intercept variable
	;
		conj2list(P,Ps)
	),
	inc_rule_count(RuleCount),
	R = pragma(R1,IDs,Ps,Name,RuleCount),
	is_rule(RI2,R1,IDs,R).
rule(RI,Name,R) :-
	inc_rule_count(RuleCount),
	R = pragma(R1,IDs,[],Name,RuleCount),
	is_rule(RI,R1,IDs,R).


is_rule(RI,R,IDs,RC) :-				%% propagation rule
   RI = (H ==> B), !,
   conj2list(H,Head2i),
   get_ids(Head2i,IDs2,Head2,RC),
   IDs = ids([],IDs2),
   (   B = (G | RB) ->
       R = rule([],Head2,G,RB)
   ;
       R = rule([],Head2,true,B)
   ).
is_rule(RI,R,IDs,RC) :-				%% simplification/simpagation rule
   RI = (H <=> B), !,
   (   B = (G | RB) ->
       Guard = G,
       Body  = RB
   ;   Guard = true,
       Body = B
   ),
   (   H = (H1 \ H2) ->
       conj2list(H1,Head2i),
       conj2list(H2,Head1i),
       get_ids(Head2i,IDs2,Head2,0,N,RC),
       get_ids(Head1i,IDs1,Head1,N,_,RC),
       IDs = ids(IDs1,IDs2)
   ;   conj2list(H,Head1i),
       Head2 = [],
       get_ids(Head1i,IDs1,Head1,RC),
       IDs = ids(IDs1,[])
   ),
   R = rule(Head1,Head2,Guard,Body).

get_ids(Cs,IDs,NCs,RC) :-
	get_ids(Cs,IDs,NCs,0,_,RC).

get_ids([],[],[],N,N,_).
get_ids([C|Cs],[N|IDs],[NC|NCs],N,NN,RC) :-
	( C = (NC # N1) ->
		(var(N1) ->
			N1 = N
		;
			check_direct_pragma(N1,N,RC)
		)
	;	
		NC = C
	),
	M is N + 1,
	get_ids(Cs,IDs,NCs, M,NN,RC).

direct_pragma(passive).
check_direct_pragma(passive,N,R) :- 
	R = pragma(_,ids(IDs1,IDs2),_,_,RuleNb), passive(RuleNb,N).
check_direct_pragma(Abbrev,N,RC) :- 
	(direct_pragma(X),
	 atom_concat(Abbrev,Remainder,X) ->
	    chr_warning(problem_pragma(Abbrev,RC),'completed "~w" to "~w"\n',[Abbrev,X])
	;
	    chr_warning(unsupported_pragma(Abbrev,RC),'',[])
	).


is_module_declaration((:- module(Mod)),Mod).
is_module_declaration((:- module(Mod,_)),Mod).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Add constraints
add_constraints([]).
add_constraints([C|Cs]) :-
	max_occurrence(C,0),
	C = _/A,
	length(Mode,A), 
	set_elems(Mode,?),
	constraint_mode(C,Mode),
	add_constraints(Cs).

% Add rules
add_rules([]).
add_rules([Rule|Rules]) :-
	Rule = pragma(_,_,_,_,RuleNb),
	rule(RuleNb,Rule),
	add_rules(Rules).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Some input verification:

check_declared_constraints(Constraints) :-
	check_declared_constraints(Constraints,[]).

check_declared_constraints([],_).
check_declared_constraints([C|Cs],Acc) :-
	( memberchk_eq(C,Acc) ->
		chr_error(syntax(C),'Constraint ~w multiply defined.\n\tRemove redundant declaration!\n',[C])
	;
		true
	),
	check_declared_constraints(Cs,[C|Acc]).

%%  - all constraints in heads are declared constraints
%%  - all passive pragmas refer to actual head constraints

check_rules([],_).
check_rules([PragmaRule|Rest],Decls) :-
	check_rule(PragmaRule,Decls),
	check_rules(Rest,Decls).

check_rule(PragmaRule,Decls) :-
	check_rule_indexing(PragmaRule),
	PragmaRule = pragma(Rule,_IDs,Pragmas,_Name,_N),
	Rule = rule(H1,H2,_,_),
	append(H1,H2,HeadConstraints),
	check_head_constraints(HeadConstraints,Decls,PragmaRule),
	check_pragmas(Pragmas,PragmaRule).

check_head_constraints([],_,_).
check_head_constraints([Constr|Rest],Decls,PragmaRule) :-
	functor(Constr,F,A),
	( member(F/A,Decls) ->
		check_head_constraints(Rest,Decls,PragmaRule)
	;
		chr_error(syntax(Constr),'Undeclared constraint ~w in head of ~@.\n\tConstraint should be one of ~w.\n', [F/A,format_rule(PragmaRule),Decls])	).

check_pragmas([],_).
check_pragmas([Pragma|Pragmas],PragmaRule) :-
	check_pragma(Pragma,PragmaRule),
	check_pragmas(Pragmas,PragmaRule).

check_pragma(Pragma,PragmaRule) :-
	var(Pragma), !,
	chr_error(syntax(Pragma),'Invalid pragma ~w in ~@.\n\tPragma should not be a variable!\n',[Pragma,format_rule(PragmaRule)]).
check_pragma(passive(ID), PragmaRule) :-
	!,
	PragmaRule = pragma(_,ids(IDs1,IDs2),_,_,RuleNb),
	( memberchk_eq(ID,IDs1) ->
		true
	; memberchk_eq(ID,IDs2) ->
		true
	;
		chr_error(syntax(ID),'Invalid identifier ~w in pragma passive in ~@.\n', [ID,format_rule(PragmaRule)])
	),
	passive(RuleNb,ID).

check_pragma(Pragma, PragmaRule) :-
	Pragma = already_in_heads,
	!,
	chr_warning(unsupported_pragma(Pragma,PragmaRule),'Termination and correctness may be affected.\n',[]).

check_pragma(Pragma, PragmaRule) :-
	Pragma = already_in_head(_),
	!,
	chr_warning(unsupported_pragma(Pragma,PragmaRule),'Termination and correctness may be affected.\n',[]).
	
check_pragma(Pragma, PragmaRule) :-
	Pragma = no_history,
	!,
	chr_warning(experimental,'Experimental pragma no_history. Use with care!\n',[]),
	PragmaRule = pragma(_,_,_,_,N),
	no_history(N).

check_pragma(Pragma,PragmaRule) :-
	chr_error(syntax(Pragma),'Invalid pragma ~w in ~@.\n', [Pragma,format_rule(PragmaRule)]).

:- chr_constraint
	no_history/1,
	has_no_history/1.

:- chr_option(mode,no_history(+)).

no_history(RuleNb) \ has_no_history(RuleNb) <=> true.
has_no_history(_) <=> fail.

format_rule(PragmaRule) :-
	PragmaRule = pragma(_,_,_,MaybeName,N),
	( MaybeName = yes(Name) ->
		write('rule '), write(Name)
	;
		write('rule number '), write(N)
	).

check_rule_indexing(PragmaRule) :-
	PragmaRule = pragma(Rule,_,_,_,_),
	Rule = rule(H1,H2,G,_),
	term_variables(H1-H2,HeadVars),
	remove_anti_monotonic_guards(G,HeadVars,NG),
	check_indexing(H1,NG-H2),
	check_indexing(H2,NG-H1),
	% EXPERIMENT
	( chr_pp_flag(term_indexing,on) -> 
		term_variables(NG,GuardVariables),
		append(H1,H2,Heads),
		check_specs_indexing(Heads,GuardVariables,Specs)
	;
		true
	).

:- chr_constraint
	indexing_spec/2,
	get_indexing_spec/2.

:- chr_option(mode,indexing_spec(+,+)).

indexing_spec(FA,Spec) \ get_indexing_spec(FA,R) <=> R = Spec.
get_indexing_spec(_,Spec) <=> Spec = [].

indexing_spec(FA,Specs1), indexing_spec(FA,Specs2)
	<=>
		append(Specs1,Specs2,Specs),
		indexing_spec(FA,Specs).

remove_anti_monotonic_guards(G,Vars,NG) :-
	conj2list(G,GL),
	remove_anti_monotonic_guard_list(GL,Vars,NGL),
	list2conj(NGL,NG).

remove_anti_monotonic_guard_list([],_,[]).
remove_anti_monotonic_guard_list([G|Gs],Vars,NGs) :-
	( G = var(X), memberchk_eq(X,Vars) ->
		NGs = RGs
	; G = functor(Term,Functor,Arity),			% isotonic
	  \+ memberchk_eq(Functor,Vars), \+ memberchk_eq(Arity,Vars) ->
		NGs = RGs
	;
		NGs = [G|RGs]
	),
	remove_anti_monotonic_guard_list(Gs,Vars,RGs).

check_indexing([],_).
check_indexing([Head|Heads],Other) :-
	functor(Head,F,A),
	Head =.. [_|Args],
	term_variables(Heads-Other,OtherVars),
	check_indexing(Args,1,F/A,OtherVars),
	check_indexing(Heads,[Head|Other]).	

check_indexing([],_,_,_).
check_indexing([Arg|Args],I,FA,OtherVars) :-
	( is_indexed_argument(FA,I) ->
		true
	; nonvar(Arg) ->
		indexed_argument(FA,I)
	; % var(Arg) ->
		term_variables(Args,ArgsVars),
		append(ArgsVars,OtherVars,RestVars),
		( memberchk_eq(Arg,RestVars) ->
			indexed_argument(FA,I)
		;
			true
		)
	),
	J is I + 1,
	term_variables(Arg,NVars),
	append(NVars,OtherVars,NOtherVars),
	check_indexing(Args,J,FA,NOtherVars).	

check_specs_indexing([],_,[]).
check_specs_indexing([Head|Heads],Variables,Specs) :-
	Specs = [Spec|RSpecs],
	term_variables(Heads,OtherVariables,Variables),
	check_spec_indexing(Head,OtherVariables,Spec),
	term_variables(Head,NVariables,Variables),
	check_specs_indexing(Heads,NVariables,RSpecs).

check_spec_indexing(Head,OtherVariables,Spec) :-
	functor(Head,F,A),
	Spec = spec(F,A,ArgSpecs),
	Head =.. [_|Args],
	check_args_spec_indexing(Args,1,OtherVariables,ArgSpecs),
	indexing_spec(F/A,[ArgSpecs]).

check_args_spec_indexing([],_,_,[]).
check_args_spec_indexing([Arg|Args],I,OtherVariables,ArgSpecs) :-
	term_variables(Args,Variables,OtherVariables),
	( check_arg_spec_indexing(Arg,I,Variables,ArgSpec) ->
		ArgSpecs = [ArgSpec|RArgSpecs]
	;
		ArgSpecs = RArgSpecs
	),
	J is I + 1,
	term_variables(Arg,NOtherVariables,OtherVariables),
	check_args_spec_indexing(Args,J,NOtherVariables,RArgSpecs).

check_arg_spec_indexing(Arg,I,Variables,ArgSpec) :-
	( var(Arg) ->
		memberchk_eq(Arg,Variables),
		ArgSpec = specinfo(I,any,[])
	;
		functor(Arg,F,A),
		ArgSpec = specinfo(I,F/A,[ArgSpecs]),
		Arg =.. [_|Args],
		check_args_spec_indexing(Args,1,Variables,ArgSpecs)
	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Occurrences

add_occurrences([]).
add_occurrences([Rule|Rules]) :-
	Rule = pragma(rule(H1,H2,_,_),ids(IDs1,IDs2),_,_,Nb),
	add_occurrences(H1,IDs1,Nb),
	add_occurrences(H2,IDs2,Nb),
	add_occurrences(Rules).

add_occurrences([],[],_).
add_occurrences([H|Hs],[ID|IDs],RuleNb) :-
	functor(H,F,A),
	FA = F/A,
	new_occurrence(FA,RuleNb,ID),
	add_occurrences(Hs,IDs,RuleNb).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Observation Analysis
%
% CLASSIFICATION
%   Legacy
%
%  - approximative: should make decision in late allocation analysis per body
%  TODO:
%    remove

is_observed(C,O) :-
	is_self_observer(C),
	ai_is_observed(C,O).

:- chr_constraint
	observes/2,
	spawns_observer/2,
	observes_indirectly/2,
	is_self_observer/1
	.

:- chr_option(mode,observes(+,+)).
:- chr_option(mode,spawns_observer(+,+)).
:- chr_option(mode,observes_indirectly(+,+)).

spawns_observer(C1,C2) \ spawns_observer(C1,C2) <=> true.
observes(C1,C2) \ observes(C1,C2) <=> true.

observes_indirectly(C1,C2) \ observes_indirectly(C1,C2) <=> true.

spawns_observer(C1,C2), observes(C2,C3) ==> observes_indirectly(C1,C3).
spawns_observer(C1,C2), observes_indirectly(C2,C3) ==> observes_indirectly(C1,C3).

observes_indirectly(C,C) \ is_self_observer(C) <=>  true.
is_self_observer(_) <=> chr_pp_flag(observation_analysis,off). 
	% true if analysis has not been run,
	% false if analysis has been run

observation_analysis(Cs) :-
    ( chr_pp_flag(observation_analysis,on) ->
	observation_analysis(Cs,Cs)
    ;
	true
    ).

observation_analysis([],_).
observation_analysis([C|Cs],Constraints) :-
	get_max_occurrence(C,MO),
	observation_analysis_occurrences(C,1,MO,Constraints),
	observation_analysis(Cs,Constraints).

observation_analysis_occurrences(C,O,MO,Cs) :-
	( O > MO ->
		true
	;
		observation_analysis_occurrence(C,O,Cs),
		NO is O + 1,
		observation_analysis_occurrences(C,NO,MO,Cs)
	).

observation_analysis_occurrence(C,O,Cs) :-
	get_occurrence(C,O,RuleNb,ID),
	( is_passive(RuleNb,ID) ->
		true
	;
		get_rule(RuleNb,PragmaRule),
		PragmaRule = pragma(rule(Heads1,Heads2,_,Body),ids(IDs1,IDs2),_,_,_),	
		( select2(ID,_Head,IDs1,Heads1,_RIDs1,RHeads1) ->
			append(RHeads1,Heads2,OtherHeads)
		; select2(ID,_Head,IDs2,Heads2,_RIDs2,RHeads2) ->
			append(RHeads2,Heads1,OtherHeads)
		),
		observe_heads(C,OtherHeads),
		observe_body(C,Body,Cs)	
	).

observe_heads(C,Heads) :-
	findall(F/A,(member(H,Heads),functor(H,F,A)),Cs),
	observe_all(C,Cs).

observe_all(C,Cs) :-
	( Cs = [C1|Cr] ->
		observes(C,C1),
		observe_all(C,Cr)
	;
		true
	).

spawn_all(C,Cs) :-
	( Cs = [C1|Cr] ->
		spawns_observer(C,C1),
		spawn_all(C,Cr)
	;
		true
	).
spawn_all_triggers(C,Cs) :-
	( Cs = [C1|Cr] ->
		( may_trigger(C1) ->
			spawns_observer(C,C1)
		;
			true
		),
		spawn_all_triggers(C,Cr)
	;
		true
	).

observe_body(C,Body,Cs) :-
	( var(Body) ->
		spawn_all(C,Cs)
	; Body = true ->
		true
	; Body = fail ->
		true
	; Body = (B1,B2) ->
		observe_body(C,B1,Cs),
		observe_body(C,B2,Cs)
	; Body = (B1;B2) ->
		observe_body(C,B1,Cs),
		observe_body(C,B2,Cs)
	; Body = (B1->B2) ->
		observe_body(C,B1,Cs),
		observe_body(C,B2,Cs)
	; functor(Body,F,A), member(F/A,Cs) ->
		spawns_observer(C,F/A)
	; Body = (_ = _) ->
		spawn_all_triggers(C,Cs)
	; Body = (_ is _) ->
		spawn_all_triggers(C,Cs)
	; binds_b(Body,Vars) ->
		(  Vars == [] ->
			true
		;
			spawn_all_triggers(C,Cs)
		)
	;
		spawn_all(C,Cs)
	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Late allocation

late_allocation_analysis(Cs) :-
	( chr_pp_flag(late_allocation,on) ->
		late_allocation(Cs)
	;
		true
	).

late_allocation([]).
late_allocation([C|Cs]) :-
	allocation_occurrence(C,1),
	late_allocation(Cs).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Generated predicates
%%	attach_$CONSTRAINT
%%	attach_increment
%%	detach_$CONSTRAINT
%%	attr_unify_hook

%%	attach_$CONSTRAINT
generate_attach_detach_a_constraint_all([],[]).
generate_attach_detach_a_constraint_all([Constraint|Constraints],Clauses) :-
	( ( chr_pp_flag(debugable,on) ; is_stored(Constraint), \+ only_ground_indexed_arguments(Constraint)) ->
		generate_attach_a_constraint(Constraint,Clauses1),
		generate_detach_a_constraint(Constraint,Clauses2)
	;
		Clauses1 = [],
		Clauses2 = []
	),	
	generate_attach_detach_a_constraint_all(Constraints,Clauses3),
	append([Clauses1,Clauses2,Clauses3],Clauses).

generate_attach_a_constraint(Constraint,[Clause1,Clause2]) :-
	generate_attach_a_constraint_empty_list(Constraint,Clause1),
	get_max_constraint_index(N),
	( N == 1 ->
		generate_attach_a_constraint_1_1(Constraint,Clause2)
	;
		generate_attach_a_constraint_t_p(Constraint,Clause2)
	).

generate_attach_a_constraint_skeleton(FA,Args,Body,Clause) :-
	make_name('attach_',FA,Fct),
	Head =.. [Fct | Args],
	Clause = ( Head :- Body).

generate_attach_a_constraint_empty_list(FA,Clause) :-
	generate_attach_a_constraint_skeleton(FA,[[],_],true,Clause).

generate_attach_a_constraint_1_1(FA,Clause) :-
	Args = [[Var|Vars],Susp],
	generate_attach_a_constraint_skeleton(FA,Args,Body,Clause),
	generate_attach_body_1(FA,Var,Susp,AttachBody),
	make_name('attach_',FA,Fct),
	RecursiveCall =.. [Fct,Vars,Susp],
	% SWI-Prolog specific code
	chr_pp_flag(solver_events,NMod),
	( NMod \== none ->
		Args = [[Var|_],Susp],
		get_target_module(Mod),
		use_auxiliary_predicate(run_suspensions),
		Subscribe = clp_events:subscribe(Var,NMod,Mod,'$run_suspensions'([Susp]))
	;
		Subscribe = true
	),
	Body =
	(
		AttachBody,
		Subscribe,
		RecursiveCall
	).

generate_attach_body_1(FA,Var,Susp,Body) :-
	get_target_module(Mod),
	Body =
	(   get_attr(Var, Mod, Susps) ->
            NewSusps=[Susp|Susps],
            put_attr(Var, Mod, NewSusps)
        ;   
            put_attr(Var, Mod, [Susp])
	).

generate_attach_a_constraint_t_p(FA,Clause) :-
	Args = [[Var|Vars],Susp],
	generate_attach_a_constraint_skeleton(FA,Args,Body,Clause),
	make_name('attach_',FA,Fct),
	RecursiveCall =.. [Fct,Vars,Susp],
	generate_attach_body_n(FA,Var,Susp,AttachBody),
	% SWI-Prolog specific code
	chr_pp_flag(solver_events,NMod),
	( NMod \== none ->
		Args = [[Var|_],Susp],
		get_target_module(Mod),
		use_auxiliary_predicate(run_suspensions),
		Subscribe = clp_events:subscribe(Var,NMod,Mod,'$run_suspensions'([Susp]))
	;
		Subscribe = true
	),
	Body =
	(
		AttachBody,
		Subscribe,
		RecursiveCall
	).

generate_attach_body_n(F/A,Var,Susp,Body) :-
	get_constraint_index(F/A,Position),
	or_pattern(Position,Pattern),
	get_max_constraint_index(Total),
	make_attr(Total,Mask,SuspsList,Attr),
	nth(Position,SuspsList,Susps),
	substitute(Susps,SuspsList,[Susp|Susps],SuspsList1),
	make_attr(Total,Mask,SuspsList1,NewAttr1),
	substitute(Susps,SuspsList,[Susp],SuspsList2),
	make_attr(Total,NewMask,SuspsList2,NewAttr2),
	copy_term_nat(SuspsList,SuspsList3),
	nth(Position,SuspsList3,[Susp]),
	chr_delete(SuspsList3,[Susp],RestSuspsList),
	set_elems(RestSuspsList,[]),
	make_attr(Total,Pattern,SuspsList3,NewAttr3),
	get_target_module(Mod),
	Body =
	( get_attr(Var,Mod,TAttr) ->
		TAttr = Attr,
		( Mask /\ Pattern =:= Pattern ->
			put_attr(Var, Mod, NewAttr1)
		;
			NewMask is Mask \/ Pattern,
			put_attr(Var, Mod, NewAttr2)
		)
	;
		put_attr(Var,Mod,NewAttr3)
	).

%%	detach_$CONSTRAINT
generate_detach_a_constraint(Constraint,[Clause1,Clause2]) :-
	generate_detach_a_constraint_empty_list(Constraint,Clause1),
	get_max_constraint_index(N),
	( N == 1 ->
		generate_detach_a_constraint_1_1(Constraint,Clause2)
	;
		generate_detach_a_constraint_t_p(Constraint,Clause2)
	).

generate_detach_a_constraint_empty_list(FA,Clause) :-
	make_name('detach_',FA,Fct),
	Args = [[],_],
	Head =.. [Fct | Args],
	Clause = ( Head :- true).

generate_detach_a_constraint_1_1(FA,Clause) :-
	make_name('detach_',FA,Fct),
	Args = [[Var|Vars],Susp],
	Head =.. [Fct | Args],
	RecursiveCall =.. [Fct,Vars,Susp],
	generate_detach_body_1(FA,Var,Susp,DetachBody),
	Body =
	(
		DetachBody,
		RecursiveCall
	),
	Clause = (Head :- Body).

generate_detach_body_1(FA,Var,Susp,Body) :-
	get_target_module(Mod),
	Body =
	( get_attr(Var,Mod,Susps) ->
		'chr sbag_del_element'(Susps,Susp,NewSusps),
		( NewSusps == [] ->
			del_attr(Var,Mod)
		;
			put_attr(Var,Mod,NewSusps)
		)
	;
		true
	).

generate_detach_a_constraint_t_p(FA,Clause) :-
	make_name('detach_',FA,Fct),
	Args = [[Var|Vars],Susp],
	Head =.. [Fct | Args],
	RecursiveCall =.. [Fct,Vars,Susp],
	generate_detach_body_n(FA,Var,Susp,DetachBody),
	Body =
	(
		DetachBody,
		RecursiveCall
	),
	Clause = (Head :- Body).

generate_detach_body_n(F/A,Var,Susp,Body) :-
	get_constraint_index(F/A,Position),
	or_pattern(Position,Pattern),
	and_pattern(Position,DelPattern),
	get_max_constraint_index(Total),
	make_attr(Total,Mask,SuspsList,Attr),
	nth(Position,SuspsList,Susps),
	substitute(Susps,SuspsList,[],SuspsList1),
	make_attr(Total,NewMask,SuspsList1,Attr1),
	substitute(Susps,SuspsList,NewSusps,SuspsList2),
	make_attr(Total,Mask,SuspsList2,Attr2),
	get_target_module(Mod),
	Body =
	( get_attr(Var,Mod,TAttr) ->
		TAttr = Attr,
		( Mask /\ Pattern =:= Pattern ->
			'chr sbag_del_element'(Susps,Susp,NewSusps),
			( NewSusps == [] ->
				NewMask is Mask /\ DelPattern,
				( NewMask == 0 ->
					del_attr(Var,Mod)
				;
					put_attr(Var,Mod,Attr1)
				)
			;
				put_attr(Var,Mod,Attr2)
			)
		;
			true
		)
	;
		true
	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%generate_indexed_variables_clauses(Constraints,Clauses) :-
%	( is_used_auxiliary_predicate(chr_indexed_variables) ->
%		generate_indexed_variables_clauses_(Constraints,Clauses)
%	;
%		Clauses = []
%	).
%
%generate_indexed_variables_clauses_([],[]).
%generate_indexed_variables_clauses_([C|Cs],Clauses) :-
%	( is_stored(C) ->
%		Clauses = [Clause|RestClauses],
%		generate_indexed_variables_clause(C,Clause)
%	;
%		Clauses = RestClauses
%	),
%	generate_indexed_variables_clauses_(Cs,RestClauses).
%
%%===============================================================================
%:- chr_constraint generate_indexed_variables_clause/2.
%:- chr_option(mode,generate_indexed_variables_clause(+,+)).
%%-------------------------------------------------------------------------------
%constraint_mode(F/A,ArgModes) \ generate_indexed_variables_clause(F/A,Clause) <=>
%	functor(Term,F,A),
%	Term =.. [_|Args],
%	get_indexing_spec(F/A,Specs),
%	( chr_pp_flag(term_indexing,on) ->
%		spectermvars(Specs,Args,F,A,Body,Vars)
%	;
%		create_indexed_variables_body(Args,ArgModes,Vars,1,F/A,MaybeBody,N),
%		( MaybeBody == empty ->
%		
%			Body = (Vars = [])
%		; N == 0 ->
%			Body = term_variables(Susp,Vars)
%		; 
%			MaybeBody = Body
%		)
%	),
%	Clause = 
%		( '$indexed_variables'(Susp,Vars) :-
%			Susp = Term,
%			Body
%		).	
%generate_indexed_variables_clause(FA,_) <=>
%	chr_error(internal,'generate_indexed_variables_clause: missing mode info for ~w.\n',[FA]).
%===============================================================================
:- chr_constraint generate_indexed_variables_body/4.
:- chr_option(mode,generate_indexed_variables_body(+,?,+,?)).
%-------------------------------------------------------------------------------
constraint_mode(F/A,ArgModes) \ generate_indexed_variables_body(F/A,Args,Body,Vars) <=>
	get_indexing_spec(F/A,Specs),
	( chr_pp_flag(term_indexing,on) ->
		spectermvars(Specs,Args,F,A,Body,Vars)
	;
		create_indexed_variables_body(Args,ArgModes,Vars,1,F/A,MaybeBody,N),
		( MaybeBody == empty ->
			Body = true,
			Vars = []
		; N == 0 ->
			Body = term_variables(Args,Vars)
		; 
			MaybeBody = Body
		)
	).
generate_indexed_variables_body(FA,_,_,_) <=>
	chr_error(internal,'generate_indexed_variables_body: missing mode info for ~w.\n',[FA]).
%===============================================================================

create_indexed_variables_body([],[],_,_,_,empty,0).
create_indexed_variables_body([V|Vs],[Mode|Modes],Vars,I,FA,Body,N) :-
	J is I + 1,
	create_indexed_variables_body(Vs,Modes,Tail,J,FA,RBody,M),
	( Mode \== (+),
          is_indexed_argument(FA,I) ->
		( RBody == empty ->
			Body = term_variables(V,Vars)
		;
			Body = (term_variables(V,Vars,Tail),RBody)
		),
		N = M
	;
		Vars = Tail,
		Body = RBody,
		N is M + 1
	).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% EXPERIMENTAL
spectermvars(Specs,Args,F,A,Goal,Vars) :-
	spectermvars(Args,1,Specs,F,A,Vars,[],Goal).	

spectermvars([],B,_,_,A,L,L,true) :- B > A, !.
spectermvars([Arg|Args],I,Specs,F,A,L,T,Goal) :-
	Goal = (ArgGoal,RGoal),
	argspecs(Specs,I,TempArgSpecs,RSpecs),
	merge_argspecs(TempArgSpecs,ArgSpecs),
	arggoal(ArgSpecs,Arg,ArgGoal,L,L1),
	J is I + 1,
	spectermvars(Args,J,RSpecs,F,A,L1,T,RGoal).

argspecs([],_,[],[]).
argspecs([[]|Rest],I,ArgSpecs,RestSpecs) :-
	argspecs(Rest,I,ArgSpecs,RestSpecs).
argspecs([[specinfo(J,Spec,Args)|Specs]|Rest],I,ArgSpecs,RestSpecs) :-
	( I == J ->
		ArgSpecs = [specinfo(J,Spec,Args)|RArgSpecs],
		( Specs = [] ->	
			RRestSpecs = RestSpecs
		;
			RestSpecs = [Specs|RRestSpecs]
		)
	;
		ArgSpecs = RArgSpecs,
		RestSpecs = [[specinfo(J,Spec,Args)|Specs]|RRestSpecs]
	),
	argspecs(Rest,I,RArgSpecs,RRestSpecs).

merge_argspecs(In,Out) :-
	sort(In,Sorted),
	merge_argspecs_(Sorted,Out).
	
merge_argspecs_([],[]).
merge_argspecs_([X],R) :- !, R = [X].
merge_argspecs_([specinfo(I,F1,A1),specinfo(I,F2,A2)|Rest],R) :-
	( (F1 == any ; F2 == any) ->
		merge_argspecs_([specinfo(I,any,[])|Rest],R)	
	; F1 == F2 ->
		append(A1,A2,A),
		merge_argspecs_([specinfo(I,F1,A)|Rest],R)	
	;
		R = [specinfo(I,F1,A1)|RR],
		merge_argspecs_([specinfo(I,F2,A2)|Rest],RR)
	).

arggoal(List,Arg,Goal,L,T) :-
	( List == [] ->
		L = T,
		Goal = true
	; List = [specinfo(_,any,_)] ->
		Goal = term_variables(Arg,L,T)
	;
		Goal =
		( var(Arg) ->
			L = [Arg|T]
		;
			Cases
		),
		arggoal_cases(List,Arg,L,T,Cases)
	).

arggoal_cases([],_,L,T,L=T).
arggoal_cases([specinfo(_,FA,ArgSpecs)|Rest],Arg,L,T,Cases) :-
	( ArgSpecs == [] ->
		Cases = RCases
	; ArgSpecs == [[]] ->
		Cases = RCases
	; FA = F/A ->
		Cases = (Case ; RCases),
		functor(Term,F,A),
		Term =.. [_|Args],
		Case = (Arg = Term -> ArgsGoal),
		spectermvars(Args,1,ArgSpecs,F,A,L,T,ArgsGoal)
	),
	arggoal_cases(Rest,Arg,L,T,RCases).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

generate_extra_clauses(Constraints,List) :-
	generate_activate_clauses(Constraints,List,Tail0),
	generate_remove_clauses(Constraints,Tail0,Tail1),
	generate_allocate_clauses(Constraints,Tail1,Tail2),
	generate_insert_constraint_internal_clauses(Constraints,Tail2,Tail3),
	generate_novel_production(Tail3,Tail4),
	generate_extend_history(Tail4,Tail5),
	generate_run_suspensions(Tail5,Tail6),
	Tail6 = []. % global_indexed_variables_clause(Constraints,Tail6,[]).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% remove_constraint_internal/[1/3]

generate_remove_clauses([],List,List).
generate_remove_clauses([C|Cs],List,Tail) :-
	generate_remove_clause(C,List,List1),
	generate_remove_clauses(Cs,List1,Tail).

remove_constraint_goal(Constraint,Susp,Agenda,Delete,Goal) :-
	remove_constraint_name(Constraint,Name),
	( chr_pp_flag(debugable,off), only_ground_indexed_arguments(Constraint) ->
		Goal =.. [Name, Susp,Delete]
	;
		Goal =.. [Name,Susp,Agenda,Delete]
	).
	
remove_constraint_name(Constraint,Name) :-
	make_name('$remove_constraint_internal_',Constraint,Name).

generate_remove_clause(Constraint,List,Tail) :-
	( is_used_auxiliary_predicate(remove_constraint_internal,Constraint) ->
		List = [RemoveClause|Tail],
		% use_auxiliary_predicate(chr_indexed_variables,Constraint),
		remove_constraint_goal(Constraint,Susp,Agenda,Delete,Head),
		% get_dynamic_suspension_term_field(state,Constraint,Susp,Mref,StateGoal),
		static_suspension_term(Constraint,Susp),
		get_static_suspension_term_field(state,Constraint,Susp,Mref),
		( chr_pp_flag(debugable,off), only_ground_indexed_arguments(Constraint) ->
			RemoveClause = 
			(
			    Head :-
			    	% StateGoal,
				'chr get_mutable'( State, Mref),
			    	'chr update_mutable'( removed, Mref),
				( State == not_stored_yet ->
					Delete = no
				;
					Delete = yes
				)
			)
		;
			get_static_suspension_term_field(arguments,Constraint,Susp,Args),
			generate_indexed_variables_body(Constraint,Args,IndexedVariablesBody,Agenda),
			( chr_pp_flag(debugable,on) ->
				Constraint = Functor / _,
				get_static_suspension_term_field(functor,Constraint,Susp,Functor)
			;
				true
			),
			RemoveClause = 
			(
				Head :-
					% StateGoal,
					'chr get_mutable'( State, Mref),
					'chr update_mutable'( removed, Mref),		% mark in any case
					( State == not_stored_yet ->	% compound(State) ->			% passive/1
					    Agenda = [],
					    Delete = no
%					; State==removed ->
%					    Agenda = [],
%					    Delete = no
					;
					    Delete = yes,
					    IndexedVariablesBody % chr_indexed_variables(Susp,Agenda)
					)
			)
		)    
	;
		List = Tail
	).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% activate_constraint/4

generate_activate_clauses([],List,List).
generate_activate_clauses([C|Cs],List,Tail) :-
	generate_activate_clause(C,List,List1),
	generate_activate_clauses(Cs,List1,Tail).

activate_constraint_goal(Constraint,Store,Vars,Susp,Generation,Goal) :-
	activate_constraint_name(Constraint,Name),
	( chr_pp_flag(debugable,off), only_ground_indexed_arguments(Constraint) ->
		Goal =.. [Name,Store, Susp]
	; chr_pp_flag(debugable,off), may_trigger(Constraint) ->
		Goal =.. [Name,Store, Vars, Susp, Generation]
	; 
		Goal =.. [Name,Store, Vars, Susp]
	).
	
activate_constraint_name(Constraint,Name) :-
	make_name('$activate_constraint_',Constraint,Name).

generate_activate_clause(Constraint,List,Tail) :-
	( is_used_auxiliary_predicate(activate_constraint,Constraint) ->
		List = [ActivateClause|Tail],
		% use_auxiliary_predicate(chr_indexed_variables,Constraint),
		get_dynamic_suspension_term_field(state,Constraint,Susp,Mref,StateGoal),
		activate_constraint_goal(Constraint,Store,Vars,Susp,Generation,Head),
		( chr_pp_flag(debugable,off), may_trigger(Constraint) ->
			get_dynamic_suspension_term_field(generation,Constraint,Susp,Gref,GenerationGoal),
			GenerationHandling =
			(
				GenerationGoal,			
				'chr get_mutable'( Gen, Gref),
				Generation is Gen+1,
				'chr update_mutable'( Generation, Gref)
			)
		;
			GenerationHandling = true
		),
		( chr_pp_flag(debugable,off), only_ground_indexed_arguments(Constraint) ->
			% Vars = [],
			StoreVarsGoal = 
				( State == not_stored_yet ->		% compound(State) ->			% passive/1
				    Store = yes
%				; State == removed ->			% the price for eager removal ... % XXX redundant?
%				    Store = yes
				;
				    Store = no
				)
		;
			get_dynamic_suspension_term_field(arguments,Constraint,Susp,Arguments,ArgumentsGoal),
			generate_indexed_variables_body(Constraint,Arguments,IndexedVariablesBody,Vars),
			StoreVarsGoal = 
				( State == not_stored_yet ->		% compound(State) ->			% passive/1
				    Store = yes,
				    ArgumentsGoal,
				    IndexedVariablesBody, 
				    'chr none_locked'( Vars)
%				; State == removed ->			% the price for eager removal ... % XXX redundant ?
%				    chr_indexed_variables(Susp,Vars),
%				    Store = yes
				;
				    Vars = [],
				    Store = no
				)
		),
		ActivateClause =	
		(
			Head :-
				StateGoal, 				
				'chr get_mutable'( State, Mref), 
				'chr update_mutable'( active, Mref),
				GenerationHandling,
				StoreVarsGoal
		)
	;
		List = Tail
	).
%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% allocate_constraint/4

generate_allocate_clauses([],List,List).
generate_allocate_clauses([C|Cs],List,Tail) :-
	generate_allocate_clause(C,List,List1),
	generate_allocate_clauses(Cs,List1,Tail).

allocate_constraint_goal(Constraint, Closure, Self, _F, Args,Goal) :-
	allocate_constraint_name(Constraint,Name),
	( chr_pp_flag(debugable,off), may_trigger(Constraint) ->
		Goal =.. [Name,Closure,Self|Args]
	;
		Goal =.. [Name,Self|Args]
	).
	
allocate_constraint_name(Constraint,Name) :-
	make_name('$allocate_constraint_',Constraint,Name).

generate_allocate_clause(Constraint,List,Tail) :-
	( is_used_auxiliary_predicate(allocate_constraint,Constraint) ->
		List = [AllocateClause|Tail1],
		% use_auxiliary_predicate(chr_indexed_variables,Constraint),
		Constraint = F/A,
		length(Args,A),
		allocate_constraint_goal(Constraint,Closure,Self,F,Args,Head),
		static_suspension_term(Constraint,Suspension),
		get_static_suspension_term_field(id,Constraint,Suspension,Id),
		get_static_suspension_term_field(state,Constraint,Suspension,Mref),
		( chr_pp_flag(debugable,on); may_trigger(Constraint) ->
			get_static_suspension_term_field(continuation,Constraint,Suspension,Closure),
			get_static_suspension_term_field(generation,Constraint,Suspension,Gref),
			GenerationHandling = 'chr create_mutable'(0,Gref),

			functor(Head,PredFunctor,PredArity),
			functor(MetaDecl,PredFunctor,PredArity),
			MetaDecl =.. [_,goal|QuestionMarks],
			set_elems(QuestionMarks,(?)),
			Tail1 = [(:- meta_predicate(MetaDecl))|Tail]

		;
			GenerationHandling = true,
			Tail1 = Tail
		),
		( chr_pp_flag(debugable,on) ->
			Constraint = Functor / _,
			get_static_suspension_term_field(functor,Constraint,Suspension,Functor)
		;
			true
		),
		History = t,
		get_static_suspension_term_field(history,Constraint,Suspension,Href),
		% get_static_suspension_term_field(functor,Constraint,Suspension,F),
		get_static_suspension_term_field(arguments,Constraint,Suspension,Args),
		Self = Suspension,
		AllocateClause =
		(
			Head :-
				% Self =.. Suspension, %[suspension,Id,Mref,Closure,Gref,Href,F|Args],
				GenerationHandling, %'chr create_mutable'(0,Gref), % Gref = mutable(0),
				% 'chr empty_history'(History),
				'chr create_mutable'(History,Href), % Href = mutable(History),
				'chr create_mutable'(not_stored_yet,Mref),
				'chr gen_id'( Id)
		)
	;
		List = Tail
	).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% insert_constraint_internal/[3,6]

generate_insert_constraint_internal_clauses([],List,List).
generate_insert_constraint_internal_clauses([C|Cs],List,Tail) :-
	generate_insert_constraint_internal_clause(C,List,List1),
	generate_insert_constraint_internal_clauses(Cs,List1,Tail).

insert_constraint_internal_constraint_goal(Constraint, Stored, Vars, Self, Closure, _F, Args,Goal) :-
	insert_constraint_internal_constraint_name(Constraint,Name),
	( (chr_pp_flag(debugable,on) ; may_trigger(Constraint)) ->
		Goal =.. [Name,Stored, Vars, Self, Closure | Args]
	; only_ground_indexed_arguments(Constraint) ->
		Goal =.. [Name,Self | Args]
	;
		Goal =.. [Name,Stored, Vars, Self | Args]
	).
	
insert_constraint_internal_constraint_name(Constraint,Name) :-
	make_name('$insert_constraint_internal_',Constraint,Name).

generate_insert_constraint_internal_clause(Constraint,List,Tail) :-
	( is_used_auxiliary_predicate(insert_constraint_internal,Constraint) ->
		Constraint = F/A,
		length(Args,A),
		History = t,
		insert_constraint_internal_constraint_goal(Constraint, yes, Vars, Self, Closure, F, Args,Head),
		static_suspension_term(Constraint,Suspension),
		get_static_suspension_term_field(id,Constraint,Suspension,Id),
		get_static_suspension_term_field(state,Constraint,Suspension,Mref),


		( (chr_pp_flag(debugable,on) ; may_trigger(Constraint)) ->
		   functor(Head,PredFunctor,PredArity),
		   functor(MetaDecl,PredFunctor,PredArity),
		   MetaDecl =.. [_,(?),(?),(?),goal|QuestionMarks],
		   set_elems(QuestionMarks,(?)),
		   Tail1 = [(:- meta_predicate(MetaDecl))|Tail]
		;
		    Tail1 = Tail
		),


		( (chr_pp_flag(debugable,on); may_trigger(Constraint)) ->
			get_static_suspension_term_field(continuation,Constraint,Suspension,Closure),
			get_static_suspension_term_field(generation,Constraint,Suspension,Gref),
			GenerationHandling = 'chr create_mutable'(0,Gref)
		;
			GenerationHandling = true
		),
		( chr_pp_flag(debugable,on) ->
			Constraint = Functor / _,
			get_static_suspension_term_field(functor,Constraint,Suspension,Functor)
		;
			true
		),
		History = t,
		get_static_suspension_term_field(history,Constraint,Suspension,Href),
		% get_static_suspension_term_field(functor,Constraint,Suspension,F),
		get_static_suspension_term_field(arguments,Constraint,Suspension,Args),
		Self = Suspension,
		List = [Clause|Tail1],
		( chr_pp_flag(debugable,off), only_ground_indexed_arguments(Constraint) ->
			Closure = true,
			Clause =
			    (
				Head :-
                                        'chr create_mutable'(active,Mref),
			                GenerationHandling, %'chr create_mutable'(0,Gref),
			                % 'chr empty_history'(History),
			                'chr create_mutable'(History,Href),
			                % Self =.. [suspension,Id,Mref,Closure,Gref,Href,F|Args],
					'chr gen_id'(Id)
			    )
		;
			generate_indexed_variables_body(Constraint,Args,IndexedVariablesBody,Vars),
			Clause =
			(
				Head :-
					% Self =.. [suspension,Id,Mref,Closure,Gref,Href,F|Args],
					IndexedVariablesBody, % chr_indexed_variables(Self,Vars),
					'chr none_locked'(Vars),
                                        'chr create_mutable'(active,Mref), % Mref = mutable(active),
			                'chr create_mutable'(0,Gref),   % Gref = mutable(0),
			                % 'chr empty_history'(History),
			                'chr create_mutable'(History,Href), % Href = mutable(History),
			                'chr gen_id'(Id)
			)
		)
	;
		List = Tail
	).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% novel_production/2

generate_novel_production(List,Tail) :-
	( is_used_auxiliary_predicate(novel_production) ->
		List = [Clause|Tail],
		Clause =
		(
			'$novel_production'( Self, Tuple) :-
				arg( 3, Self, Ref), % ARGXXX
				'chr get_mutable'( History, Ref),
				( hprolog:get_ds( Tuple, History, _) ->
			    		fail
				;
			    		true
				)
		)
	;
		List = Tail
	).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% extend_history/2

generate_extend_history(List,Tail) :-
	( is_used_auxiliary_predicate(extend_history) ->
		List = [Clause|Tail],
		Clause =
		(
			'$extend_history'( Self, Tuple) :-
				arg( 3, Self, Ref), % ARGXXX
				'chr get_mutable'( History, Ref),
				hprolog:put_ds( Tuple, History, x, NewHistory),
				'chr update_mutable'( NewHistory, Ref)
		)
	;
		List = Tail
	).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
% run_suspensions/2

generate_run_suspensions(List,Tail) :-
	( is_used_auxiliary_predicate(run_suspensions) ->
		List = [Clause1,Clause2|Tail],
		Clause1 =
		(
			'$run_suspensions'([])
		),
		( chr_pp_flag(debugable,on) ->
			Clause2 =
			(
				'$run_suspensions'([S|Next] ) :-
					arg( 2, S, Mref), % ARGXXX
					'chr get_mutable'( Status, Mref),
					( Status==active ->
					    'chr update_mutable'( triggered, Mref),
					    arg( 4, S, Gref), % ARGXXX
					    'chr get_mutable'( Gen, Gref),
					    Generation is Gen+1,
					    'chr update_mutable'( Generation, Gref),
					    arg( 5, S, Goal), % ARGXXX
					    ( 
						'chr debug_event'(wake(S)),
					        call( Goal)
					    ;
						'chr debug_event'(fail(S)), !,
						fail
					    ),
					    (
						'chr debug_event'(exit(S))
					    ;
						'chr debug_event'(redo(S)),
						fail
					    ),	
					    'chr get_mutable'( Post, Mref),
					    ( Post==triggered ->
						'chr update_mutable'( active, Mref)   % catching constraints that did not do anything
					    ;
						true
					    )
					;
					    true
					),
					'$run_suspensions'( Next)
			)
		;
			Clause2 =
			(
				'$run_suspensions'([S|Next] ) :-
					arg( 2, S, Mref), % ARGXXX
					'chr get_mutable'( Status, Mref),
					( Status==active ->
					    'chr update_mutable'( triggered, Mref),
					    arg( 4, S, Gref), % ARGXXX
					    'chr get_mutable'( Gen, Gref),
					    Generation is Gen+1,
					    'chr update_mutable'( Generation, Gref),
					    arg( 5, S, Goal), % ARGXXX
					    call( Goal),
					    'chr get_mutable'( Post, Mref),
					    ( Post==triggered ->
						'chr update_mutable'( active, Mref)	% catching constraints that did not do anything
					    ;
						true
					    )
					;
					    true
					),
					'$run_suspensions'( Next)
			)
		)
	;
		List = Tail
	),!.
generate_run_suspensions(List,Tail) :-
	chr_error(internal,'generate_run_suspensions fails',[]).

%~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

%global_indexed_variables_clause(Constraints,List,Tail) :-
%	( is_used_auxiliary_predicate(chr_indexed_variables) ->
%		List = [Clause|Tail],
%		( chr_pp_flag(reduced_indexing,on) ->
%			( are_none_suspended_on_variables ->
%				Body = true,
%				Vars = []
%			;
%				Body = (Susp =.. [_,_,_,_,_,_|Term], 
%				Term1 =.. Term,
%				'$indexed_variables'(Term1,Vars))
%			),	
%			Clause = ( chr_indexed_variables(Susp,Vars) :- Body )
%		;
%			Clause =
%			( chr_indexed_variables(Susp,Vars) :-
%				'chr chr_indexed_variables'(Susp,Vars)
%			)
%		)
%	;
%		List = Tail
%	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
generate_attach_increment(Clauses) :-
	get_max_constraint_index(N),
	( N > 0 ->
		Clauses = [Clause1,Clause2],
		generate_attach_increment_empty(Clause1),
		( N == 1 ->
			generate_attach_increment_one(Clause2)
		;
			generate_attach_increment_many(N,Clause2)
		)
	;
		Clauses = []
	).

generate_attach_increment_empty((attach_increment([],_) :- true)).

generate_attach_increment_one(Clause) :-
	Head = attach_increment([Var|Vars],Susps),
	get_target_module(Mod),
	Body =
	(
		'chr not_locked'(Var),
		( get_attr(Var,Mod,VarSusps) ->
			sort(VarSusps,SortedVarSusps),
			'chr merge_attributes'(Susps,SortedVarSusps,MergedSusps),
			put_attr(Var,Mod,MergedSusps)
		;
			put_attr(Var,Mod,Susps)
		),
		attach_increment(Vars,Susps)
	), 
	Clause = (Head :- Body).

generate_attach_increment_many(N,Clause) :-
	make_attr(N,Mask,SuspsList,Attr),
	make_attr(N,OtherMask,OtherSuspsList,OtherAttr),
	Head = attach_increment([Var|Vars],Attr),
	bagof(G,X ^ Y ^ SY ^ M ^ (member2(SuspsList,OtherSuspsList,X-Y),G = (sort(Y,SY),'chr merge_attributes'(X,SY,M))),Gs),
	list2conj(Gs,SortGoals),
	bagof(MS,A ^ B ^ C ^ member((A,'chr merge_attributes'(B,C,MS)),Gs), MergedSuspsList),
	make_attr(N,MergedMask,MergedSuspsList,NewAttr),
	get_target_module(Mod),
	Body =	
	(
		'chr not_locked'(Var),
		( get_attr(Var,Mod,TOtherAttr) ->
			TOtherAttr = OtherAttr,
			SortGoals,
			MergedMask is Mask \/ OtherMask,
			put_attr(Var,Mod,NewAttr)
		;
			put_attr(Var,Mod,Attr)
		),
		attach_increment(Vars,Attr)
	),
	Clause = (Head :- Body).

%%	attr_unify_hook
generate_attr_unify_hook(Clauses) :-
	get_max_constraint_index(N),
	( N == 0 ->
		Clauses = []
	; 
		Clauses = [Clause],
		( N == 1 ->
			generate_attr_unify_hook_one(Clause)
		;
			generate_attr_unify_hook_many(N,Clause)
		)
	).

generate_attr_unify_hook_one(Clause) :-
	Head = attr_unify_hook(Susps,Other),
	get_target_module(Mod),
	make_run_suspensions(NewSusps,WakeNewSusps),
	make_run_suspensions(Susps,WakeSusps),
	Body = 
	(
		sort(Susps, SortedSusps),
		( var(Other) ->
			( get_attr(Other,Mod,OtherSusps) ->
				true
			;
		        	OtherSusps = []
			),
			sort(OtherSusps,SortedOtherSusps),
			'chr merge_attributes'(SortedSusps,SortedOtherSusps,NewSusps),
			put_attr(Other,Mod,NewSusps),
			WakeNewSusps
		;
			( compound(Other) ->
				term_variables(Other,OtherVars),
				attach_increment(OtherVars, SortedSusps)
			;
				true
			),
			WakeSusps
		)
	),
	Clause = (Head :- Body).

generate_attr_unify_hook_many(N,Clause) :-
	make_attr(N,Mask,SuspsList,Attr),
	make_attr(N,OtherMask,OtherSuspsList,OtherAttr),
	bagof(Sort,A ^ B ^ ( member(A,SuspsList) , Sort = sort(A,B) ) , SortGoalList),
	list2conj(SortGoalList,SortGoals),
	bagof(B, A ^ member(sort(A,B),SortGoalList), SortedSuspsList),
	bagof(C, D ^ E ^ F ^ G ^ (member2(SortedSuspsList,OtherSuspsList,D-E),
                                  C = (sort(E,F),
                                       'chr merge_attributes'(D,F,G)) ), 
              SortMergeGoalList),
	bagof(G, D ^ F ^ H ^ member((H,'chr merge_attributes'(D,F,G)),SortMergeGoalList) , MergedSuspsList),
	list2conj(SortMergeGoalList,SortMergeGoals),
	make_attr(N,MergedMask,MergedSuspsList,MergedAttr),
	make_attr(N,Mask,SortedSuspsList,SortedAttr),
	Head = attr_unify_hook(Attr,Other),
	get_target_module(Mod),
	make_run_suspensions_loop(MergedSuspsList,WakeMergedSusps),
	make_run_suspensions_loop(SortedSuspsList,WakeSortedSusps),
	Body =
	(
		SortGoals,
		( var(Other) ->
			( get_attr(Other,Mod,TOtherAttr) ->
				TOtherAttr = OtherAttr,
				SortMergeGoals,
				MergedMask is Mask \/ OtherMask,
				put_attr(Other,Mod,MergedAttr),
				WakeMergedSusps
			;
				put_attr(Other,Mod,SortedAttr),
				WakeSortedSusps
			)
		;
			( compound(Other) ->
				term_variables(Other,OtherVars),
				attach_increment(OtherVars,SortedAttr)
			;
				true
			),
			WakeSortedSusps
		)	
	),	
	Clause = (Head :- Body).

make_run_suspensions(Susps,Goal) :-
	make_run_suspensions(1,Susps,Goal).

make_run_suspensions(Index,Susps,Goal) :-
	( get_indexed_constraint(Index,C), may_trigger(C) ->
		use_auxiliary_predicate(run_suspensions),
		Goal = '$run_suspensions'(Susps)
	;
		Goal = true
	).

make_run_suspensions_loop(SuspsList,Goal) :-
	make_run_suspensions_loop(SuspsList,1,Goal).

make_run_suspensions_loop([],_,true).
make_run_suspensions_loop([Susps|SuspsList],I,(Goal,Goals)) :-
	make_run_suspensions(I,Susps,Goal),
	J is I + 1,
	make_run_suspensions_loop(SuspsList,J,Goals).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% $insert_in_store_F/A
% $delete_from_store_F/A

generate_insert_delete_constraints([],[]). 
generate_insert_delete_constraints([FA|Rest],Clauses) :-
	( is_stored(FA) ->
		Clauses = [IClause,DClause|RestClauses],
		generate_insert_delete_constraint(FA,IClause,DClause)
	;
		Clauses = RestClauses
	),
	generate_insert_delete_constraints(Rest,RestClauses).
			
generate_insert_delete_constraint(FA,IClause,DClause) :-
	get_store_type(FA,StoreType),
	generate_insert_constraint(StoreType,FA,IClause),
	generate_delete_constraint(StoreType,FA,DClause).

generate_insert_constraint(StoreType,C,Clause) :-
	make_name('$insert_in_store_',C,ClauseName),
	Head =.. [ClauseName,Susp],
	generate_insert_constraint_body(StoreType,C,Susp,Body),
	( chr_pp_flag(store_counter,on) ->
		InsertCounterInc = '$insert_counter_inc'
	;
		InsertCounterInc = true	
	),
	Clause = (Head :- InsertCounterInc,Body).	

generate_insert_constraint_body(default,C,Susp,Body) :-
	global_list_store_name(C,StoreName),
	make_get_store_goal(StoreName,Store,GetStoreGoal),
	make_update_store_goal(StoreName,Cell,UpdateStoreGoal),
	( chr_pp_flag(debugable,on) ->
		Cell = [Susp|Store],
	 	Body =
	 	(
	 		GetStoreGoal,    % nb_getval(StoreName,Store),
	 		UpdateStoreGoal  % b_setval(StoreName,[Susp|Store])
	 	)
	;
		set_dynamic_suspension_term_field(global_list_prev,C,NextSusp,Cell,SetGoal),	
		Body =
		(
			GetStoreGoal,    % nb_getval(StoreName,Store),
			Cell = [Susp|Store],
			UpdateStoreGoal,  % b_setval(StoreName,[Susp|Store])
			( Store = [NextSusp|_] ->
				SetGoal
			;
				true
			)
		)
	).
% 	get_target_module(Mod),
% 	get_max_constraint_index(Total),
% 	( Total == 1 ->
% 		generate_attach_body_1(C,Store,Susp,AttachBody)
% 	;
% 		generate_attach_body_n(C,Store,Susp,AttachBody)
% 	),
% 	Body =
% 	(
% 		'chr default_store'(Store),
% 		AttachBody
% 	).
generate_insert_constraint_body(multi_inthash(Indexes),C,Susp,Body) :-
	generate_multi_inthash_insert_constraint_bodies(Indexes,C,Susp,Body).
generate_insert_constraint_body(multi_hash(Indexes),C,Susp,Body) :-
	generate_multi_hash_insert_constraint_bodies(Indexes,C,Susp,Body).
generate_insert_constraint_body(global_ground,C,Susp,Body) :-
	global_ground_store_name(C,StoreName),
	make_get_store_goal(StoreName,Store,GetStoreGoal),
	make_update_store_goal(StoreName,Cell,UpdateStoreGoal),
	( chr_pp_flag(debugable,on) ->
		Cell = [Susp|Store],
	 	Body =
	 	(
	 		GetStoreGoal,    % nb_getval(StoreName,Store),
	 		UpdateStoreGoal  % b_setval(StoreName,[Susp|Store])
	 	)
	;
		set_dynamic_suspension_term_field(global_list_prev,C,NextSusp,Cell,SetGoal),	
		Body =
		(
			GetStoreGoal,    % nb_getval(StoreName,Store),
			Cell = [Susp|Store],
			UpdateStoreGoal,  % b_setval(StoreName,[Susp|Store])
			( Store = [NextSusp|_] ->
				SetGoal
			;
				true
			)
		)
	).
% 	global_ground_store_name(C,StoreName),
% 	make_get_store_goal(StoreName,Store,GetStoreGoal),
% 	make_update_store_goal(StoreName,[Susp|Store],UpdateStoreGoal),
% 	Body =
% 	(
% 		GetStoreGoal,    % nb_getval(StoreName,Store),
% 		UpdateStoreGoal  % b_setval(StoreName,[Susp|Store])
% 	).
generate_insert_constraint_body(global_singleton,C,Susp,Body) :-
	global_singleton_store_name(C,StoreName),
	make_update_store_goal(StoreName,Susp,UpdateStoreGoal),
	Body =
	(
		UpdateStoreGoal % b_setval(StoreName,Susp)
	).
generate_insert_constraint_body(multi_store(StoreTypes),C,Susp,Body) :-
	find_with_var_identity(
		B,
		[Susp],
		( 
			member(ST,StoreTypes),
			generate_insert_constraint_body(ST,C,Susp,B)
		),
		Bodies
		),
	list2conj(Bodies,Body).

generate_multi_inthash_insert_constraint_bodies([],_,_,true).
generate_multi_inthash_insert_constraint_bodies([Index|Indexes],FA,Susp,(Body,Bodies)) :-
	multi_hash_store_name(FA,Index,StoreName),
	multi_hash_key(FA,Index,Susp,KeyBody,Key),
	Body =
	(
		KeyBody,
		nb_getval(StoreName,Store),
		insert_iht(Store,Key,Susp)
	),
	generate_multi_inthash_insert_constraint_bodies(Indexes,FA,Susp,Bodies).
generate_multi_hash_insert_constraint_bodies([],_,_,true).
generate_multi_hash_insert_constraint_bodies([Index|Indexes],FA,Susp,(Body,Bodies)) :-
	multi_hash_store_name(FA,Index,StoreName),
	multi_hash_key(FA,Index,Susp,KeyBody,Key),
	make_get_store_goal(StoreName,Store,GetStoreGoal),
	Body =
	(
		KeyBody,
		GetStoreGoal, % nb_getval(StoreName,Store),
		insert_ht(Store,Key,Susp)
	),
	generate_multi_hash_insert_constraint_bodies(Indexes,FA,Susp,Bodies).

generate_delete_constraint(StoreType,FA,Clause) :-
	make_name('$delete_from_store_',FA,ClauseName),
	Head =.. [ClauseName,Susp],
	generate_delete_constraint_body(StoreType,FA,Susp,Body),
	( chr_pp_flag(store_counter,on) ->
		DeleteCounterInc = '$delete_counter_inc'
	;
		DeleteCounterInc = true	
	),
	Clause = (Head :- DeleteCounterInc, Body).

generate_delete_constraint_body(default,C,Susp,Body) :-
	( chr_pp_flag(debugable,on) ->
	 	global_list_store_name(C,StoreName),
	 	make_get_store_goal(StoreName,Store,GetStoreGoal),
	 	make_update_store_goal(StoreName,NStore,UpdateStoreGoal),
	 	Body =
	 	(
	 		GetStoreGoal, % nb_getval(StoreName,Store),
	 		'chr sbag_del_element'(Store,Susp,NStore),
	 		UpdateStoreGoal % b_setval(StoreName,NStore)
	 	)
	;
		get_dynamic_suspension_term_field(global_list_prev,C,Susp,PredCell,GetGoal),
		global_list_store_name(C,StoreName),
		make_get_store_goal(StoreName,Store,GetStoreGoal),
		make_update_store_goal(StoreName,Tail,UpdateStoreGoal),
		set_dynamic_suspension_term_field(global_list_prev,C,NextSusp,_,SetGoal1),	
		set_dynamic_suspension_term_field(global_list_prev,C,NextSusp,PredCell,SetGoal2),	
		Body =
		(
			GetGoal,
			( var(PredCell) ->
				GetStoreGoal, % nb_getval(StoreName,Store),
				Store = [_|Tail],
				UpdateStoreGoal,
				( Tail = [NextSusp|_] ->
					SetGoal1
				;
					true
				)	
			;
				PredCell = [_,_|Tail],
				setarg(2,PredCell,Tail),
				( Tail = [NextSusp|_] ->
					SetGoal2
				;
					true
				)	
			)
		)
	).
% 	get_target_module(Mod),
% 	get_max_constraint_index(Total),
% 	( Total == 1 ->
% 		generate_detach_body_1(C,Store,Susp,DetachBody),
% 		Body =
% 		(
% 			'chr default_store'(Store),
% 			DetachBody
% 		)
% 	;
% 		generate_detach_body_n(C,Store,Susp,DetachBody),
% 		Body =
% 		(
% 			'chr default_store'(Store),
% 			DetachBody
% 		)
% 	).
generate_delete_constraint_body(multi_inthash(Indexes),C,Susp,Body) :-
	generate_multi_inthash_delete_constraint_bodies(Indexes,C,Susp,Body).
generate_delete_constraint_body(multi_hash(Indexes),C,Susp,Body) :-
	generate_multi_hash_delete_constraint_bodies(Indexes,C,Susp,Body).
generate_delete_constraint_body(global_ground,C,Susp,Body) :-
	( chr_pp_flag(debugable,on) ->
		global_ground_store_name(C,StoreName),
	 	make_get_store_goal(StoreName,Store,GetStoreGoal),
	 	make_update_store_goal(StoreName,NStore,UpdateStoreGoal),
	 	Body =
	 	(
	 		GetStoreGoal, % nb_getval(StoreName,Store),
	 		'chr sbag_del_element'(Store,Susp,NStore),
	 		UpdateStoreGoal % b_setval(StoreName,NStore)
	 	)
	;
		get_dynamic_suspension_term_field(global_list_prev,C,Susp,PredCell,GetGoal),
		global_ground_store_name(C,StoreName),
		make_get_store_goal(StoreName,Store,GetStoreGoal),
		make_update_store_goal(StoreName,Tail,UpdateStoreGoal),
		set_dynamic_suspension_term_field(global_list_prev,C,NextSusp,_,SetGoal1),	
		set_dynamic_suspension_term_field(global_list_prev,C,NextSusp,PredCell,SetGoal2),	
		Body =
		(
			GetGoal,
			( var(PredCell) ->
				GetStoreGoal, % nb_getval(StoreName,Store),
				Store = [_|Tail],
				UpdateStoreGoal,
				( Tail = [NextSusp|_] ->
					SetGoal1
				;
					true
				)	
			;
				PredCell = [_,_|Tail],
				setarg(2,PredCell,Tail),
				( Tail = [NextSusp|_] ->
					SetGoal2
				;
					true
				)	
			)
		)
	).
% 	global_ground_store_name(C,StoreName),
% 	make_get_store_goal(StoreName,Store,GetStoreGoal),
% 	make_update_store_goal(StoreName,NStore,UpdateStoreGoal),
% 	Body =
% 	(
% 		GetStoreGoal, % nb_getval(StoreName,Store),
% 		'chr sbag_del_element'(Store,Susp,NStore),
% 		UpdateStoreGoal % b_setval(StoreName,NStore)
% 	).
generate_delete_constraint_body(global_singleton,C,_Susp,Body) :-
	global_singleton_store_name(C,StoreName),
	make_update_store_goal(StoreName,[],UpdateStoreGoal),
	Body =
	(
		UpdateStoreGoal  % b_setval(StoreName,[])
	).
generate_delete_constraint_body(multi_store(StoreTypes),C,Susp,Body) :-
	find_with_var_identity(
		B,
		[Susp],
		(
			member(ST,StoreTypes),
			generate_delete_constraint_body(ST,C,Susp,B)
		),
		Bodies
	),
	list2conj(Bodies,Body).

generate_multi_inthash_delete_constraint_bodies([],_,_,true).
generate_multi_inthash_delete_constraint_bodies([Index|Indexes],FA,Susp,(Body,Bodies)) :-
	multi_hash_store_name(FA,Index,StoreName),
	multi_hash_key(FA,Index,Susp,KeyBody,Key),
	Body =
	(
		KeyBody,
		nb_getval(StoreName,Store),
		delete_iht(Store,Key,Susp)
	),
	generate_multi_inthash_delete_constraint_bodies(Indexes,FA,Susp,Bodies).
generate_multi_hash_delete_constraint_bodies([],_,_,true).
generate_multi_hash_delete_constraint_bodies([Index|Indexes],FA,Susp,(Body,Bodies)) :-
	multi_hash_store_name(FA,Index,StoreName),
	multi_hash_key(FA,Index,Susp,KeyBody,Key),
	make_get_store_goal(StoreName,Store,GetStoreGoal),
	Body =
	(
		KeyBody,
		GetStoreGoal, % nb_getval(StoreName,Store),
		delete_ht(Store,Key,Susp)
	),
	generate_multi_hash_delete_constraint_bodies(Indexes,FA,Susp,Bodies).

generate_delete_constraint_call(FA,Susp,Call) :-
	make_name('$delete_from_store_',FA,Functor),
	Call =.. [Functor,Susp]. 

generate_insert_constraint_call(FA,Susp,Call) :-
	make_name('$insert_in_store_',FA,Functor),
	Call =.. [Functor,Susp]. 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- chr_constraint 
	module_initializer/1,
	module_initializers/1.

module_initializers(G), module_initializer(Initializer) <=>
	G = (Initializer,Initializers),
	module_initializers(Initializers).

module_initializers(G) <=>
	G = true.

generate_attach_code(Constraints,[Enumerate|L]) :-
	enumerate_stores_code(Constraints,Enumerate),
	generate_attach_code(Constraints,L,T),
	module_initializers(Initializers),
	prolog_global_variables_code(PrologGlobalVariables),
	T = [('$chr_initialization' :- Initializers)
	     |PrologGlobalVariables].
% 	T = [('$chr_initialization' :- Initializers),
% 	     (:- '$chr_initialization')|PrologGlobalVariables
% 	    ].

generate_attach_code([],L,L).
generate_attach_code([C|Cs],L,T) :-
	get_store_type(C,StoreType),
	generate_attach_code(StoreType,C,L,L1),
	generate_attach_code(Cs,L1,T). 

generate_attach_code(default,C,L,T) :-
	global_list_store_initialisation(C,L,T).
generate_attach_code(multi_inthash(Indexes),C,L,T) :-
	multi_inthash_store_initialisations(Indexes,C,L,L1),
	multi_inthash_via_lookups(Indexes,C,L1,T).
generate_attach_code(multi_hash(Indexes),C,L,T) :-
	multi_hash_store_initialisations(Indexes,C,L,L1),
	multi_hash_via_lookups(Indexes,C,L1,T).
generate_attach_code(global_ground,C,L,T) :-
	global_ground_store_initialisation(C,L,T).
generate_attach_code(global_singleton,C,L,T) :-
	global_singleton_store_initialisation(C,L,T).
generate_attach_code(multi_store(StoreTypes),C,L,T) :-
	multi_store_generate_attach_code(StoreTypes,C,L,T).

multi_store_generate_attach_code([],_,L,L).
multi_store_generate_attach_code([ST|STs],C,L,T) :-
	generate_attach_code(ST,C,L,L1),
	multi_store_generate_attach_code(STs,C,L1,T).	

multi_inthash_store_initialisations([],_,L,L).
multi_inthash_store_initialisations([Index|Indexes],FA,L,T) :-
	multi_hash_store_name(FA,Index,StoreName),
	module_initializer((new_iht(HT),nb_setval(StoreName,HT))),
	% L = [(:- (chr_integertable_store:new_ht(HT),nb_setval(StoreName,HT)) )|L1],
%	L1 = L,
	L = [ (initial_gv_value(StoreName,HT) :- new_iht(HT)) |L1],
	multi_inthash_store_initialisations(Indexes,FA,L1,T).
multi_hash_store_initialisations([],_,L,L).
multi_hash_store_initialisations([Index|Indexes],FA,L,T) :-
	multi_hash_store_name(FA,Index,StoreName),
	prolog_global_variable(StoreName),
	make_init_store_goal(StoreName,HT,InitStoreGoal),
	module_initializer((new_ht(HT),InitStoreGoal)),
%	L1 = L,
	L = [ (initial_gv_value(StoreName,HT) :- new_ht(HT)) |L1],
	multi_hash_store_initialisations(Indexes,FA,L1,T).

global_list_store_initialisation(C,L,T) :-
	global_list_store_name(C,StoreName),
	prolog_global_variable(StoreName),
	make_init_store_goal(StoreName,[],InitStoreGoal),
	module_initializer(InitStoreGoal),
	L = [ (initial_gv_value(StoreName,[])) |T].
global_ground_store_initialisation(C,L,T) :-
	global_ground_store_name(C,StoreName),
	prolog_global_variable(StoreName),
	make_init_store_goal(StoreName,[],InitStoreGoal),
	module_initializer(InitStoreGoal),
	L = [ (initial_gv_value(StoreName,[])) |T].
global_singleton_store_initialisation(C,L,T) :-
	global_singleton_store_name(C,StoreName),
	prolog_global_variable(StoreName),
	make_init_store_goal(StoreName,[],InitStoreGoal),
	module_initializer(InitStoreGoal),
	L = [ (initial_gv_value(StoreName,[])) |T].

multi_inthash_via_lookups([],_,L,L).
multi_inthash_via_lookups([Index|Indexes],C,L,T) :-
	multi_hash_via_lookup_name(C,Index,PredName),
	Head =.. [PredName,Key,SuspsList],
	multi_hash_store_name(C,Index,StoreName),
	Body = 
	(
		nb_getval(StoreName,HT),
		lookup_iht(HT,Key,SuspsList)
	),
	L = [(Head :- Body)|L1],
	multi_inthash_via_lookups(Indexes,C,L1,T).
multi_hash_via_lookups([],_,L,L).
multi_hash_via_lookups([Index|Indexes],C,L,T) :-
	multi_hash_via_lookup_name(C,Index,PredName),
	Head =.. [PredName,Key,SuspsList],
	multi_hash_store_name(C,Index,StoreName),
	make_get_store_goal(StoreName,HT,GetStoreGoal),
	Body = 
	(
		GetStoreGoal, % nb_getval(StoreName,HT),
		lookup_ht(HT,Key,SuspsList)
	),
	L = [(Head :- Body)|L1],
	multi_hash_via_lookups(Indexes,C,L1,T).

multi_hash_via_lookup_name(F/A,Index,Name) :-
	( integer(Index) ->
		IndexName = Index
	; is_list(Index) ->
		atom_concat_list(Index,IndexName)
	),
	atom_concat_list(['$via1_multi_hash_',F,(/),A,'-',IndexName],Name).

multi_hash_store_name(F/A,Index,Name) :-
	get_target_module(Mod),		
	( integer(Index) ->
		IndexName = Index
	; is_list(Index) ->
		atom_concat_list(Index,IndexName)
	),
	atom_concat_list(['$chr_store_multi_hash_',Mod,(:),F,(/),A,'-',IndexName],Name).

multi_hash_key(F/A,Index,Susp,KeyBody,Key) :-
	( ( integer(Index) ->
		I = Index
	  ; 
		Index = [I]
	  ) ->
		get_dynamic_suspension_term_field(argument(I),F/A,Susp,Key,KeyBody)
	; is_list(Index) ->
		sort(Index,Indexes),
		find_with_var_identity(Goal-KeyI,[Susp],(member(I,Indexes),get_dynamic_suspension_term_field(argument(I),F/A,Susp,KeyI,Goal)),ArgKeyPairs), 
		once(pairup(Bodies,Keys,ArgKeyPairs)),
		Key =.. [k|Keys],
		list2conj(Bodies,KeyBody)
	).

multi_hash_key_args(Index,Head,KeyArgs) :-
	( integer(Index) ->
		arg(Index,Head,Arg),
		KeyArgs = [Arg]
	; is_list(Index) ->
		sort(Index,Indexes),
		term_variables(Head,Vars),
		find_with_var_identity(Arg,Vars,(member(I,Indexes), arg(I,Head,Arg)),KeyArgs)
	).
		
global_list_store_name(F/A,Name) :-
	get_target_module(Mod),		
	atom_concat_list(['$chr_store_global_list_',Mod,(:),F,(/),A],Name).
global_ground_store_name(F/A,Name) :-
	get_target_module(Mod),		
	atom_concat_list(['$chr_store_global_ground_',Mod,(:),F,(/),A],Name).
global_singleton_store_name(F/A,Name) :-
	get_target_module(Mod),		
	atom_concat_list(['$chr_store_global_singleton_',Mod,(:),F,(/),A],Name).

:- chr_constraint
	prolog_global_variable/1,
	prolog_global_variables/1.

:- chr_option(mode,prolog_global_variable(+)).
:- chr_option(mode,prolog_global_variable(2)).

prolog_global_variable(Name) \ prolog_global_variable(Name) <=> true.

prolog_global_variables(List), prolog_global_variable(Name) <=> 
	List = [Name|Tail],
	prolog_global_variables(Tail).
prolog_global_variables(List) <=> List = [].

%% SWI begin
prolog_global_variables_code(Code) :-
	prolog_global_variables(Names),
	( Names == [] ->
		Code = []
	;
	    Code = [ (:- multifile initial_gv_value/2) ]


%		findall('$chr_prolog_global_variable'(Name),member(Name,Names),NameDeclarations),
% 		Code = [(:- dynamic user:exception/3),
% 			(:- multifile user:exception/3),
% 			(user:exception(undefined_global_variable,Name,retry) :-
% 			        (
% 				'$chr_prolog_global_variable'(Name),
% 				'$chr_initialization'
% 			        )
% 			)
% 	       		|
% 			NameDeclarations
% 			]
%		Code = [
%			(:- multifile initial_gv_value/2),
%			(initial_gv_value(Name,Value) :-
%		             '$chr_prolog_global_variable'(Name),
%			     '$chr_initialization',
%			     b_getval(Name,Value))
%	       		|
%			NameDeclarations
%			]
	).
%% SWI end
%% SICStus begin
prolog_global_variables_code([]).
%% SICStus end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%sbag_member_call(S,L,sysh:mem(S,L)).
sbag_member_call(S,L,'chr sbag_member'(S,L)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

enumerate_stores_code(Constraints,Clause) :-
	Head = '$enumerate_constraints'(Constraint),
	enumerate_store_bodies(Constraints,Constraint,Bodies),
	list2disj(Bodies,Body),
	Clause = (Head :- Body).	

enumerate_store_bodies([],_,[]).
enumerate_store_bodies([C|Cs],Constraint,L) :-
	( is_stored(C) ->
		get_store_type(C,StoreType),
		enumerate_store_body(StoreType,C,Suspension,SuspensionBody),
		get_dynamic_suspension_term_field(arguments,C,Suspension,Arguments,DynamicGoal),
		C = F/_,
		Body = (SuspensionBody, DynamicGoal, Constraint =.. [F|Arguments]),
		L = [Body|T]
	;
		L = T
	),
	enumerate_store_bodies(Cs,Constraint,T).

enumerate_store_body(default,C,Susp,Body) :-
	global_list_store_name(C,StoreName),
	sbag_member_call(Susp,List,Sbag),
	make_get_store_goal(StoreName,List,GetStoreGoal),
	Body =
	(
		GetStoreGoal, % nb_getval(StoreName,List),
		Sbag
	).
% 	get_constraint_index(C,Index),
% 	get_target_module(Mod),
% 	get_max_constraint_index(MaxIndex),
% 	Body1 = 
% 	(
% 		'chr default_store'(GlobalStore),
% 		get_attr(GlobalStore,Mod,Attr)
% 	),
% 	( MaxIndex > 1 ->
% 		NIndex is Index + 1,
% 		sbag_member_call(Susp,List,Sbag),
% 		Body2 =	
% 		(
% 			arg(NIndex,Attr,List),
% 			Sbag
% 		)
% 	;
% 		sbag_member_call(Susp,Attr,Sbag),
% 		Body2 = Sbag
% 	),
% 	Body = (Body1,Body2).
enumerate_store_body(multi_inthash([Index|_]),C,Susp,Body) :-
	multi_inthash_enumerate_store_body(Index,C,Susp,Body).
enumerate_store_body(multi_hash([Index|_]),C,Susp,Body) :-
	multi_hash_enumerate_store_body(Index,C,Susp,Body).
enumerate_store_body(global_ground,C,Susp,Body) :-
	global_ground_store_name(C,StoreName),
	sbag_member_call(Susp,List,Sbag),
	make_get_store_goal(StoreName,List,GetStoreGoal),
	Body =
	(
		GetStoreGoal, % nb_getval(StoreName,List),
		Sbag
	).
enumerate_store_body(global_singleton,C,Susp,Body) :-
	global_singleton_store_name(C,StoreName),
	make_get_store_goal(StoreName,Susp,GetStoreGoal),
	Body =
	(
		GetStoreGoal, % nb_getval(StoreName,Susp),
		Susp \== []
	).
enumerate_store_body(multi_store(STs),C,Susp,Body) :-
	once((
		member(ST,STs),
		enumerate_store_body(ST,C,Susp,Body)
	)).

multi_inthash_enumerate_store_body(I,C,Susp,B) :-
	multi_hash_store_name(C,I,StoreName),
	B =
	(
		nb_getval(StoreName,HT),
		value_iht(HT,Susp)	
	).
multi_hash_enumerate_store_body(I,C,Susp,B) :-
	multi_hash_store_name(C,I,StoreName),
	make_get_store_goal(StoreName,HT,GetStoreGoal),
	B =
	(
		GetStoreGoal, % nb_getval(StoreName,HT),
		value_ht(HT,Susp)	
	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


:- chr_constraint
	prev_guard_list/7,
	simplify_guards/1,
	set_all_passive/1.

:- chr_option(mode,prev_guard_list(+,+,+,+,+,+,+)).
:- chr_option(mode,simplify_guards(+)).
:- chr_option(mode,set_all_passive(+)).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    GUARD SIMPLIFICATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% If the negation of the guards of earlier rules entails (part of)
% the current guard, the current guard can be simplified. We can only
% use earlier rules with a head that matches if the head of the current
% rule does, and which make it impossible for the current rule to match
% if they fire (i.e. they shouldn't be propagation rules and their
% head constraints must be subsets of those of the current rule).
% At this point, we know for sure that the negation of the guard
% of such a rule has to be true (otherwise the earlier rule would have
% fired, because of the refined operational semantics), so we can use
% that information to simplify the guard by replacing all entailed
% conditions by true/0. As a consequence, the never-stored analysis
% (in a further phase) will detect more cases of never-stored constraints.
% 
% e.g.      c(X),d(Y) <=> X > 0 | ...
%           e(X) <=> X < 0 | ...
%           c(X) \ d(Y),e(Z) <=> X =< 0, Z >= 0, ... | ...  
%		   	         \____________/
%                                    true

guard_simplification :- 
    ( chr_pp_flag(guard_simplification,on) ->
	multiple_occ_constraints_checked([]),
	simplify_guards(1)
    ;
	true
    ).

% for every rule, we create a prev_guard_list where the last argument
% eventually is a list of the negations of earlier guards
rule(RuleNb,Rule) \ simplify_guards(RuleNb) <=> 
    Rule = pragma(rule(Head1,Head2,G,_B),_Ids,_Pragmas,_Name,RuleNb),
    append(Head1,Head2,Heads),
    make_head_matchings_explicit_not_negated(Heads,UniqueVarsHeads,Matchings),
    add_guard_to_head(Heads,G,GHeads),
    PrevRule is RuleNb-1,
    prev_guard_list(RuleNb,PrevRule,UniqueVarsHeads,G,[],Matchings,[GHeads]),
    multiple_occ_constraints_checked([]),
    NextRule is RuleNb+1, simplify_guards(NextRule).

simplify_guards(_) <=> true.

% the negation of the guard of a non-propagation rule is added
% if its kept head constraints are a subset of the kept constraints of
% the rule we're working on, and its removed head constraints (at least one)
% are a subset of the removed constraints
rule(N,Rule) \ prev_guard_list(RuleNb,N,H,G,GuardList,M,GH) <=>
    Rule = pragma(rule(H1,H2,G2,_B),_Ids,_Pragmas,_Name,N),
    H1 \== [], 
    append(H1,H2,Heads),
    make_head_matchings_explicit(Heads,UniqueVarsHeads,Matchings),
%    term_variables(UniqueVarsHeads+H,HVars),
%    strip_attributes(HVars,HVarAttrs),	% this seems to be necessairy to get past the setof
    setof(Renaming,head_subset(UniqueVarsHeads,H,Renaming),Renamings),
%    restore_attributes(HVars,HVarAttrs),
    Renamings \= []
    |
    compute_derived_info(Matchings,Renamings,UniqueVarsHeads,Heads,G2,M,H,GH,DerivedInfo,GH_New1),
    append(GuardList,DerivedInfo,GL1),
    list2conj(GL1,GL_),
    conj2list(GL_,GL),
    append(GH_New1,GH,GH1),
    list2conj(GH1,GH_),
    conj2list(GH_,GH_New),
    N1 is N-1,
    prev_guard_list(RuleNb,N1,H,G,GL,M,GH_New).


% if this isn't the case, we skip this one and try the next rule
prev_guard_list(RuleNb,N,H,G,GuardList,M,GH) <=> N > 0 |
    N1 is N-1, prev_guard_list(RuleNb,N1,H,G,GuardList,M,GH).

prev_guard_list(RuleNb,0,H,G,GuardList,M,GH) <=>
    GH \== [] |
    add_type_information_(H,GH,TypeInfo),
    conj2list(TypeInfo,TI),
    term_variables(H,HeadVars),    
    append([chr_pp_headvariables(HeadVars)|TI],GuardList,Info),
    list2conj(Info,InfoC),
    conj2list(InfoC,InfoL),
    prev_guard_list(RuleNb,0,H,G,InfoL,M,[]).

add_type_information_(H,[],true) :- !.
add_type_information_(H,[GH|GHs],TI) :- !,
    add_type_information(H,GH,TI1),
    TI = (TI1, TI2),
    add_type_information_(H,GHs,TI2).

% when all earlier guards are added or skipped, we simplify the guard.
% if it's different from the original one, we change the rule
prev_guard_list(RuleNb,0,H,G,GuardList,M,[]), rule(RuleNb,Rule) <=> 
    Rule = pragma(rule(Head1,Head2,G,B),Ids,Pragmas,Name,RuleNb),
    G \== true,		% let's not try to simplify this ;)
    append(M,GuardList,Info),
    simplify_guard(G,B,Info,SimpleGuard,NB),
    G \== SimpleGuard     |
%    ( prolog_flag(verbose,V), V == yes ->
%	format('            * Guard simplification in ~@\n',[format_rule(Rule)]),
%        format('     	      was: ~w\n',[G]),
%        format('     	      now: ~w\n',[SimpleGuard]),
%        (NB\==B -> format('     	      new body: ~w\n',[NB]) ; true)
%    ;
%	true	    
%    ),
    rule(RuleNb,pragma(rule(Head1,Head2,SimpleGuard,NB),Ids,Pragmas,Name,RuleNb)),
    prev_guard_list(RuleNb,0,H,SimpleGuard,GuardList,M,[]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    AUXILIARY PREDICATES 	(GUARD SIMPLIFICATION)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

compute_derived_info(Matchings,[],UniqueVarsHeads,Heads,G2,M,H,GH,[],[]) :- !.

compute_derived_info(Matchings,[Renaming1|RR],UniqueVarsHeads,Heads,G2,M,H,GH,DerivedInfo,GH_New) :- !,
    copy_term_nat(Matchings-G2,FreshMatchings),
    variable_replacement(Matchings-G2,FreshMatchings,ExtraRenaming),
    append(Renaming1,ExtraRenaming,Renaming2),  
    list2conj(Matchings,Match),
    negate_b(Match,HeadsDontMatch),
    make_head_matchings_explicit_not_negated2(Heads,UniqueVarsHeads,HeadsMatch),
    list2conj(HeadsMatch,HeadsMatchBut),
    term_variables(Renaming2,RenVars),
    term_variables(Matchings-G2-HeadsMatch,MGVars),
    new_vars(MGVars,RenVars,ExtraRenaming2),
    append(Renaming2,ExtraRenaming2,Renaming),
    negate_b(G2,TheGuardFailed),
    ( G2 == true ->		% true can't fail
	Info_ = HeadsDontMatch
    ;
	Info_ = (HeadsDontMatch ; (HeadsMatchBut, TheGuardFailed))
    ),
    copy_with_variable_replacement(Info_,DerivedInfo1,Renaming),
    copy_with_variable_replacement(G2,RenamedG2,Renaming),
    copy_with_variable_replacement(Matchings,RenamedMatchings_,Renaming),
    list2conj(RenamedMatchings_,RenamedMatchings),
    add_guard_to_head(H,RenamedG2,GH2),
    add_guard_to_head(GH2,RenamedMatchings,GH3),
    compute_derived_info(Matchings,RR,UniqueVarsHeads,Heads,G2,M,H,GH,DerivedInfo2,GH_New2),
    append([DerivedInfo1],DerivedInfo2,DerivedInfo),
    append([GH3],GH_New2,GH_New).


simplify_guard(G,B,Info,SG,NB) :-
    conj2list(G,LG),
%    guard_entailment:simplify_guards(Info,B,LG,SGL,NB),
    simplify_guards(Info,B,LG,SGL,NB),
    list2conj(SGL,SG).


new_vars([],_,[]).
new_vars([A|As],RV,ER) :-
    ( memberchk_eq(A,RV) ->
	new_vars(As,RV,ER)
    ;
	ER = [A-NewA,NewA-A|ER2],
    	new_vars(As,RV,ER2)
    ).
    
% check if a list of constraints is a subset of another list of constraints
% (multiset-subset), meanwhile computing a variable renaming to convert
% one into the other.
head_subset(H,Head,Renaming) :-
    head_subset(H,Head,Renaming,[],_).

% empty list is a subset of everything    
head_subset([],Head,Renaming,Cumul,Headleft) :- !,
    Renaming = Cumul,
    Headleft = Head.

% first constraint has to be in the list, the rest has to be a subset
% of the list with one occurrence of the first constraint removed
% (has to be multiset-subset)
head_subset([A|B],Head,Renaming,Cumul,Headleft) :- !,
    head_subset(A,Head,R1,Cumul,Headleft1),
    head_subset(B,Headleft1,R2,R1,Headleft2),
    Renaming = R2,
    Headleft = Headleft2.

% check if A is in the list, remove it from Headleft
head_subset(A,[X|Y],Renaming,Cumul,Headleft) :- !,
    ( head_subset(A,X,R1,Cumul,HL1),
	Renaming = R1,
	Headleft = Y
    ;
	head_subset(A,Y,R2,Cumul,HL2),
	Renaming = R2,
	Headleft = [X|HL2]
    ).

% A is X if there's a variable renaming to make them identical
head_subset(A,X,Renaming,Cumul,Headleft) :-
    variable_replacement(A,X,Cumul,Renaming),
    Headleft = [].

make_head_matchings_explicit(Heads,UniqueVarsHeads,Matchings) :-
    extract_variables(Heads,VH1),
    make_matchings_explicit(VH1,H1_,[],[],_,Matchings),
    insert_variables(H1_,Heads,UniqueVarsHeads).

make_head_matchings_explicit_not_negated(Heads,UniqueVarsHeads,Matchings) :-
    extract_variables(Heads,VH1),
    make_matchings_explicit_not_negated(VH1,H1_,[],Matchings),
    insert_variables(H1_,Heads,UniqueVarsHeads).

make_head_matchings_explicit_not_negated2(Heads,UniqueVarsHeads,Matchings) :-
    extract_variables(Heads,VH1),
    extract_variables(UniqueVarsHeads,UV),
    make_matchings_explicit_not_negated(VH1,UV,[],Matchings).


extract_variables([],[]).
extract_variables([X|R],V) :-
    X =.. [_|Args],
    extract_variables(R,V2),
    append(Args,V2,V).

insert_variables([],[],[]) :- !.
insert_variables(Vars,[C|R],[C2|R2]) :-
    C =.. [F | Args],
    length(Args,N),
    take_first_N(Vars,N,Args2,RestVars),
    C2 =.. [F | Args2],
    insert_variables(RestVars,R,R2).

take_first_N(Vars,0,[],Vars) :- !.
take_first_N([X|R],N,[X|R2],RestVars) :-
    N1 is N-1,
    take_first_N(R,N1,R2,RestVars).

make_matchings_explicit([],[],_,MC,MC,[]).
make_matchings_explicit([X|R],[NewVar|R2],C,MC,MCO,M) :-
    ( var(X) ->
	( memberchk_eq(X,C) ->
	    list2disj(MC,MC_disj),
	    M = [(MC_disj ; NewVar == X)|M2],		% or only =    ??
	    C2 = C
	;
	    M = M2,
	    NewVar = X,
	    C2 = [X|C]
	),
	MC2 = MC
    ;
	functor(X,F,A),
	X =.. [F|Args],
	make_matchings_explicit(Args,NewArgs,C,MC,MC_,ArgM),
	X_ =.. [F|NewArgs],
	(ArgM == [] ->
	    M = [functor(NewVar,F,A) |M2]
	;
	    list2conj(ArgM,ArgM_conj),
	    list2disj(MC,MC_disj),
	    ArgM_ = (NewVar \= X_ ; MC_disj ; ArgM_conj),
	    M = [ functor(NewVar,F,A) , ArgM_|M2]
	),
	MC2 = [ NewVar \= X_ |MC_],
	term_variables(Args,ArgVars),
	append(C,ArgVars,C2)
    ),
    make_matchings_explicit(R,R2,C2,MC2,MCO,M2).
    

make_matchings_explicit_not_negated([],[],_,[]).
make_matchings_explicit_not_negated([X|R],[NewVar|R2],C,M) :-
    M = [NewVar = X|M2],
    C2 = C,
    make_matchings_explicit_not_negated(R,R2,C2,M2).


add_guard_to_head([],G,[]).
add_guard_to_head([H|RH],G,[GH|RGH]) :-
    (var(H) ->
	find_guard_info_for_var(H,G,GH)
    ;
	functor(H,F,A),
	H =.. [F|HArgs],
	add_guard_to_head(HArgs,G,NewHArgs),
	GH =.. [F|NewHArgs]
    ),
    add_guard_to_head(RH,G,RGH).

find_guard_info_for_var(H,(G1,G2),GH) :- !,
    find_guard_info_for_var(H,G1,GH1),
    find_guard_info_for_var(GH1,G2,GH).
    
find_guard_info_for_var(H,G,GH) :-
    (G = (H1 = A), H == H1 ->
	GH = A
    ;
	(G = functor(H2,HF,HA), H == H2, ground(HF), ground(HA) ->
	    length(GHArg,HA),
	    GH =.. [HF|GHArg]
	;
	    GH = H
	)
    ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    ALWAYS FAILING HEADS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rule(RuleNb,Rule) \ prev_guard_list(RuleNb,0,H,G,GuardList,M,[]) <=> 
    chr_pp_flag(check_impossible_rules,on),
    Rule = pragma(rule(Head1,Head2,G,B),Ids,Pragmas,Name,RuleNb),
    append(M,GuardList,Info),
%    guard_entailment:entails_guard(Info,fail) |
    entails_guard(Info,fail) |
    chr_warning(weird_program,'Heads will never match in ~@.\n\tThis rule will never fire!\n',[format_rule(Rule)]),
    set_all_passive(RuleNb).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    HEAD SIMPLIFICATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% now we check the head matchings  (guard may have been simplified meanwhile)
prev_guard_list(RuleNb,0,H,G,GuardList,M,[]) \ rule(RuleNb,Rule) <=> 
    Rule = pragma(rule(Head1,Head2,G,B),Ids,Pragmas,Name,RuleNb),
    simplify_heads(M,GuardList,G,B,NewM,NewB),
    NewM \== [],
    extract_variables(Head1,VH1),
    extract_variables(Head2,VH2),
    extract_variables(H,VH),
    replace_some_heads(VH1,VH2,VH,NewM,H1,H2,G,B,NewB_),
    insert_variables(H1,Head1,NewH1),
    insert_variables(H2,Head2,NewH2),
    append(NewB,NewB_,NewBody),
    list2conj(NewBody,BodyMatchings),
    NewRule = pragma(rule(NewH1,NewH2,G,(BodyMatchings,B)),Ids,Pragmas,Name,RuleNb),
    (Head1 \== NewH1 ; Head2 \== NewH2 )    
    |
%    ( prolog_flag(verbose,V), V == yes ->
%	format('            * Head simplification in ~@\n',[format_rule(Rule)]),
%	format('     	      was: ~w \\ ~w \n',[Head2,Head1]),
%	format('     	      now: ~w \\ ~w \n',[NewH2,NewH1]),
%	format('     	      extra body: ~w \n',[BodyMatchings])
%    ;
%	true	    
%    ),
    rule(RuleNb,NewRule).    



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    AUXILIARY PREDICATES 	(HEAD SIMPLIFICATION)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

replace_some_heads(H1,H2,NH,[],H1,H2,G,Body,[]) :- !.
replace_some_heads([],[H2|RH2],[NH|RNH],[M|RM],[],[H2_|RH2_],G,Body,NewB) :- !,
    ( NH == M ->
	H2_ = M,
	replace_some_heads([],RH2,RNH,RM,[],RH2_,G,Body,NewB)
    ;
	(M = functor(X,F,A), NH == X ->
	    length(A_args,A),
	    (var(H2) ->
		NewB1 = [],
		H2_ =.. [F|A_args]
	    ;
		H2 =.. [F|OrigArgs],
		use_same_args(OrigArgs,A_args,A_args_,G,Body,NewB1),
		H2_ =.. [F|A_args_]
	    ),
	    replace_some_heads([],RH2,RNH,RM,[],RH2_,G,Body,NewB2),
	    append(NewB1,NewB2,NewB)	
	;
	    H2_ = H2,
	    replace_some_heads([],RH2,RNH,[M|RM],[],RH2_,G,Body,NewB)
	)
    ).

replace_some_heads([H1|RH1],H2,[NH|RNH],[M|RM],[H1_|RH1_],H2_,G,Body,NewB) :- !,
    ( NH == M ->
	H1_ = M,
	replace_some_heads(RH1,H2,RNH,RM,RH1_,H2_,G,Body,NewB)
    ;
	(M = functor(X,F,A), NH == X ->
	    length(A_args,A),
	    (var(H1) ->
		NewB1 = [],
		H1_ =.. [F|A_args]
	    ;
		H1 =.. [F|OrigArgs],
		use_same_args(OrigArgs,A_args,A_args_,G,Body,NewB1),
		H1_ =.. [F|A_args_]
	    ),
	    replace_some_heads(RH1,H2,RNH,RM,RH1_,H2_,G,Body,NewB2),
	    append(NewB1,NewB2,NewB)
	;
	    H1_ = H1,
	    replace_some_heads(RH1,H2,RNH,[M|RM],RH1_,H2_,G,Body,NewB)
	)
    ).

use_same_args([],[],[],_,_,[]).
use_same_args([OA|ROA],[NA|RNA],[Out|ROut],G,Body,NewB) :-
    var(OA),!,
    Out = OA,
    use_same_args(ROA,RNA,ROut,G,Body,NewB).
use_same_args([OA|ROA],[NA|RNA],[Out|ROut],G,Body,NewB) :-
    nonvar(OA),!,
    ( vars_occur_in(OA,Body) ->
        NewB = [NA = OA|NextB]
    ;
        NewB = NextB
    ),
    Out = NA,
    use_same_args(ROA,RNA,ROut,G,Body,NextB).

    
simplify_heads([],_GuardList,_G,_Body,[],[]).
simplify_heads([M|RM],GuardList,G,Body,NewM,NewB) :-
    M = (A = B),
    ( (nonvar(B) ; vars_occur_in(B,RM-GuardList)),
%	guard_entailment:entails_guard(GuardList,(A=B)) ->
	entails_guard(GuardList,(A=B)) ->
	( vars_occur_in(B,G-RM-GuardList) ->
	    NewB = NextB,
	    NewM = NextM
	;
	    ( vars_occur_in(B,Body) ->
		NewB = [A = B|NextB]
	    ;
		NewB = NextB
	    ),
	    NewM = [A|NextM]
	)
    ;
	( nonvar(B), functor(B,BFu,BAr),
%	  guard_entailment:entails_guard([functor(A,BFu,BAr)|GuardList],(A=B)) ->
	  entails_guard([functor(A,BFu,BAr)|GuardList],(A=B)) ->
	    NewB = NextB,
	    ( vars_occur_in(B,G-RM-GuardList) ->
	        NewM = NextM
    	    ;
		NewM = [functor(A,BFu,BAr)|NextM]
	    )
	;
	    NewM = NextM,
	    NewB = NextB
	)
    ),
    simplify_heads(RM,[M|GuardList],G,Body,NextM,NextB).

vars_occur_in(B,G) :-
    term_variables(B,BVars),
    term_variables(G,GVars),
    intersect_eq(BVars,GVars,L),
    L \== [].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    ALWAYS FAILING GUARDS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

set_all_passive(RuleNb), occurrence(_,_,RuleNb,ID) ==> passive(RuleNb,ID).
set_all_passive(_) <=> true.

prev_guard_list(RuleNb,0,H,G,GuardList,M,[]),rule(RuleNb,Rule) ==> 
    chr_pp_flag(check_impossible_rules,on),
    Rule = pragma(rule(_,_,G,_),_Ids,_Pragmas,_Name,RuleNb),
    conj2list(G,GL),
%    guard_entailment:entails_guard(GL,fail) |
    entails_guard(GL,fail) |
    chr_warning(weird_program,'Guard will always fail in ~@.\n\tThis rule will never fire!\n',[format_rule(Rule)]),
    set_all_passive(RuleNb).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    OCCURRENCE SUBSUMPTION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- chr_constraint
	first_occ_in_rule/4,
	next_occ_in_rule/6,
	multiple_occ_constraints_checked/1.

:- chr_option(mode,first_occ_in_rule(+,+,+,+)).
:- chr_option(mode,next_occ_in_rule(+,+,+,+,+,+)).
:- chr_option(mode,multiple_occ_constraints_checked(+)).



prev_guard_list(RuleNb,0,H,G,GuardList,M,[]),
occurrence(C,O,RuleNb,ID), occurrence(C,O2,RuleNb,ID2), rule(RuleNb,Rule)
\ multiple_occ_constraints_checked(Done) <=>
    O < O2, 
    chr_pp_flag(occurrence_subsumption,on),
    Rule = pragma(rule(H1,H2,_G,_B),_Ids,_Pragmas,_Name,RuleNb),
    H1 \== [],
    \+ memberchk_eq(C,Done) |
    first_occ_in_rule(RuleNb,C,O,ID),
    multiple_occ_constraints_checked([C|Done]).


occurrence(C,O,RuleNb,ID) \ first_occ_in_rule(RuleNb,C,O2,_) <=> O < O2 | 
    first_occ_in_rule(RuleNb,C,O,ID).

first_occ_in_rule(RuleNb,C,O,ID_o1) <=> 
    C = F/A,
    functor(FreshHead,F,A),
    next_occ_in_rule(RuleNb,C,O,ID_o1,[],FreshHead).

passive(RuleNb,ID_o2), occurrence(C,O2,RuleNb,ID_o2)
\ next_occ_in_rule(RuleNb,C,O,ID_o1,Cond,FH) <=> O2 is O+1 |
    next_occ_in_rule(RuleNb,C,O2,ID_o1,NewCond,FH).


prev_guard_list(RuleNb,0,H,G,GuardList,M,[]),
occurrence(C,O2,RuleNb,ID_o2), rule(RuleNb,Rule) \ 
next_occ_in_rule(RuleNb,C,O,ID_o1,Cond,FH) <=>
    O2 is O+1,
    Rule = pragma(rule(H1,H2,G,B),ids(ID1,ID2),_Pragmas,_Name,RuleNb)
    |
    append(H1,H2,Heads),
    add_failing_occ(Rule,Heads,H,ID_o1,ExtraCond,FH,M,C,Repl),
    ( ExtraCond == [chr_pp_void_info] ->
	next_occ_in_rule(RuleNb,C,O2,ID_o2,Cond,FH)
    ;
	append(ExtraCond,Cond,NewCond),
        add_failing_occ(Rule,Heads,H,ID_o2,CheckCond,FH,M,C,Repl2),
	copy_term_nat(GuardList,FGuardList),
	variable_replacement(GuardList,FGuardList,GLRepl),
	copy_with_variable_replacement(GuardList,GuardList2,Repl),
	copy_with_variable_replacement(GuardList,GuardList3_,Repl2),
	copy_with_variable_replacement(GuardList3_,GuardList3,GLRepl),
	append(NewCond,GuardList2,BigCond),
        append(BigCond,GuardList3,BigCond2),
	copy_with_variable_replacement(M,M2,Repl),
	copy_with_variable_replacement(M,M3,Repl2),
	append(M3,BigCond2,BigCond3),
	append([chr_pp_active_constraint(FH)|M2],BigCond3,Info),
        list2conj(CheckCond,OccSubsum),
	copy_term_nat((NewCond,BigCond2,Info,OccSubsum,FH),(NewCond2,BigCond2_,Info2,OccSubsum2,FH2)),
	term_variables(NewCond2-FH2,InfoVars),
        flatten_stuff(Info2,Info3),
	flatten_stuff(OccSubsum2,OccSubsum3),
	( OccSubsum \= chr_pp_void_info, 
	unify_stuff(InfoVars,Info3,OccSubsum3), !,
%	( guard_entailment:entails_guard(Info2,OccSubsum2) ->
	( entails_guard(Info2,OccSubsum2) ->
%	( prolog_flag(verbose,V), V == yes ->
%	    format('            * Occurrence subsumption detected in ~@\n',[format_rule(Rule)]),
%	    format('     	      passive: constraint ~w, occurrence number ~w (id ~w)\n',[C,O2,ID_o2]),
%        ;
%		true	    
%        ),
	    passive(RuleNb,ID_o2)
	; 
	    true
	)
	; true 
	),!,
	next_occ_in_rule(RuleNb,C,O2,ID_o2,NewCond,FH)
    ).


next_occ_in_rule(RuleNb,C,O,ID,Cond,Args) <=> true.
prev_guard_list(RuleNb,0,H,G,GuardList,M,[]),
multiple_occ_constraints_checked(Done) <=> true.

flatten_stuff([A|B],C) :- !,
    flatten_stuff(A,C1),
    flatten_stuff(B,C2),
    append(C1,C2,C).
flatten_stuff((A;B),C) :- !,
    flatten_stuff(A,C1),
    flatten_stuff(B,C2),
    append(C1,C2,C).
flatten_stuff((A,B),C) :- !,
    flatten_stuff(A,C1),
    flatten_stuff(B,C2),
    append(C1,C2,C).
    
flatten_stuff(chr_pp_not_in_store(A),[A]) :- !.
flatten_stuff(X,[]).

unify_stuff(AllInfo,[],[]).

unify_stuff(AllInfo,[H|RInfo],[I|ROS]) :- 
    H \== I,
    term_variables(H,HVars),
    term_variables(I,IVars),
    intersect_eq(HVars,IVars,SharedVars),
    check_safe_unif(H,I,SharedVars),
    variable_replacement(H,I,Repl),
    check_replacement(Repl),
    term_variables(Repl,ReplVars),
    list_difference_eq(ReplVars,HVars,LDiff),
    intersect_eq(AllInfo,LDiff,LDiff2),
    LDiff2 == [],
    H = I,
    unify_stuff(AllInfo,RInfo,ROS),!.
    
unify_stuff(AllInfo,X,[Y|ROS]) :-
    unify_stuff(AllInfo,X,ROS).

unify_stuff(AllInfo,[Y|RInfo],X) :-
    unify_stuff(AllInfo,RInfo,X).

check_safe_unif(H,I,SV) :- var(H), !, var(I),
    ( (memberchk_eq(H,SV);memberchk_eq(I,SV)) ->
	H == I
    ;
	true
    ).

check_safe_unif([],[],SV) :- !.
check_safe_unif([H|Hs],[I|Is],SV) :-  !,
    check_safe_unif(H,I,SV),!,
    check_safe_unif(Hs,Is,SV).
    
check_safe_unif(H,I,SV) :-
    nonvar(H),!,nonvar(I),
    H =.. [F|HA],
    I =.. [F|IA],
    check_safe_unif(HA,IA,SV).

check_safe_unif2(H,I) :- var(H), !.

check_safe_unif2([],[]) :- !.
check_safe_unif2([H|Hs],[I|Is]) :-  !,
    check_safe_unif2(H,I),!,
    check_safe_unif2(Hs,Is).
    
check_safe_unif2(H,I) :-
    nonvar(H),!,nonvar(I),
    H =.. [F|HA],
    I =.. [F|IA],
    check_safe_unif2(HA,IA).


check_replacement(Repl) :- 
    check_replacement(Repl,FirstVars),
    sort(FirstVars,Sorted),
    length(Sorted,L),!,
    length(FirstVars,L).

check_replacement([],[]).
check_replacement([A-B|R],[A|RC]) :- check_replacement(R,RC).


add_failing_occ(Rule,Heads,NH,ID_o1,FailCond,FH,M,C,Repl) :-
    Rule = pragma(rule(H1,H2,G,B),ids(ID1,ID2),_Pragmas,_Name,RuleNb),
    append(ID2,ID1,IDs),
    missing_partner_cond(Heads,NH,IDs,ID_o1,MPCond,H,C),
    copy_term_nat((H,Heads,NH),(FH2,FHeads,NH2)),
    variable_replacement((H,Heads,NH),(FH2,FHeads,NH2),Repl),
    copy_with_variable_replacement(G,FG,Repl),
    extract_explicit_matchings(FG,FG2),
    negate_b(FG2,NotFG),
    copy_with_variable_replacement(MPCond,FMPCond,Repl),
    ( check_safe_unif2(FH,FH2),    FH=FH2 ->
	FailCond = [(NotFG;FMPCond)]
    ;
	% in this case, not much can be done
	% e.g.    c(f(...)), c(g(...)) <=> ...
	FailCond = [chr_pp_void_info]
    ).



missing_partner_cond([],[],[],ID_o1,fail,H2,C).
missing_partner_cond([H|Hs],[H2|H2s],[ID_o1|IDs],ID_o1,Cond,H,C) :- !,
    missing_partner_cond(Hs,H2s,IDs,ID_o1,Cond,H,C).
missing_partner_cond([H|Hs],[NH|NHs],[ID|IDs],ID_o1,Cond,H2,F/A) :-
    Cond = (chr_pp_not_in_store(H);Cond1),
    missing_partner_cond(Hs,NHs,IDs,ID_o1,Cond1,H2,F/A).


extract_explicit_matchings(A=B) :-
    var(A), var(B), !, A=B.
extract_explicit_matchings(A==B) :-
    var(A), var(B), !, A=B.

extract_explicit_matchings((A,B),D) :- !,
    ( extract_explicit_matchings(A) ->
	extract_explicit_matchings(B,D)
    ;
	D = (A,E),
	extract_explicit_matchings(B,E)
    ).
extract_explicit_matchings(A,D) :- !,
    ( extract_explicit_matchings(A) ->
	D = true
    ;
	D = A
    ).




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    TYPE INFORMATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- chr_constraint
	type_definition/2,
	type_alias/2,
	constraint_type/2,
	get_type_definition/2,
	get_constraint_type/2,
	add_type_information/3.


:- chr_option(mode,type_definition(?,?)).
:- chr_option(mode,type_alias(?,?)).
:- chr_option(mode,constraint_type(+,+)).
:- chr_option(mode,add_type_information(+,+,?)).
:- chr_option(type_declaration,add_type_information(list,list,any)).

type_alias(T,T) <=>
   chr_error(cyclic_alias(T),'',[]).
type_alias(T,B) \ type_alias(A,T) <=> type_alias(A,B).

type_alias(T,D) \ get_type_definition(T2,Def) <=> 
	nonvar(T),nonvar(T2),functor(T,F,A),functor(T2,F,A) |
	copy_term_nat((T,D),(T1,D1)),T1=T2, get_type_definition(D1,Def).

type_definition(T,D) \ get_type_definition(T2,Def) <=> 
	nonvar(T),nonvar(T2),functor(T,F,A),functor(T2,F,A) |
	copy_term_nat((T,D),(T1,D1)),T1=T2,Def = D1.
get_type_definition(_,_) <=> fail.
constraint_type(C,T) \ get_constraint_type(C,Type) <=> Type = T.
get_constraint_type(_,_) <=> fail.

add_type_information([],[],T) <=> T=true.

constraint_mode(F/A,Modes) 
\ add_type_information([Head|R],[RealHead|RRH],TypeInfo) <=>
    functor(Head,F,A) |
    Head =.. [_|Args],
    RealHead =.. [_|RealArgs],
    add_mode_info(Modes,Args,ModeInfo),
    TypeInfo = (ModeInfo, TI),
    (get_constraint_type(F/A,Types) ->
	types2condition(Types,Args,RealArgs,Modes,TI2),
	list2conj(TI2,ConjTI),
	TI = (ConjTI,RTI),
	add_type_information(R,RRH,RTI)
    ;
	add_type_information(R,RRH,TI)
    ).


add_type_information([Head|R],_,TypeInfo) <=>
    functor(Head,F,A),
    chr_error(internal,'Mode information missing for ~w.\n',[F/A]).


add_mode_info([],[],true).
add_mode_info([(+)|Modes],[A|Args],MI) :- !,
    MI = (ground(A), ModeInfo),
    add_mode_info(Modes,Args,ModeInfo).
add_mode_info([M|Modes],[A|Args],MI) :-
    add_mode_info(Modes,Args,MI).


types2condition([],[],[],[],[]).
types2condition([Type|Types],[Arg|Args],[RealArg|RAs],[Mode|Modes],TI) :-
    (get_type_definition(Type,Def) ->
	type2condition(Def,Arg,RealArg,TC),
	(Mode \== (+) ->
	    TC_ = [(\+ ground(Arg))|TC]
	;
	    TC_ = TC
	),
	list2disj(TC_,DisjTC),
	TI = [DisjTC|RTI],
	types2condition(Types,Args,RAs,Modes,RTI)
    ;
	( builtin_type(Type,Arg,C) ->
	    TI = [C|RTI],
	    types2condition(Types,Args,RAs,Modes,RTI)
	;
	    chr_error(internal,'Undefined type ~w.\n',[Type])
	)
    ).

type2condition([],Arg,_,[]).
type2condition([Def|Defs],Arg,RealArg,TC) :-
    ( builtin_type(Def,Arg,C) ->
	true
    ;
        real_type(Def,Arg,RealArg,C)
    ),
    item2list(C,LC),
    type2condition(Defs,Arg,RealArg,RTC),
    append(LC,RTC,TC).

item2list([],[]) :- !.
item2list([X|Y],[X|Y]) :- !.
item2list(N,L) :- L = [N].

builtin_type(X,Arg,true) :- var(X),!.
builtin_type(any,Arg,true).
builtin_type(dense_int,Arg,(integer(Arg),Arg>=0)).
builtin_type(int,Arg,integer(Arg)).
builtin_type(number,Arg,number(Arg)).
builtin_type(float,Arg,float(Arg)).
builtin_type(natural,Arg,(integer(Arg),Arg>=0)).

real_type(Def,Arg,RealArg,C) :-
    ( nonvar(Def) ->
	functor(Def,F,A),
	( A == 0 ->
	    C = (Arg = F)
	;
	    Def =.. [_|TArgs],
	    length(AA,A),
	    Def2 =.. [F|AA],
	    ( var(RealArg) ->
		C = functor(Arg,F,A)
	    ;
		( functor(RealArg,F,A) ->
		    RealArg =.. [_|RAArgs],
		    nested_types(TArgs,AA,RAArgs,ACond),
		    C = (functor(Arg,F,A),Arg=Def2,ACond)
		;
		    C = functor(Arg,F,A)
		)
	    )
	)
    ;
	chr_error(internal,'Illegal type definition (must be nonvar).\n',[])
    ).	
nested_types([],[],[],true).
nested_types([T|RT],[A|RA],[RealA|RRA],C) :-
    (get_type_definition(T,Def) ->
	type2condition(Def,A,RealA,TC),
	list2disj(TC,DisjTC),
	C = (DisjTC, RC),
	nested_types(RT,RA,RRA,RC)
    ;
	( builtin_type(T,A,Cond) ->
	    C = (Cond, RC),
	    nested_types(RT,RA,RRA,RC)
	;
	    chr_error(internal,'Undefined type ~w inside type definition.\n',[T])
	)
    ).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- chr_constraint
	stored/3, % constraint,occurrence,(yes/no/maybe)
	stored_completing/3,
	stored_complete/3,
	is_stored/1,
	is_finally_stored/1,
	check_all_passive/2.

:- chr_option(mode,stored(+,+,+)).
:- chr_option(type_declaration,stored(any,int,storedinfo)).
:- chr_option(type_definition,type(storedinfo,[yes,no,maybe])).
:- chr_option(mode,stored_complete(+,+,+)).
:- chr_option(mode,maybe_complementary_guards(+,+,?,?)).
:- chr_option(mode,guard_list(+,+,+,+)).
:- chr_option(mode,check_all_passive(+,+)).

% change yes in maybe when yes becomes passive
passive(RuleNb,ID), occurrence(C,O,RuleNb,ID) \ 
	stored(C,O,yes), stored_complete(C,RO,Yesses)
	<=> O < RO | NYesses is Yesses - 1,
	stored(C,O,maybe), stored_complete(C,RO,NYesses).
% change yes in maybe when not observed
ai_not_observed(C,O) \ stored(C,O,yes), stored_complete(C,RO,Yesses)
	<=> O < RO |
	NYesses is Yesses - 1,
	stored(C,O,maybe), stored_complete(C,RO,NYesses).

occurrence(_,_,RuleNb,ID), occurrence(C2,_,RuleNb,_), stored_complete(C2,RO,0), max_occurrence(C2,MO2)
	==> RO =< MO2 |  % C2 is never stored
	passive(RuleNb,ID).	


    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rule(RuleNb,Rule),passive(RuleNb,Id) ==>
    Rule = pragma(rule(Head1,Head2,G,B),ids([Id|IDs1],IDs2),Pragmas,Name,RuleNb) |
    append(IDs1,IDs2,I), check_all_passive(RuleNb,I).

rule(RuleNb,Rule),passive(RuleNb,Id) ==>
    Rule = pragma(rule(Head1,Head2,G,B),ids([],[Id|IDs2]),Pragmas,Name,RuleNb) |
    check_all_passive(RuleNb,IDs2).

passive(RuleNb,Id) \ check_all_passive(RuleNb,[Id|IDs]) <=>
    check_all_passive(RuleNb,IDs).

rule(RuleNb,Rule) \ check_all_passive(RuleNb,[]) <=> 
    chr_warning(weird_program,'All heads passive in ~@.\n\tThis rule never fires. Please check your program.\n',[format_rule(Rule)]).
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
% collect the storage information

stored(C,O,yes) \ stored_completing(C,O,Yesses)
	<=> NO is O + 1, NYesses is Yesses + 1,
	    stored_completing(C,NO,NYesses).
stored(C,O,maybe) \ stored_completing(C,O,Yesses)
	<=> NO is O + 1,
	    stored_completing(C,NO,Yesses).
	    
stored(C,O,no) \ stored_completing(C,O,Yesses)
	<=> stored_complete(C,O,Yesses).
stored_completing(C,O,Yesses)
	<=> stored_complete(C,O,Yesses).

stored_complete(C,O,Yesses), occurrence(C,O2,RuleNb,Id) ==>
	O2 > O | passive(RuleNb,Id).
	
% decide whether a constraint is stored
max_occurrence(C,MO), stored_complete(C,RO,0) \ is_stored(C)
	<=> RO =< MO | fail.
is_stored(C) <=>  true.

% decide whether a constraint is suspends after occurrences
max_occurrence(C,MO), stored_complete(C,RO,_) \ is_finally_stored(C)
	<=> RO =< MO | fail.
is_finally_stored(C) <=>  true.

storage_analysis(Constraints) :-
	( chr_pp_flag(storage_analysis,on) ->
		check_constraint_storages(Constraints)
	;
		true
	).

check_constraint_storages([]).
check_constraint_storages([C|Cs]) :-
	check_constraint_storage(C),
	check_constraint_storages(Cs).

check_constraint_storage(C) :-
	get_max_occurrence(C,MO),
	check_occurrences_storage(C,1,MO).

check_occurrences_storage(C,O,MO) :-
	( O > MO ->
		stored_completing(C,1,0)
	;
		check_occurrence_storage(C,O),
		NO is O + 1,
		check_occurrences_storage(C,NO,MO)
	).

check_occurrence_storage(C,O) :-
	get_occurrence(C,O,RuleNb,ID),
	( is_passive(RuleNb,ID) ->
		stored(C,O,maybe)
	;
		get_rule(RuleNb,PragmaRule),
		PragmaRule = pragma(rule(Heads1,Heads2,Guard,Body),ids(IDs1,IDs2),_,_,_),
		( select2(ID,Head1,IDs1,Heads1,RIDs1,RHeads1) ->
			check_storage_head1(Head1,O,Heads1,Heads2,Guard)
		; select2(ID,Head2,IDs2,Heads2,RIDs2,RHeads2) ->
			check_storage_head2(Head2,O,Heads1,Body)
		)
	).

check_storage_head1(Head,O,H1,H2,G) :-
	functor(Head,F,A),
	C = F/A,
	( H1 == [Head],
	  H2 == [],
%	  guard_entailment:entails_guard([chr_pp_headvariables(Head)],G),
	  entails_guard([chr_pp_headvariables(Head)],G),
	  Head =.. [_|L],
	  no_matching(L,[]) ->
	  	stored(C,O,no)
	;
		stored(C,O,maybe)
	).

no_matching([],_).
no_matching([X|Xs],Prev) :-
	var(X),
	\+ memberchk_eq(X,Prev),
	no_matching(Xs,[X|Prev]).

check_storage_head2(Head,O,H1,B) :-
	functor(Head,F,A),
	C = F/A,
	( ( (H1 \== [], B == true ) ; 
	   \+ is_observed(F/A,O) ) ->
		stored(C,O,maybe)
	;
		stored(C,O,yes)
	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____        _         ____                      _ _       _   _
%% |  _ \ _   _| | ___   / ___|___  _ __ ___  _ __ (_) | __ _| |_(_) ___  _ __
%% | |_) | | | | |/ _ \ | |   / _ \| '_ ` _ \| '_ \| | |/ _` | __| |/ _ \| '_ \
%% |  _ <| |_| | |  __/ | |__| (_) | | | | | | |_) | | | (_| | |_| | (_) | | | |
%% |_| \_\\__,_|_|\___|  \____\___/|_| |_| |_| .__/|_|_|\__,_|\__|_|\___/|_| |_|
%%                                           |_|

constraints_code(Constraints,Clauses) :-
	(chr_pp_flag(reduced_indexing,on), 
		    \+ forsome(C,Constraints,\+ only_ground_indexed_arguments(C)) ->
	    none_suspended_on_variables
	;
	    true
        ),
	constraints_code1(Constraints,L,[]),
	clean_clauses(L,Clauses).

%===============================================================================
:- chr_constraint constraints_code1/3.
:- chr_option(mode,constraints_code1(+,+,+)).
:- chr_option(type_declaration,constraints_code(list,any,any)).
%-------------------------------------------------------------------------------
constraints_code1([],L,T) <=> L = T.
constraints_code1([C|RCs],L,T) 
	<=>
		constraint_code(C,L,T1),
		constraints_code1(RCs,T1,T).
%===============================================================================
:- chr_constraint constraint_code/3.
:- chr_option(mode,constraint_code(+,+,+)).
%-------------------------------------------------------------------------------
%% 	Generate code for a single CHR constraint
constraint_code(Constraint, L, T) 
	<=>	true
	|	( (chr_pp_flag(debugable,on) ;
		  is_stored(Constraint), ( has_active_occurrence(Constraint); chr_pp_flag(late_allocation,off)), 
                  ( may_trigger(Constraint) ; 
		    get_allocation_occurrence(Constraint,AO), 
		    get_max_occurrence(Constraint,MO), MO >= AO ) )
		   ->
			constraint_prelude(Constraint,Clause),
			L = [Clause | L1]
		;
			L = L1
		),
		Id = [0],
		occurrences_code(Constraint,1,Id,NId,L1,L2),
		gen_cond_attach_clause(Constraint,NId,L2,T).

%===============================================================================
%%	Generate prelude predicate for a constraint.
%%	f(...) :- f/a_0(...,Susp).
constraint_prelude(F/A, Clause) :-
	vars_susp(A,Vars,Susp,VarsSusp),
	Head =.. [ F | Vars],
	make_suspension_continuation_goal(F/A,VarsSusp,Continuation),
	build_head(F,A,[0],VarsSusp,Delegate),
	FTerm =.. [F|Vars],
	( chr_pp_flag(debugable,on) ->
		use_auxiliary_predicate(insert_constraint_internal,F/A),
		generate_insert_constraint_call(F/A,Susp,InsertCall),
		make_name('attach_',F/A,AttachF),
		AttachCall =.. [AttachF,Vars2,Susp],
                Inactive = (arg(2,Susp,Mutable), 'chr update_mutable'(inactive,Mutable)),	
		insert_constraint_internal_constraint_goal(F/A, Stored, Vars2, Susp, Continuation, F, Vars,InsertGoal),
		Clause = 
			( Head :-
				InsertGoal, % insert_constraint_internal(Stored,Vars2,Susp,Continuation,F,Vars),
				InsertCall,
				AttachCall,
				Inactive,
			        (   
					'chr debug_event'(call(Susp)),
		   	                Delegate
				;
					'chr debug_event'(fail(Susp)), !,
            				fail
        			),
			        (   
					'chr debug_event'(exit(Susp))
			        ;   
					'chr debug_event'(redo(Susp)),
				        fail
			        )
			)
	; get_allocation_occurrence(F/A,0) ->
		gen_insert_constraint_internal_goal(F/A,Goal,VarsSusp,Vars,Susp),
                Inactive = (arg(2,Susp,Mutable), 'chr update_mutable'(inactive,Mutable)),
		Clause = ( Head  :- Goal, Inactive, Delegate )
	;
		Clause = ( Head  :- Delegate )
	). 

make_suspension_continuation_goal(F/A,VarsSusp,Goal) :-
	( may_trigger(F/A) ->
		get_target_module(Mod),
		build_head(F,A,[0],VarsSusp,Delegate),
		Goal = Delegate
	;
		Goal = true
	).

%===============================================================================
:- chr_constraint has_active_occurrence/1, has_active_occurrence/2.
%-------------------------------------------------------------------------------
has_active_occurrence(C) <=> has_active_occurrence(C,1).

max_occurrence(C,MO) \ has_active_occurrence(C,O) <=>
	O > MO | fail.
passive(RuleNb,ID),occurrence(C,O,RuleNb,ID) \
	has_active_occurrence(C,O) <=>
	NO is O + 1,
	has_active_occurrence(C,NO).
has_active_occurrence(C,O) <=> true.
%===============================================================================

gen_cond_attach_clause(F/A,Id,L,T) :-
	( is_finally_stored(F/A) ->
		get_allocation_occurrence(F/A,AllocationOccurrence),
		get_max_occurrence(F/A,MaxOccurrence),
		( chr_pp_flag(debugable,off), MaxOccurrence < AllocationOccurrence ->
			( only_ground_indexed_arguments(F/A) ->
				gen_insert_constraint_internal_goal(F/A,Body,AllArgs,Args,Susp)
			;
				gen_cond_attach_goal(F/A,Body,AllArgs,Args,Susp)
			)
		; 	vars_susp(A,Args,Susp,AllArgs),
			gen_uncond_attach_goal(F/A,Susp,Body,_)
		),
		( chr_pp_flag(debugable,on) ->
			Constraint =.. [F|Args],
			DebugEvent = 'chr debug_event'(insert(Constraint#Susp))
		;
			DebugEvent = true
		),
		build_head(F,A,Id,AllArgs,Head),
		Clause = ( Head :- DebugEvent,Body ),
		L = [Clause | T]
	;
		L = T
	).	

:- chr_constraint 
	use_auxiliary_predicate/1,
	use_auxiliary_predicate/2,
	is_used_auxiliary_predicate/1,
	is_used_auxiliary_predicate/2.

:- chr_option(mode,use_auxiliary_predicate(+)).
:- chr_option(mode,use_auxiliary_predicate(+,+)).

use_auxiliary_predicate(P) \ use_auxiliary_predicate(P) <=> true.

use_auxiliary_predicate(P,C) \ use_auxiliary_predicate(P,C) <=> true.

use_auxiliary_predicate(P) \ is_used_auxiliary_predicate(P) <=> true.

use_auxiliary_predicate(P,_) \ is_used_auxiliary_predicate(P) <=> true.

is_used_auxiliary_predicate(P) <=> fail.

use_auxiliary_predicate(P) \ is_used_auxiliary_predicate(P,_) <=> true.
use_auxiliary_predicate(P,C) \ is_used_auxiliary_predicate(P,C) <=> true.

is_used_auxiliary_predicate(P,C) <=> fail.


	% only called for constraints with
	% at least one
	% non-ground indexed argument	
gen_cond_attach_goal(F/A,Goal,AllArgs,Args,Susp) :-
	vars_susp(A,Args,Susp,AllArgs),
	make_suspension_continuation_goal(F/A,AllArgs,Closure),
	make_name('attach_',F/A,AttachF),
	Attach =.. [AttachF,Vars,Susp],
	FTerm =.. [F|Args],
	generate_insert_constraint_call(F/A,Susp,InsertCall),
	use_auxiliary_predicate(insert_constraint_internal,F/A),
	insert_constraint_internal_constraint_goal(F/A, Stored, Vars, Susp, Closure, F, Args,InsertGoal),
	use_auxiliary_predicate(activate_constraint,F/A),
	( may_trigger(F/A) ->
		activate_constraint_goal(F/A,Stored,Vars,Susp,_,ActivateGoal),
		Goal =
		(
			( var(Susp) ->
				InsertGoal % insert_constraint_internal(Stored,Vars,Susp,Closure,F,Args)
			; 
				ActivateGoal % activate_constraint(Stored,Vars,Susp,_)
			),
			( Stored == yes ->
				InsertCall,	
				Attach
			;
				true
			)
		)
	;
		Goal =
		(
			InsertGoal, % insert_constraint_internal(Stored,Vars,Susp,Closure,F,Args),
			InsertCall,	
			Attach
		)
	).

gen_insert_constraint_internal_goal(F/A,Goal,AllArgs,Args,Susp) :-
	vars_susp(A,Args,Susp,AllArgs),
	make_suspension_continuation_goal(F/A,AllArgs,Cont),
	( \+ only_ground_indexed_arguments(F/A) ->
		make_name('attach_',F/A,AttachF),
		Attach =.. [AttachF,Vars,Susp]
	;
		Attach = true
	),
	FTerm =.. [F|Args],
	generate_insert_constraint_call(F/A,Susp,InsertCall),
	use_auxiliary_predicate(insert_constraint_internal,F/A),
	insert_constraint_internal_constraint_goal(F/A, _, Vars, Susp, Cont, F, Args,InsertInternalGoal),
	( only_ground_indexed_arguments(F/A), chr_pp_flag(debugable,off) ->
	    Goal =
	    (
		InsertInternalGoal, % insert_constraint_internal(Susp,F,Args),
		InsertCall
	    )
	;
	    Goal =
	    (
		InsertInternalGoal, % insert_constraint_internal(_,Vars,Susp,Cont,F,Args),
		InsertCall,
		Attach
	    )
	).

gen_uncond_attach_goal(FA,Susp,AttachGoal,Generation) :-
	( \+ only_ground_indexed_arguments(FA) ->
		make_name('attach_',FA,AttachF),
		Attach =.. [AttachF,Vars,Susp]
	;
		Attach = true
	),
	generate_insert_constraint_call(FA,Susp,InsertCall),
	( chr_pp_flag(late_allocation,on) ->
	  	use_auxiliary_predicate(activate_constraint,FA),
		activate_constraint_goal(FA,Stored,Vars,Susp,Generation,ActivateGoal),
		AttachGoal =
		(
			ActivateGoal,
			( Stored == yes ->
				InsertCall,
				Attach	
			;
				true
			)
		)
	;
		use_auxiliary_predicate(activate_constraint,FA),
		activate_constraint_goal(FA,Stored,Vars,Susp,Generation,AttachGoal)
		% AttachGoal =
		% (
		% 	activate_constraint(Stored,Vars, Susp, Generation)
		% )
	).

%-------------------------------------------------------------------------------
:- chr_constraint occurrences_code/6.
:- chr_option(mode,occurrences_code(+,+,+,+,+,+)).
%-------------------------------------------------------------------------------
max_occurrence(C,MO) \ occurrences_code(C,O,Id,NId,L,T)
	 <=> 	O > MO 
	|	NId = Id, L = T.
occurrences_code(C,O,Id,NId,L,T) 
	<=>
		occurrence_code(C,O,Id,Id1,L,L1), 
		NO is O + 1,
		occurrences_code(C,NO,Id1,NId,L1,T).
%-------------------------------------------------------------------------------
:- chr_constraint occurrence_code/6.
:- chr_option(mode,occurrence_code(+,+,+,+,+,+)).
%-------------------------------------------------------------------------------
occurrence(C,O,RuleNb,ID), passive(RuleNb,ID) \ occurrence_code(C,O,Id,NId,L,T) 
	<=> 	NId = Id, L = T.
occurrence(C,O,RuleNb,ID), rule(RuleNb,PragmaRule) \ occurrence_code(C,O,Id,NId,L,T)
	<=>	true |  
		PragmaRule = pragma(rule(Heads1,Heads2,_,_),ids(IDs1,IDs2),_,_,_),	
		( select2(ID,Head1,IDs1,Heads1,RIDs1,RHeads1) ->
			NId = Id,
			head1_code(Head1,RHeads1,RIDs1,PragmaRule,C,O,Id,L,T)
		; select2(ID,Head2,IDs2,Heads2,RIDs2,RHeads2) ->
			head2_code(Head2,RHeads2,RIDs2,PragmaRule,C,O,Id,L,L1),
			inc_id(Id,NId),
			( unconditional_occurrence(C,O) ->
				L1 = T
			;
				gen_alloc_inc_clause(C,O,Id,L1,T)
			)
		).

occurrence_code(C,O,_,_,_,_)
	<=>	
		chr_error(internal,'occurrence_code/6: missing information to compile ~w:~w\n',[C,O]).
%-------------------------------------------------------------------------------

%%	Generate code based on one removed head of a CHR rule
head1_code(Head,OtherHeads,OtherIDs,PragmaRule,FA,O,Id,L,T) :-
	PragmaRule = pragma(Rule,_,_,_Name,RuleNb),
	Rule = rule(_,Head2,_,_),
	( Head2 == [] ->
		reorder_heads(RuleNb,Head,OtherHeads,OtherIDs,NOtherHeads,NOtherIDs),
		simplification_code(Head,NOtherHeads,NOtherIDs,PragmaRule,FA,O,Id,L,T)
	;
		simpagation_head1_code(Head,OtherHeads,OtherIDs,PragmaRule,FA,Id,L,T)
	).

%% Generate code based on one persistent head of a CHR rule
head2_code(Head,OtherHeads,OtherIDs,PragmaRule,FA,O,Id,L,T) :-
	PragmaRule = pragma(Rule,_,_,_Name,RuleNb),
	Rule = rule(Head1,_,_,_),
	( Head1 == [] ->
		reorder_heads(RuleNb,Head,OtherHeads,OtherIDs,NOtherHeads,NOtherIDs),
		propagation_code(Head,NOtherHeads,NOtherIDs,Rule,RuleNb,FA,O,Id,L,T)
	;
		simpagation_head2_code(Head,OtherHeads,OtherIDs,PragmaRule,FA,O,Id,L,T) 
	).

gen_alloc_inc_clause(F/A,O,Id,L,T) :-
	vars_susp(A,Vars,Susp,VarsSusp),
	build_head(F,A,Id,VarsSusp,Head),
	inc_id(Id,IncId),
	build_head(F,A,IncId,VarsSusp,CallHead),
	gen_occ_allocation(F/A,O,Vars,Susp,VarsSusp,ConditionalAlloc),
	Clause =
	(
		Head :-
			ConditionalAlloc,
			CallHead
	),
	L = [Clause|T].

gen_cond_allocation(Vars,Susp,FA,VarsSusp,ConstraintAllocationGoal) :-
	gen_allocation(Vars,Susp,FA,VarsSusp,UncondConstraintAllocationGoal),
	ConstraintAllocationGoal =
	( var(Susp) ->
		UncondConstraintAllocationGoal
	;  
		true
	).
gen_allocation(Vars,Susp,F/A,VarsSusp,ConstraintAllocationGoal) :-
	( may_trigger(F/A) ->
		build_head(F,A,[0],VarsSusp,Term),
		get_target_module(Mod),
		Cont = Term
	;
		Cont = true
	),
	FTerm =.. [F|Vars],
	use_auxiliary_predicate(allocate_constraint,F/A),
	allocate_constraint_goal(F/A, Cont, Susp, F, Vars, ConstraintAllocationGoal).

gen_occ_allocation(FA,O,Vars,Susp,VarsSusp,ConstraintAllocationGoal) :-
	get_allocation_occurrence(FA,AO),
	( chr_pp_flag(debugable,off), O == AO ->
		( may_trigger(FA) ->
			gen_cond_allocation(Vars,Susp,FA,VarsSusp,ConstraintAllocationGoal)
		;
			gen_allocation(Vars,Susp,FA,VarsSusp,ConstraintAllocationGoal)
		)
	;
		ConstraintAllocationGoal = true
	).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% Reorders guard goals with respect to partner constraint retrieval goals and
% active constraint. Returns combined partner retrieval + guard goal.

guard_via_reschedule_new(Retrievals,GuardList,Prelude,GuardListSkeleton,LookupSkeleton,GoalSkeleton) :-
	( chr_pp_flag(guard_via_reschedule,on) ->
		guard_via_reschedule_main_new(Retrievals,GuardList,Prelude,GuardListSkeleton,LookupSkeleton,ScheduleSkeleton),
		list2conj(ScheduleSkeleton,GoalSkeleton)
	;
		length(Retrievals,RL), length(LookupSkeleton,RL),
		length(GuardList,GL), length(GuardListSkeleton,GL),
		append(LookupSkeleton,GuardListSkeleton,GoalListSkeleton),
		list2conj(GoalListSkeleton,GoalSkeleton)	
	).
guard_via_reschedule_main_new(PartnerLookups,GuardList,ActiveHead,
	GuardListSkeleton,LookupSkeleton,ScheduleSkeleton) :-
	initialize_unit_dictionary(ActiveHead,Dict),
	maplist(wrap_in_functor(lookup),PartnerLookups,WrappedPartnerLookups),
	maplist(wrap_in_functor(guard),GuardList,WrappedGuardList),
	build_units(WrappedPartnerLookups,WrappedGuardList,Dict,Units),
	dependency_reorder(Units,NUnits),
	wrappedunits2lists(NUnits,IndexedGuardListSkeleton,LookupSkeleton,ScheduleSkeleton),
	sort(IndexedGuardListSkeleton,SortedIndexedGuardListSkeleton),
	snd_of_pairs(SortedIndexedGuardListSkeleton,GuardListSkeleton).

wrap_in_functor(Functor,X,Term) :-
	Term =.. [Functor,X].

wrappedunits2lists([],[],[],[]).
wrappedunits2lists([unit(N,WrappedGoal,_,_)|Units],Gs,Ls,Ss) :-
	Ss = [GoalCopy|TSs],
	( WrappedGoal = lookup(Goal) ->
		Ls = [GoalCopy|TLs],
		Gs = TGs
	; WrappedGoal = guard(Goal) ->
		Gs = [N-GoalCopy|TGs],
		Ls = TLs
	),
	wrappedunits2lists(Units,TGs,TLs,TSs).

guard_splitting(Rule,SplitGuardList) :-
	Rule = rule(H1,H2,Guard,_),
	append(H1,H2,Heads),
	conj2list(Guard,GuardList),
	term_variables(Heads,HeadVars),
	split_off_simple_guard_new(GuardList,HeadVars,GuardPrefix,RestGuardList),
	append(GuardPrefix,[RestGuard],SplitGuardList),
	term_variables(RestGuardList,GuardVars1),
	% variables that are declared to be ground don't need to be locked
	ground_vars(Heads,GroundVars),	
	list_difference_eq(HeadVars,GroundVars,LockableHeadVars),
	intersect_eq(LockableHeadVars,GuardVars1,GuardVars),
	( chr_pp_flag(guard_locks,on),
          bagof(('chr lock'(X)) - ('chr unlock'(X)), (member(X,GuardVars)), LocksUnlocks) ->
		once(pairup(Locks,Unlocks,LocksUnlocks))
	;
		Locks = [],
		Unlocks = []
	),
	list2conj(Locks,LockPhase),
	list2conj(Unlocks,UnlockPhase),
	list2conj(RestGuardList,RestGuard1),
	RestGuard = (LockPhase,(RestGuard1,UnlockPhase)).

guard_body_copies3(Rule,GuardList,VarDict,GuardCopyList,BodyCopy) :-
	Rule = rule(_,_,_,Body),
	my_term_copy(GuardList,VarDict,VarDict2,GuardCopyList),
	my_term_copy(Body,VarDict2,BodyCopy).


split_off_simple_guard_new([],_,[],[]).
split_off_simple_guard_new([G|Gs],VarDict,S,C) :-
	( simple_guard_new(G,VarDict) ->
		S = [G|Ss],
		split_off_simple_guard_new(Gs,VarDict,Ss,C)
	;
		S = [],
		C = [G|Gs]
	).

% simple guard: cheap and benign (does not bind variables)
simple_guard_new(G,Vars) :-
	binds_b(G,BoundVars),
	\+ (( member(V,BoundVars), 
	      memberchk_eq(V,Vars)
	   )).

dependency_reorder(Units,NUnits) :-
	dependency_reorder(Units,[],NUnits).

dependency_reorder([],Acc,Result) :-
	reverse(Acc,Result).

dependency_reorder([Unit|Units],Acc,Result) :-
	Unit = unit(_GID,_Goal,Type,GIDs),
	( Type == fixed ->
		NAcc = [Unit|Acc]
	;
		dependency_insert(Acc,Unit,GIDs,NAcc)
	),
	dependency_reorder(Units,NAcc,Result).

dependency_insert([],Unit,_,[Unit]).
dependency_insert([X|Xs],Unit,GIDs,L) :-
	X = unit(GID,_,_,_),
	( memberchk(GID,GIDs) ->
		L = [Unit,X|Xs]
	;
		L = [X | T],
		dependency_insert(Xs,Unit,GIDs,T)
	).

build_units(Retrievals,Guard,InitialDict,Units) :-
	build_retrieval_units(Retrievals,1,N,InitialDict,Dict,Units,Tail),
	build_guard_units(Guard,N,Dict,Tail).


build_retrieval_units([],N,N,Dict,Dict,L,L).
build_retrieval_units([U|Us],N,M,Dict,NDict,L,T) :-
	term_variables(U,Vs),
	update_unit_dictionary(Vs,N,Dict,Dict1,[],GIDs),
	L = [unit(N,U,fixed,GIDs)|L1], 
	N1 is N + 1,
	build_retrieval_units(Us,N1,M,Dict1,NDict,L1,T).

initialize_unit_dictionary(Term,Dict) :-
	term_variables(Term,Vars),
	pair_all_with(Vars,0,Dict).	

update_unit_dictionary([],_,Dict,Dict,GIDs,GIDs).
update_unit_dictionary([V|Vs],This,Dict,NDict,GIDs,NGIDs) :-
	( lookup_eq(Dict,V,GID) ->
		( (GID == This ; memberchk(GID,GIDs) ) ->
			GIDs1 = GIDs
		;
			GIDs1 = [GID|GIDs]
		),
		Dict1 = Dict
	;
		Dict1 = [V - This|Dict],
		GIDs1 = GIDs
	),
	update_unit_dictionary(Vs,This,Dict1,NDict,GIDs1,NGIDs).

build_guard_units(Guard,N,Dict,Units) :-
	( Guard = [Goal] ->
		Units = [unit(N,Goal,fixed,[])]
	; Guard = [Goal|Goals] ->
		term_variables(Goal,Vs),
		update_unit_dictionary2(Vs,N,Dict,NDict,[],GIDs),
		Units = [unit(N,Goal,movable,GIDs)|RUnits],
		N1 is N + 1,
		build_guard_units(Goals,N1,NDict,RUnits)
	).

update_unit_dictionary2([],_,Dict,Dict,GIDs,GIDs).
update_unit_dictionary2([V|Vs],This,Dict,NDict,GIDs,NGIDs) :-
	( lookup_eq(Dict,V,GID) ->
		( (GID == This ; memberchk(GID,GIDs) ) ->
			GIDs1 = GIDs
		;
			GIDs1 = [GID|GIDs]
		),
		Dict1 = [V - This|Dict]
	;
		Dict1 = [V - This|Dict],
		GIDs1 = GIDs
	),
	update_unit_dictionary2(Vs,This,Dict1,NDict,GIDs1,NGIDs).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____       _     ____                             _   _            
%% / ___|  ___| |_  / ___|  ___ _ __ ___   __ _ _ __ | |_(_) ___ ___ _ 
%% \___ \ / _ \ __| \___ \ / _ \ '_ ` _ \ / _` | '_ \| __| |/ __/ __(_)
%%  ___) |  __/ |_   ___) |  __/ | | | | | (_| | | | | |_| | (__\__ \_ 
%% |____/ \___|\__| |____/ \___|_| |_| |_|\__,_|_| |_|\__|_|\___|___(_)
%%                                                                     
%%  _   _       _                    ___        __                              
%% | | | |_ __ (_) __ _ _   _  ___  |_ _|_ __  / _| ___ _ __ ___ _ __   ___ ___ 
%% | | | | '_ \| |/ _` | | | |/ _ \  | || '_ \| |_ / _ \ '__/ _ \ '_ \ / __/ _ \
%% | |_| | | | | | (_| | |_| |  __/  | || | | |  _|  __/ | |  __/ | | | (_|  __/
%%  \___/|_| |_|_|\__, |\__,_|\___| |___|_| |_|_|  \___|_|  \___|_| |_|\___\___|
%%                   |_|                                                        
:- chr_constraint
	functional_dependency/4,
	get_functional_dependency/4.

:- chr_option(mode,functional_dependency(+,+,?,?)).

allocation_occurrence(C,AO), occurrence(C,O,RuleNb,_) \ functional_dependency(C,RuleNb,Pattern,Key)
	<=>
		RuleNb > 1, AO > O
	|
		functional_dependency(C,1,Pattern,Key).

functional_dependency(C,RuleNb1,Pattern,Key) \ get_functional_dependency(C,RuleNb2,QPattern,QKey)
	<=> 
		RuleNb2 >= RuleNb1
	|
		QPattern = Pattern, QKey = Key.
get_functional_dependency(_,_,_,_)
	<=>
		fail.

functional_dependency_analysis(Rules) :-
		( chr_pp_flag(functional_dependency_analysis,on) ->
			functional_dependency_analysis_main(Rules)
		;
			true
		).

functional_dependency_analysis_main([]).
functional_dependency_analysis_main([PRule|PRules]) :-
	( discover_unique_pattern(PRule,C,RuleNb,Pattern,Key) ->
		functional_dependency(C,RuleNb,Pattern,Key)
	;
		true
	),
	functional_dependency_analysis_main(PRules).

discover_unique_pattern(PragmaRule,F/A,RuleNb,Pattern,Key) :-
	PragmaRule = pragma(Rule,_,_,Name,RuleNb),
	Rule = rule(H1,H2,Guard,_),
	( H1 = [C1],
	  H2 = [C2] ->
		true
	; H1 = [C1,C2],
	  H2 == [] ->
		true
	),
	check_unique_constraints(C1,C2,Guard,RuleNb,List),
	term_variables(C1,Vs),
	\+ ( 
		member(V1,Vs),
		lookup_eq(List,V1,V2),
		memberchk_eq(V2,Vs)
	),
	select_pragma_unique_variables(Vs,List,Key1),
	copy_term_nat(C1-Key1,Pattern-Key),
	functor(C1,F,A).
	
select_pragma_unique_variables([],_,[]).
select_pragma_unique_variables([V|Vs],List,L) :-
	( lookup_eq(List,V,_) ->
		L = T
	;
		L = [V|T]
	),
	select_pragma_unique_variables(Vs,List,T).

	% depends on functional dependency analysis
	% and shape of rule: C1 \ C2 <=> true.
set_semantics_rules(Rules) :-
	( chr_pp_flag(set_semantics_rule,on) ->
		set_semantics_rules_main(Rules)
	;
		true
	).

set_semantics_rules_main([]).
set_semantics_rules_main([R|Rs]) :-
	set_semantics_rule_main(R),
	set_semantics_rules_main(Rs).

set_semantics_rule_main(PragmaRule) :-
	PragmaRule = pragma(Rule,IDs,Pragmas,_,RuleNb),
	( Rule = rule([C1],[C2],true,_),
	  IDs = ids([ID1],[ID2]),
	  \+ is_passive(RuleNb,ID1),
	  functor(C1,F,A),
	  get_functional_dependency(F/A,RuleNb,Pattern,Key),
	  copy_term_nat(Pattern-Key,C1-Key1),
	  copy_term_nat(Pattern-Key,C2-Key2),
	  Key1 == Key2 ->
		passive(RuleNb,ID2)
	;
		true
	).

check_unique_constraints(C1,C2,G,RuleNb,List) :-
	\+ any_passive_head(RuleNb),
	variable_replacement(C1-C2,C2-C1,List),
	copy_with_variable_replacement(G,OtherG,List),
	negate_b(G,NotG),
	once(entails_b(NotG,OtherG)).

	% checks for rules of the shape ...,C1,C2... (<|=)==> ...
	% where C1 and C2 are symmteric constraints
symmetry_analysis(Rules) :-
	( chr_pp_flag(check_unnecessary_active,off) ->
		true
	;
		symmetry_analysis_main(Rules)
	).

symmetry_analysis_main([]).
symmetry_analysis_main([R|Rs]) :-
	R = pragma(Rule,ids(IDs1,IDs2),_,_,RuleNb),
	Rule = rule(H1,H2,_,_),
	( ( \+ chr_pp_flag(check_unnecessary_active,simplification)
	  ; H2 == [] ), H1 \== [] ->
		symmetry_analysis_heads(H1,IDs1,[],[],Rule,RuleNb),
		symmetry_analysis_heads(H2,IDs2,[],[],Rule,RuleNb)
	;
		true
	),	 
	symmetry_analysis_main(Rs).

symmetry_analysis_heads([],[],_,_,_,_).
symmetry_analysis_heads([H|Hs],[ID|IDs],PreHs,PreIDs,Rule,RuleNb) :-
	( \+ is_passive(RuleNb,ID),
	  member2(PreHs,PreIDs,PreH-PreID),
	  \+ is_passive(RuleNb,PreID),
	  variable_replacement(PreH,H,List),
	  copy_with_variable_replacement(Rule,Rule2,List),
	  identical_rules(Rule,Rule2) ->
		passive(RuleNb,ID)
	;
		true
	),
	symmetry_analysis_heads(Hs,IDs,[H|PreHs],[ID|PreIDs],Rule,RuleNb).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____  _                 _ _  __ _           _   _
%% / ___|(_)_ __ ___  _ __ | (_)/ _(_) ___ __ _| |_(_) ___  _ __
%% \___ \| | '_ ` _ \| '_ \| | | |_| |/ __/ _` | __| |/ _ \| '_ \
%%  ___) | | | | | | | |_) | | |  _| | (_| (_| | |_| | (_) | | | |
%% |____/|_|_| |_| |_| .__/|_|_|_| |_|\___\__,_|\__|_|\___/|_| |_|
%%                   |_| 

simplification_code(Head,RestHeads,RestIDs,PragmaRule,F/A,O,Id,L,T) :-
	PragmaRule = pragma(Rule,_,Pragmas,_,_RuleNb),
	head_info(Head,A,_Vars,Susp,HeadVars,HeadPairs),
	build_head(F,A,Id,HeadVars,ClauseHead),
	get_constraint_mode(F/A,Mode),

	head_arg_matches(HeadPairs,Mode,[],FirstMatching,VarDict1,[],GroundVars),
	
	guard_splitting(Rule,GuardList),
	guard_via_reschedule_new(RestHeads,GuardList,Head,GuardCopyList,GetRestHeads,RescheduledTest),	

	rest_heads_retrieval_and_matching(RestHeads,RestIDs,Head,GetRestHeads,Susps,VarDict1,VarDict,[],[],[],GroundVars,_),
	
	guard_body_copies3(Rule,GuardList,VarDict,GuardCopyList,BodyCopy),
	
	gen_uncond_susps_detachments(Susps,RestHeads,SuspsDetachments),
	gen_cond_susp_detachment(Id,Susp,F/A,SuspDetachment),

	( chr_pp_flag(debugable,on) ->
		Rule = rule(_,_,Guard,Body),
		my_term_copy(Guard - Body, VarDict, DebugGuard - DebugBody),		
		DebugTry   = 'chr debug_event'(  try([Susp|RestSusps],[],DebugGuard,DebugBody)),
		DebugApply = 'chr debug_event'(apply([Susp|RestSusps],[],DebugGuard,DebugBody)),
		instrument_goal(ActualCut,DebugTry,DebugApply,Cut)
	;
		Cut = ActualCut
	),
	( unconditional_occurrence(F/A,O), chr_pp_flag(late_allocation,on) -> ActualCut = true ; ActualCut = (!) ),	
	Clause = ( ClauseHead :-
			FirstMatching, 
		     RescheduledTest,
	             Cut,
	             SuspsDetachments,
	             SuspDetachment,
	             BodyCopy
	         ),
	L = [Clause | T].

head_arg_matches(Pairs,Modes,VarDict,Goal,NVarDict) :-
	head_arg_matches(Pairs,Modes,VarDict,Goal,NVarDict,[],_).

head_arg_matches(Pairs,Modes,VarDict,Goal,NVarDict,GroundVars,NGroundVars) :-
	head_arg_matches_(Pairs,Modes,VarDict,GroundVars,GoalList,NVarDict,NGroundVars),
	list2conj(GoalList,Goal).
 
head_arg_matches_([],[],VarDict,GroundVars,[],VarDict,GroundVars).
head_arg_matches_([Arg-Var| Rest],[Mode|Modes],VarDict,GroundVars,GoalList,NVarDict,NGroundVars) :-
   (   var(Arg) ->
       ( lookup_eq(VarDict,Arg,OtherVar) ->
	   ( Mode = (+) ->
		( memberchk_eq(Arg,GroundVars) ->
			GoalList = [Var = OtherVar | RestGoalList],
			GroundVars1 = GroundVars
		;
			GoalList = [Var == OtherVar | RestGoalList],
			GroundVars1 = [Arg|GroundVars]
		)
	   ;
           	GoalList = [Var == OtherVar | RestGoalList],
		GroundVars1 = GroundVars
	   ),
           VarDict1 = VarDict
       ;   VarDict1 = [Arg-Var | VarDict],
           GoalList = RestGoalList,
	   ( Mode = (+) ->
	   	GroundVars1 = [Arg|GroundVars]
	   ;
		GroundVars1 = GroundVars
	   )
       ),
       Pairs = Rest,
       RestModes = Modes	
   ;   atomic(Arg) ->
       ( Mode = (+) ->
	       GoalList = [ Var = Arg | RestGoalList]	
       ;
	       GoalList = [ Var == Arg | RestGoalList]
       ),
       VarDict = VarDict1,
       GroundVars1 = GroundVars,
       Pairs = Rest,
       RestModes = Modes
   ;   Mode == (+), is_ground(GroundVars,Arg)  -> 
       copy_with_variable_replacement(Arg,ArgCopy,VarDict),
       GoalList = [ Var = ArgCopy | RestGoalList],	
       VarDict = VarDict1,
       GroundVars1 = GroundVars,
       Pairs = Rest,
       RestModes = Modes
   ;   Arg =.. [_|Args],
       functor(Arg,Fct,N),
       functor(Term,Fct,N),
       Term =.. [_|Vars],
       ( Mode = (+) ->
		GoalList = [ Var = Term | RestGoalList ] 
       ;
		GoalList = [ nonvar(Var), Var = Term | RestGoalList ] 
       ),
       pairup(Args,Vars,NewPairs),
       append(NewPairs,Rest,Pairs),
       replicate(N,Mode,NewModes),
       append(NewModes,Modes,RestModes),
       VarDict1 = VarDict,
       GroundVars1 = GroundVars
   ),
   head_arg_matches_(Pairs,RestModes,VarDict1,GroundVars1,RestGoalList,NVarDict,NGroundVars).

is_ground(GroundVars,Term) :-
	( ground(Term) -> 
		true
	; compound(Term) ->
		Term =.. [_|Args],
		maplist(is_ground(GroundVars),Args)
	;
		memberchk_eq(Term,GroundVars)
	).

rest_heads_retrieval_and_matching(Heads,IDs,ActiveHead,GoalList,Susps,VarDict,NVarDict,PrevHs,PrevSusps,AttrDict) :-
	rest_heads_retrieval_and_matching(Heads,IDs,ActiveHead,GoalList,Susps,VarDict,NVarDict,PrevHs,PrevSusps,AttrDict,[],_).

rest_heads_retrieval_and_matching(Heads,IDs,ActiveHead,GoalList,Susps,VarDict,NVarDict,PrevHs,PrevSusps,AttrDict,GroundVars,NGroundVars) :-
	( Heads = [_|_] ->
		rest_heads_retrieval_and_matching_n(Heads,IDs,PrevHs,PrevSusps,ActiveHead,GoalList,Susps,VarDict,NVarDict,AttrDict,GroundVars,NGroundVars)	
	;
		GoalList = [],
		Susps = [],
		VarDict = NVarDict,
		GroundVars = NGroundVars
	).

rest_heads_retrieval_and_matching_n([],_,_,_,_,[],[],VarDict,VarDict,_AttrDict,GroundVars,GroundVars).
rest_heads_retrieval_and_matching_n([H|Hs],[ID|IDs],PrevHs,PrevSusps,ActiveHead,
    [Goal|Goals],[Susp|Susps],VarDict,NVarDict,_AttrDict,GroundVars,NGroundVars) :-
	functor(H,F,A),
	head_info(H,A,Vars,_,_,Pairs),
	get_store_type(F/A,StoreType),
	( StoreType == default ->
		passive_head_via(H,[ActiveHead|PrevHs],VarDict,ViaGoal,VarSusps),
		create_get_mutable_ref(active,State,GetMutable),
		get_constraint_mode(F/A,Mode),
		head_arg_matches(Pairs,Mode,VarDict,MatchingGoal,VarDict1,GroundVars,GroundVars1),
		NPairs = Pairs,
		sbag_member_call(Susp,VarSusps,Sbag),
		ExistentialLookup = 	(
						ViaGoal,
						Sbag,
						Susp = Suspension,		% not inlined
						GetMutable
					)
	;
		existential_lookup(StoreType,H,[ActiveHead|PrevHs],VarDict,Suspension,State,ExistentialLookup,Susp,Pairs,NPairs),
		get_constraint_mode(F/A,Mode),
		filter_mode(NPairs,Pairs,Mode,NMode),
		head_arg_matches(NPairs,NMode,VarDict,MatchingGoal,VarDict1,GroundVars,GroundVars1)
	),
	delay_phase_end(validate_store_type_assumptions,
		( static_suspension_term(F/A,Suspension),
		  get_static_suspension_term_field(state,F/A,Suspension,State),
		  get_static_suspension_term_field(arguments,F/A,Suspension,Vars)
		)
	),
	different_from_other_susps(H,Susp,PrevHs,PrevSusps,DiffSuspGoals),
	append(NPairs,VarDict1,DA_),		% order important here
	translate(GroundVars1,DA_,GroundVarsA),
	translate(GroundVars1,VarDict1,GroundVarsB),
	inline_matching_goal(MatchingGoal,MatchingGoal2,GroundVarsA,GroundVarsB),
	Goal = 
	(
		ExistentialLookup,
		DiffSuspGoals,
		MatchingGoal2
	),
	rest_heads_retrieval_and_matching_n(Hs,IDs,[H|PrevHs],[Susp|PrevSusps],ActiveHead,Goals,Susps,VarDict1,NVarDict,_NewAttrDict,GroundVars1,NGroundVars).

inline_matching_goal(A==B,true,GVA,GVB) :- 
    memberchk_eq(A,GVA),
    memberchk_eq(B,GVB),
    A=B, !.
    
    
inline_matching_goal(A=B,true,_,_) :- A=B, !.
inline_matching_goal((A,B),(A2,B2),GVA,GVB) :- !,
    inline_matching_goal(A,A2,GVA,GVB),
    inline_matching_goal(B,B2,GVA,GVB).
inline_matching_goal(X,X,_,_).


filter_mode([],_,_,[]).
filter_mode([Arg-Var|Rest],[_-V|R],[M|Ms],Modes) :-
	( Var == V ->
		Modes = [M|MT],
		filter_mode(Rest,R,Ms,MT)
	;
		filter_mode([Arg-Var|Rest],R,Ms,Modes)
	).

check_unique_keys([],_).
check_unique_keys([V|Vs],Dict) :-
	lookup_eq(Dict,V,_),
	check_unique_keys(Vs,Dict).

% Generates tests to ensure the found constraint differs from previously found constraints
%	TODO: detect more cases where constraints need be different
different_from_other_susps(Head,Susp,Heads,Susps,DiffSuspGoals) :-
	different_from_other_susps_(Heads,Susps,Head,Susp,DiffSuspGoalList),
	list2conj(DiffSuspGoalList,DiffSuspGoals).

different_from_other_susps_(_,[],_,_,[]) :- !.
different_from_other_susps_([PreHead|Heads],[PreSusp|Susps],Head,Susp,List) :-
	( functor(Head,F,A), functor(PreHead,F,A),
          copy_term_nat(PreHead-Head,PreHeadCopy-HeadCopy),
	  \+ \+ PreHeadCopy = HeadCopy ->

		List = [Susp \== PreSusp | Tail]
	;
		List = Tail
	),
	different_from_other_susps_(Heads,Susps,Head,Susp,Tail).

% passive_head_via(in,in,in,in,out,out,out) :-
passive_head_via(Head,PrevHeads,VarDict,Goal,AllSusps) :-
	functor(Head,F,A),
	get_constraint_index(F/A,Pos),
	common_variables(Head,PrevHeads,CommonVars),
	translate(CommonVars,VarDict,Vars),
      	global_list_store_name(F/A,Name),
       	GlobalGoal = nb_getval(Name,AllSusps),
	( Vars == [] ->
		Goal = GlobalGoal
	; 
		gen_get_mod_constraints(F/A,Vars,ViaGoal,AttrGoal,AllSusps),
		Goal = 
		( ViaGoal ->
			AttrGoal
		;
			GlobalGoal
		)
	).
 
common_variables(T,Ts,Vs) :-
	term_variables(T,V1),
	term_variables(Ts,V2),
	intersect_eq(V1,V2,Vs).

gen_get_mod_constraints(FA,Vars,ViaGoal,AttrGoal,AllSusps) :-
	get_target_module(Mod),
        ( Vars = [A] ->
        	ViaGoal =  'chr newvia_1'(A,V)
       	; Vars = [A,B] ->
               	ViaGoal = 'chr newvia_2'(A,B,V)
        ;   
		ViaGoal = 'chr newvia'(Vars,V)
       	),
       	AttrGoal =
       	(   get_attr(V,Mod,TSusps),
	    TSuspsEqSusps % TSusps = Susps
       	),
	get_max_constraint_index(N),
	( N == 1 ->
	    	TSuspsEqSusps = true, % TSusps = Susps
		AllSusps = TSusps
	;
		TSuspsEqSusps = (TSusps = Susps),
		get_constraint_index(FA,Pos),
		make_attr(N,_,SuspsList,Susps),
		nth(Pos,SuspsList,AllSusps)
	).

guard_body_copies(Rule,VarDict,GuardCopy,BodyCopy) :-
	guard_body_copies2(Rule,VarDict,GuardCopyList,BodyCopy),
	list2conj(GuardCopyList,GuardCopy).

guard_body_copies2(Rule,VarDict,GuardCopyList,BodyCopy) :-
	Rule = rule(H,_,Guard,Body),
	conj2list(Guard,GuardList),
	split_off_simple_guard(GuardList,VarDict,GuardPrefix,RestGuardList),
	my_term_copy(GuardPrefix-RestGuardList,VarDict,VarDict2,GuardPrefixCopy-RestGuardListCopyCore),

	append(GuardPrefixCopy,[RestGuardCopy],GuardCopyList),
	term_variables(RestGuardList,GuardVars),
	term_variables(RestGuardListCopyCore,GuardCopyVars),
	% variables that are declared to be ground don't need to be locked
	ground_vars(H,GroundVars),	
	list_difference_eq(GuardVars,GroundVars,GuardVars_),
	( chr_pp_flag(guard_locks,on),
          bagof(('chr lock'(Y)) - ('chr unlock'(Y)),
                X ^ (member(X,GuardVars),		% X is a variable appearing in the original guard
                     pairlist:lookup_eq(VarDict,X,Y),            % translate X into new variable
                     memberchk_eq(Y,GuardCopyVars)      % redundant check? or multiple entries for X possible?
                    ),
                LocksUnlocks) ->
		once(pairup(Locks,Unlocks,LocksUnlocks))
	;
		Locks = [],
		Unlocks = []
	),
	list2conj(Locks,LockPhase),
	list2conj(Unlocks,UnlockPhase),
	list2conj(RestGuardListCopyCore,RestGuardCopyCore),
	RestGuardCopy = (LockPhase,(RestGuardCopyCore,UnlockPhase)),
	my_term_copy(Body,VarDict2,BodyCopy).


split_off_simple_guard([],_,[],[]).
split_off_simple_guard([G|Gs],VarDict,S,C) :-
	( simple_guard(G,VarDict) ->
		S = [G|Ss],
		split_off_simple_guard(Gs,VarDict,Ss,C)
	;
		S = [],
		C = [G|Gs]
	).

% simple guard: cheap and benign (does not bind variables)
simple_guard(G,VarDict) :-
	binds_b(G,Vars),
	\+ (( member(V,Vars), 
	     lookup_eq(VarDict,V,_)
	   )).

gen_cond_susp_detachment(Id,Susp,FA,SuspDetachment) :-
	( is_stored(FA) ->
		( (Id == [0]; 
		  (get_allocation_occurrence(FA,AO),
		   get_max_occurrence(FA,MO), 
		   MO < AO )), 
		  only_ground_indexed_arguments(FA), chr_pp_flag(late_allocation,on) ->
			SuspDetachment = true
		;
			gen_uncond_susp_detachment(Susp,FA,UnCondSuspDetachment),
			( chr_pp_flag(late_allocation,on) ->
				SuspDetachment = 
				(   var(Susp) ->
				    true
				;   UnCondSuspDetachment
				)
			;
				SuspDetachment = UnCondSuspDetachment
			)
		)
	;
	        SuspDetachment = true
	).

gen_uncond_susp_detachment(Susp,FA,SuspDetachment) :-
   ( is_stored(FA) ->
	( \+ only_ground_indexed_arguments(FA) ->
		make_name('detach_',FA,Fct),
		Detach =.. [Fct,Vars,Susp]
	;
		Detach = true
	),
	( chr_pp_flag(debugable,on) ->
		DebugEvent = 'chr debug_event'(remove(Susp))
	;
		DebugEvent = true
	),
	generate_delete_constraint_call(FA,Susp,DeleteCall),
	use_auxiliary_predicate(remove_constraint_internal,FA),
	remove_constraint_goal(FA,Susp,Vars,Delete,RemoveInternalGoal),
	( only_ground_indexed_arguments(FA) -> % are_none_suspended_on_variables ->
	    SuspDetachment = 
	    (
		DebugEvent,
		RemoveInternalGoal,
		( Delete = yes -> 
			DeleteCall,
			Detach
		;
			true
		)
	    )
	;
	    SuspDetachment = 
	    (
		DebugEvent,
		RemoveInternalGoal,
		( Delete == yes ->
			DeleteCall,
			Detach
		;
			true
		)
	    )
	)
   ;
	SuspDetachment = true
   ).

gen_uncond_susps_detachments([],[],true).
gen_uncond_susps_detachments([Susp|Susps],[Term|Terms],(SuspDetachment,SuspsDetachments)) :-
   functor(Term,F,A),
   gen_uncond_susp_detachment(Susp,F/A,SuspDetachment),
   gen_uncond_susps_detachments(Susps,Terms,SuspsDetachments).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____  _                                   _   _               _
%% / ___|(_)_ __ ___  _ __   __ _  __ _  __ _| |_(_) ___  _ __   / |
%% \___ \| | '_ ` _ \| '_ \ / _` |/ _` |/ _` | __| |/ _ \| '_ \  | |
%%  ___) | | | | | | | |_) | (_| | (_| | (_| | |_| | (_) | | | | | |
%% |____/|_|_| |_| |_| .__/ \__,_|\__, |\__,_|\__|_|\___/|_| |_| |_|
%%                   |_|          |___/

simpagation_head1_code(Head,RestHeads,OtherIDs,PragmaRule,F/A,Id,L,T) :-
   	PragmaRule = pragma(Rule,ids(_,Heads2IDs),Pragmas,_Name,_RuleNb),
   	Rule = rule(_Heads,Heads2,Guard,Body),

   	head_info(Head,A,_Vars,Susp,HeadVars,HeadPairs),
   	get_constraint_mode(F/A,Mode),
   	head_arg_matches(HeadPairs,Mode,[],FirstMatching,VarDict1,[],GroundVars),

   	build_head(F,A,Id,HeadVars,ClauseHead),

   	append(RestHeads,Heads2,Heads),
   	append(OtherIDs,Heads2IDs,IDs),
   	reorder_heads(RuleNb,Head,Heads,IDs,NHeads,NIDs),
   
	guard_splitting(Rule,GuardList),
	guard_via_reschedule_new(NHeads,GuardList,Head,GuardCopyList,GetRestHeads,RescheduledTest),	

	rest_heads_retrieval_and_matching(NHeads,NIDs,Head,GetRestHeads,Susps,VarDict1,VarDict,[],[],[],GroundVars,_),
   split_by_ids(NIDs,Susps,OtherIDs,Susps1,Susps2), 

   guard_body_copies3(Rule,GuardList,VarDict,GuardCopyList,BodyCopy),

   gen_uncond_susps_detachments(Susps1,RestHeads,SuspsDetachments),
   gen_cond_susp_detachment(Id,Susp,F/A,SuspDetachment),
   
	( chr_pp_flag(debugable,on) ->
		my_term_copy(Guard - Body, VarDict, DebugGuard - DebugBody),		
		DebugTry   = 'chr debug_event'(  try([Susp|Susps1],Susps2,DebugGuard,DebugBody)),
		DebugApply = 'chr debug_event'(apply([Susp|Susps1],Susps2,DebugGuard,DebugBody)),
		instrument_goal((!),DebugTry,DebugApply,Cut)
	;
		Cut = (!)
	),

   Clause = ( ClauseHead :-
		FirstMatching, 
		RescheduledTest,
		Cut,
                SuspsDetachments,
                SuspDetachment,
                BodyCopy
            ),
   L = [Clause | T].

split_by_ids([],[],_,[],[]).
split_by_ids([I|Is],[S|Ss],I1s,S1s,S2s) :-
	( memberchk_eq(I,I1s) ->
		S1s = [S | R1s],
		S2s = R2s
	;
		S1s = R1s,
		S2s = [S | R2s]
	),
	split_by_ids(Is,Ss,I1s,R1s,R2s).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____  _                                   _   _               ____
%% / ___|(_)_ __ ___  _ __   __ _  __ _  __ _| |_(_) ___  _ __   |___ \
%% \___ \| | '_ ` _ \| '_ \ / _` |/ _` |/ _` | __| |/ _ \| '_ \    __) |
%%  ___) | | | | | | | |_) | (_| | (_| | (_| | |_| | (_) | | | |  / __/
%% |____/|_|_| |_| |_| .__/ \__,_|\__, |\__,_|\__|_|\___/|_| |_| |_____|
%%                   |_|          |___/

%% Genereate prelude + worker predicate
%% prelude calls worker
%% worker iterates over one type of removed constraints
simpagation_head2_code(Head2,RestHeads2,RestIDs,PragmaRule,FA,O,Id,L,T) :-
   PragmaRule = pragma(Rule,ids(IDs1,IDs2),Pragmas,_Name,RuleNb),
   Rule = rule(Heads1,_,Guard,Body),
   append(Heads1,RestHeads2,Heads),
   append(IDs1,RestIDs,IDs),
   reorder_heads(RuleNb,Head2,Heads,IDs,[NHead|NHeads],[NID|NIDs]),
   simpagation_head2_prelude(Head2,NHead,[NHeads,Guard,Body],FA,O,Id,L,L1),
   extend_id(Id,Id1),
   ( memberchk_eq(NID,IDs2) ->
        simpagation_universal_searches(NHeads,NIDs,IDs2,[NHead,Head2],Rule,FA,NextHeads,PreHeads,NextIDs,Id1,Id2,L1,L2)
   ;
	L1 = L2, Id1 = Id2,NextHeads = NHeads, PreHeads = [NHead,Head2], NextIDs = NIDs
   ),
   universal_search_iterator_end(PreHeads,NextHeads,Rule,FA,Id2,L2,L3),
   simpagation_head2_new_worker(PreHeads,NextHeads,NextIDs,PragmaRule,FA,O,Id2,L3,T).

simpagation_universal_searches([],[],_,PreHeads,_,_,[],PreHeads,[],Id,Id,L,L).
simpagation_universal_searches(Heads,[ID|IDs],IDs2,PreHeads,Rule,C,OutHeads,OutPreHeads,OutIDs,Id,NId,L,T) :-
	Heads = [Head|RHeads],
	inc_id(Id,Id1),
	universal_search_iterator_end(PreHeads,Heads,Rule,C,Id,L,L0),
	universal_search_iterator(Heads,PreHeads,Rule,C,Id,L0,L1),
	( memberchk_eq(ID,IDs2) ->
		simpagation_universal_searches(RHeads,IDs,IDs2,[Head|PreHeads],Rule,C,OutHeads,OutPreHeads,OutIDs,Id1,NId,L1,T)
	;
		NId = Id1, L1 = T, OutHeads = RHeads, OutPreHeads = [Head|PreHeads], IDs = OutIDs
	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
simpagation_head2_prelude(Head,Head1,Rest,F/A,O,Id1,L,T) :-
	head_info(Head,A,Vars,Susp,VarsSusp,HeadPairs),
	build_head(F,A,Id1,VarsSusp,ClauseHead),
	get_constraint_mode(F/A,Mode),
	head_arg_matches(HeadPairs,Mode,[],FirstMatching,VarDict),

	lookup_passive_head(Head1,[Head],VarDict,ModConstraintsGoal,AllSusps),

	gen_occ_allocation(F/A,O,Vars,Susp,VarsSusp,ConstraintAllocationGoal),

	extend_id(Id1,DelegateId),
	extra_active_delegate_variables(Head,[Head1|Rest],VarDict,ExtraVars),
	append([AllSusps|VarsSusp],ExtraVars,DelegateCallVars),
	build_head(F,A,DelegateId,DelegateCallVars,Delegate),

	PreludeClause = 
	   ( ClauseHead :-
	          FirstMatching,
	          ModConstraintsGoal,
	          !,
	          ConstraintAllocationGoal,
	          Delegate
	   ),
	L = [PreludeClause|T].

extra_active_delegate_variables(Term,Terms,VarDict,Vars) :-
	Term =.. [_|Args],
	delegate_variables(Term,Terms,VarDict,Args,Vars).

passive_delegate_variables(Term,PrevTerms,NextTerms,VarDict,Vars) :-
	term_variables(PrevTerms,PrevVars),
	delegate_variables(Term,NextTerms,VarDict,PrevVars,Vars).

delegate_variables(Term,Terms,VarDict,PrevVars,Vars) :-
	term_variables(Term,V1),
	term_variables(Terms,V2),
	intersect_eq(V1,V2,V3),
	list_difference_eq(V3,PrevVars,V4),
	translate(V4,VarDict,Vars).
	
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
simpagation_head2_new_worker([CurrentHead|PreHeads],NextHeads,NextIDs,PragmaRule,F/A,O,Id,L,T) :-
	   PragmaRule = pragma(Rule,ids(IDs1,_),Pragmas,_,RuleNb), 
	   Rule = rule(_,_,Guard,Body),
	   get_prop_inner_loop_vars(PreHeads,[CurrentHead,NextHeads,Guard,Body],PreVarsAndSusps,VarDict,Susp,PreSusps),
	
	   gen_var(OtherSusp),
	   gen_var(OtherSusps),
	
	   functor(CurrentHead,OtherF,OtherA),
	   gen_vars(OtherA,OtherVars),
	   head_info(CurrentHead,OtherA,OtherVars,OtherSusp,_VarsSusp,HeadPairs),
	   get_constraint_mode(OtherF/OtherA,Mode),
	   head_arg_matches(HeadPairs,Mode,VarDict,FirstMatching,VarDict1,[],GroundVars),
	
	% BEGIN NEW - Customizable suspension term layout	   
	%  OtherSuspension =.. [suspension,_,State,_,_,_,_|OtherVars],
	delay_phase_end(validate_store_type_assumptions,
		( static_suspension_term(OtherF/OtherA,OtherSuspension),
		  get_static_suspension_term_field(state,OtherF/OtherA,OtherSuspension,State),
		  get_static_suspension_term_field(arguments,OtherF/OtherA,OtherSuspension,OtherVars)
		)
	),
	% END NEW
	different_from_other_susps(CurrentHead,OtherSusp,PreHeads,PreSusps,DiffSuspGoals),
	create_get_mutable_ref(active,State,GetMutable),
	CurrentSuspTest = (
	   OtherSusp = OtherSuspension,
	   GetMutable,
	   DiffSuspGoals,
	   FirstMatching
	),
	
	ClauseVars = [[OtherSusp|OtherSusps]|PreVarsAndSusps],
	build_head(F,A,Id,ClauseVars,ClauseHead),
	
	guard_splitting(Rule,GuardList),
	guard_via_reschedule_new(NextHeads,GuardList,[CurrentHead|PreHeads],GuardCopyList,RestSuspsRetrieval,RescheduledTest),	

	rest_heads_retrieval_and_matching(NextHeads,NextIDs,[CurrentHead|PreHeads],RestSuspsRetrieval,Susps,VarDict1,VarDict2,[CurrentHead|PreHeads],[OtherSusp|PreSusps],[]),
	split_by_ids(NextIDs,Susps,IDs1,Susps1,Susps2),
	split_by_ids(NextIDs,NextHeads,IDs1,RestHeads1,_),
	
	gen_uncond_susps_detachments([OtherSusp | Susps1],[CurrentHead|RestHeads1],Susps1Detachments),
	
	RecursiveVars = [OtherSusps|PreVarsAndSusps],
	build_head(F,A,Id,RecursiveVars,RecursiveCall),
	RecursiveVars2 = [[]|PreVarsAndSusps],
	build_head(F,A,Id,RecursiveVars2,RecursiveCall2),
	
	guard_body_copies3(Rule,GuardList,VarDict2,GuardCopyList,BodyCopy),
	(   BodyCopy \== true, is_observed(F/A,O) ->
	    gen_uncond_attach_goal(F/A,Susp,Attachment,Generation),
	    gen_state_cond_call(Susp,F/A,RecursiveCall,Generation,ConditionalRecursiveCall),
	    gen_state_cond_call(Susp,F/A,RecursiveCall2,Generation,ConditionalRecursiveCall2)
	;   Attachment = true,
	    ConditionalRecursiveCall = RecursiveCall,
	    ConditionalRecursiveCall2 = RecursiveCall2
	),
	
	( chr_pp_flag(debugable,on) ->
		my_term_copy(Guard - Body, VarDict, DebugGuard - DebugBody),		
		DebugTry   = 'chr debug_event'(  try([OtherSusp|Susps1],[Susp|Susps2],DebugGuard,DebugBody)),
		DebugApply = 'chr debug_event'(apply([OtherSusp|Susps1],[Susp|Susps2],DebugGuard,DebugBody))
	;
		DebugTry = true,
		DebugApply = true
	),
	
	( member(unique(ID1,UniqueKeys), Pragmas),
	  check_unique_keys(UniqueKeys,VarDict) ->
	     Clause =
	     	( ClauseHead :-
	     		( CurrentSuspTest ->
	     			( RescheduledTest,
	     			  DebugTry ->
	     				DebugApply,
	     				Susps1Detachments,
	     				Attachment,
	     				BodyCopy,
	     				ConditionalRecursiveCall2
	     			;
	     				RecursiveCall2
	     			)
	     		;
	     			RecursiveCall
	     		)
	     	)
	 ;
	     Clause =
	   		( ClauseHead :-
	          		( CurrentSuspTest,
	     		  RescheduledTest,
	     		  DebugTry ->
	     			DebugApply,
	     			Susps1Detachments,
	     			Attachment,
	     			BodyCopy,
	     			ConditionalRecursiveCall
	     		;
	     			RecursiveCall
	     		)
	     	)
	),
	L = [Clause | T].

gen_state_cond_call(Susp,FA,Call,Generation,ConditionalCall) :-
	% BEGIN NEW - Customizable suspension term layout
   	% length(Args,A),
   	% Suspension =.. [suspension,_,State,_,NewGeneration,_,_|Args],
	( may_trigger(FA) ->
		delay_phase_end(validate_store_type_assumptions,
			( static_suspension_term(FA,Suspension),
			  get_static_suspension_term_field(state,FA,Suspension,State),
			  get_static_suspension_term_field(generation,FA,Suspension,NewGeneration),
			  get_static_suspension_term_field(arguments,FA,Suspension,Args)
			)
		),
   		create_get_mutable_ref(Generation,NewGeneration,GetGeneration)
	;
		delay_phase_end(validate_store_type_assumptions,
			( static_suspension_term(FA,Suspension),
			  get_static_suspension_term_field(state,FA,Suspension,State),
			  get_static_suspension_term_field(arguments,FA,Suspension,Args)
			)
		),
		GetGeneration = true
	),
	% END NEW
	create_get_mutable_ref(active,State,GetState),
   	ConditionalCall =
      	(	Susp = Suspension,
	  	GetState,
          	GetGeneration ->
		  	'chr update_mutable'(inactive,State),
	          	Call
	      	;   
			true
      	).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____                                    _   _             
%% |  _ \ _ __ ___  _ __   __ _  __ _  __ _| |_(_) ___  _ __  
%% | |_) | '__/ _ \| '_ \ / _` |/ _` |/ _` | __| |/ _ \| '_ \ 
%% |  __/| | | (_) | |_) | (_| | (_| | (_| | |_| | (_) | | | |
%% |_|   |_|  \___/| .__/ \__,_|\__, |\__,_|\__|_|\___/|_| |_|
%%                 |_|          |___/                         

propagation_code(Head,RestHeads,RestIDs,Rule,RuleNb,FA,O,Id,L,T) :-
	( RestHeads == [] ->
		propagation_single_headed(Head,Rule,RuleNb,FA,O,Id,L,T)
	;   
		propagation_multi_headed(Head,RestHeads,RestIDs,Rule,RuleNb,FA,O,Id,L,T)
	).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Single headed propagation
%% everything in a single clause
propagation_single_headed(Head,Rule,RuleNb,F/A,O,Id,ProgramList,ProgramTail) :-
	head_info(Head,A,Vars,Susp,VarsSusp,HeadPairs),
	build_head(F,A,Id,VarsSusp,ClauseHead),
	
	inc_id(Id,NextId),
	build_head(F,A,NextId,VarsSusp,NextHead),
	
	get_constraint_mode(F/A,Mode),
	head_arg_matches(HeadPairs,Mode,[],HeadMatching,VarDict,[],GroundVars),
	guard_body_copies(Rule,VarDict,GuardCopy,BodyCopy),
	gen_occ_allocation(F/A,O,Vars,Susp,VarsSusp,Allocation),
	
	% - recursive call -
	RecursiveCall = NextHead,
	( BodyCopy \== true, is_observed(F/A,O) ->
	    gen_uncond_attach_goal(F/A,Susp,Attachment,Generation),
	    gen_state_cond_call(Susp,F/A,RecursiveCall,Generation,ConditionalRecursiveCall)
	;   Attachment = true,
	    ConditionalRecursiveCall = RecursiveCall
	),

	( unconditional_occurrence(F/A,O), chr_pp_flag(late_allocation,on) ->
		ActualCut = true
	;
		ActualCut = !
	),

	( chr_pp_flag(debugable,on) ->
		Rule = rule(_,_,Guard,Body),
		my_term_copy(Guard - Body, VarDict, DebugGuard - DebugBody),		
		DebugTry   = 'chr debug_event'(  try([],[Susp],DebugGuard,DebugBody)),
		DebugApply = 'chr debug_event'(apply([],[Susp],DebugGuard,DebugBody)),
		instrument_goal(ActualCut,DebugTry,DebugApply,Cut)
	;
		Cut = ActualCut
	),
   	( may_trigger(F/A), \+ has_no_history(RuleNb)->
		use_auxiliary_predicate(novel_production),
		use_auxiliary_predicate(extend_history),
		NovelProduction = '$novel_production'(Susp,RuleNb),	% optimisation of t(RuleNb,Susp)
		ExtendHistory   = '$extend_history'(Susp,RuleNb)
   	;
		NovelProduction = true,
		ExtendHistory   = true
	),

	Clause = (
	     ClauseHead :-
	     	HeadMatching,
	     	Allocation,
	     	NovelProduction,
	     	GuardCopy,
	     	Cut,
	     	ExtendHistory,
	     	Attachment,
	     	BodyCopy,
	     	ConditionalRecursiveCall
	),  
	ProgramList = [Clause | ProgramTail].
   
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% multi headed propagation
%% prelude + predicates to accumulate the necessary combinations of suspended
%% constraints + predicate to execute the body
propagation_multi_headed(Head,RestHeads,RestIDs,Rule,RuleNb,FA,O,Id,L,T) :-
   RestHeads = [First|Rest],
   propagation_prelude(Head,RestHeads,Rule,FA,O,Id,L,L1),
   extend_id(Id,ExtendedId),
   propagation_nested_code(Rest,[First,Head],RestIDs,Rule,RuleNb,FA,O,ExtendedId,L1,T).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
propagation_prelude(Head,[First|Rest],Rule,F/A,O,Id,L,T) :-
   head_info(Head,A,Vars,Susp,VarsSusp,HeadPairs),
   build_head(F,A,Id,VarsSusp,PreludeHead),
   get_constraint_mode(F/A,Mode),
   head_arg_matches(HeadPairs,Mode,[],FirstMatching,VarDict),
   Rule = rule(_,_,Guard,Body),
   extra_active_delegate_variables(Head,[First,Rest,Guard,Body],VarDict,ExtraVars),

   lookup_passive_head(First,[Head],VarDict,FirstSuspGoal,Susps),

   gen_occ_allocation(F/A,O,Vars,Susp,VarsSusp,CondAllocation),

   extend_id(Id,NestedId),
   append([Susps|VarsSusp],ExtraVars,NestedVars), 
   build_head(F,A,NestedId,NestedVars,NestedHead),
   NestedCall = NestedHead,

   Prelude = (
      PreludeHead :-
	  FirstMatching,
	  FirstSuspGoal,
          !,
          CondAllocation,
          NestedCall
   ),
   L = [Prelude|T].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
propagation_nested_code([],[CurrentHead|PreHeads],RestIDs,Rule,RuleNb,FA,O,Id,L,T) :-
   universal_search_iterator_end([CurrentHead|PreHeads],[],Rule,FA,Id,L,L1),
   propagation_body(CurrentHead,PreHeads,RestIDs,Rule,RuleNb,FA,O,Id,L1,T).


propagation_nested_code([Head|RestHeads],PreHeads,RestIDs,Rule,RuleNb,FA,O,Id,L,T) :-
   universal_search_iterator_end(PreHeads,[Head|RestHeads],Rule,FA,Id,L,L1),
   universal_search_iterator([Head|RestHeads],PreHeads,Rule,FA,Id,L1,L2),
   inc_id(Id,IncId),
   propagation_nested_code(RestHeads,[Head|PreHeads],RestIDs,Rule,RuleNb,FA,O,IncId,L2,T).

check_fd_lookup_condition(_,_,_,_) :- fail.
%check_fd_lookup_condition(F,A,_,_) :-
%	get_store_type(F/A,global_singleton), !.
%check_fd_lookup_condition(F,A,CurrentHead,PreHeads) :-
%	get_functional_dependency(F/A,1,P,K),
%	copy_term_nat(P-K,CurrentHead-Key),
%	term_variables(PreHeads,PreVars),
%	intersect_eq(Key,PreVars,Key).		

propagation_body(CurrentHead,PreHeads,RestIDs,Rule,RuleNb,F/A,O,Id,L,T) :-
	Rule = rule(_,_,Guard,Body),
	gen_var_susp_list_for_b(PreHeads,[CurrentHead,Guard,Body],VarDict1,PreVarsAndSuspsList,FirstVarsSusp,AllSusps,PrevIterators),
	flatten(PreVarsAndSuspsList,PreVarsAndSusps),
	init(AllSusps,RestSusps),
	last(AllSusps,Susp),	
	gen_var(OtherSusp),
	gen_var(OtherSusps),
	functor(CurrentHead,OtherF,OtherA),
	gen_vars(OtherA,OtherVars),
	delay_phase_end(validate_store_type_assumptions,
		( static_suspension_term(OtherF/OtherA,Suspension),
		  get_static_suspension_term_field(state,OtherF/OtherA,Suspension,State),
		  get_static_suspension_term_field(arguments,OtherF/OtherA,Suspension,OtherVars)
		)
	),
	create_get_mutable_ref(active,State,GetMutable),
	CurrentSuspTest = (
	   OtherSusp = Suspension,
	   GetMutable
	),
	ClauseVars = [[OtherSusp|OtherSusps]|PreVarsAndSusps],
	build_head(F,A,Id,ClauseVars,ClauseHead),
	( check_fd_lookup_condition(OtherF,OtherA,CurrentHead,PreHeads) ->	% iterator (OtherSusps) is empty at runtime
		universal_search_iterator_failure_vars(PreHeads,Id,PreVarsAndSuspsList,FirstVarsSusp,PrevIterators,PreVarsAndSusps1,PrevId),
		RecursiveVars = PreVarsAndSusps1
	;
		RecursiveVars = [OtherSusps|PreVarsAndSusps],
		PrevId = Id
	),
	build_head(F,A,PrevId,RecursiveVars,RecursiveHead),
	RecursiveCall = RecursiveHead,
	CurrentHead =.. [_|OtherArgs],
	pairup(OtherArgs,OtherVars,OtherPairs),
	get_constraint_mode(OtherF/OtherA,Mode),
	head_arg_matches(OtherPairs,Mode,VarDict1,Matching,VarDict),
	
	different_from_other_susps(CurrentHead,OtherSusp,PreHeads,RestSusps,DiffSuspGoals), 
	guard_body_copies(Rule,VarDict,GuardCopy,BodyCopy),
	
	(   BodyCopy \== true, is_observed(F/A,O) ->
	    gen_uncond_attach_goal(F/A,Susp,Attach,Generation),
	    gen_state_cond_call(Susp,F/A,RecursiveCall,Generation,ConditionalRecursiveCall)
	;   Attach = true,
	    ConditionalRecursiveCall = RecursiveCall
	),
	( (is_least_occurrence(RuleNb) ; has_no_history(RuleNb)) ->
		NovelProduction = true,
		ExtendHistory   = true
	;	  
		get_occurrence(F/A,O,_,ID),

		history_susps(RestIDs,[OtherSusp|RestSusps],Susp,ID,HistorySusps),
   		Tuple =.. [t,RuleNb|HistorySusps],
		use_auxiliary_predicate(novel_production),
		use_auxiliary_predicate(extend_history),
		bagof('$novel_production'(X,Y),( member(X,HistorySusps), Y = TupleVar) ,NovelProductionsList),
		list2conj(NovelProductionsList,NovelProductions),
		NovelProduction = ( TupleVar = Tuple, NovelProductions),
		ExtendHistory   = '$extend_history'(Susp,TupleVar)
	),


	( chr_pp_flag(debugable,on) ->
		Rule = rule(_,_,Guard,Body),
		my_term_copy(Guard - Body, VarDict, DebugGuard - DebugBody),		
		DebugTry   = 'chr debug_event'(  try([],[Susp,OtherSusp|RestSusps],DebugGuard,DebugBody)),
		DebugApply = 'chr debug_event'(apply([],[Susp,OtherSusp|RestSusps],DebugGuard,DebugBody))
	;
		DebugTry = true,
		DebugApply = true
	),

   Clause = (
      ClauseHead :-
	  (   CurrentSuspTest,
	     DiffSuspGoals,
             Matching,
	     NovelProduction,
             GuardCopy,
	     DebugTry ->
	     DebugApply,
	     ExtendHistory,
             Attach,
             BodyCopy,
             ConditionalRecursiveCall
         ;   RecursiveCall
         )
   ),
   L = [Clause|T].

history_susps(RestIDs,ReversedRestSusps,Susp,ID,HistorySusps) :-
	reverse(ReversedRestSusps,RestSusps),
	pairup([ID|RestIDs],[Susp|RestSusps],IDSusps),
	sort(IDSusps,SortedIDSusps),
	pairup(_,HistorySusps,SortedIDSusps).

gen_var_susp_list_for([Head],Terms,VarDict,HeadVars,VarsSusp,Susp) :-
   !,
   functor(Head,F,A),
   head_info(Head,A,_Vars,Susp,VarsSusp,HeadPairs),
   get_constraint_mode(F/A,Mode),
   head_arg_matches(HeadPairs,Mode,[],_,VarDict),
   extra_active_delegate_variables(Head,Terms,VarDict,ExtraVars),
   append(VarsSusp,ExtraVars,HeadVars).
gen_var_susp_list_for([Head|Heads],Terms,NVarDict,VarsSusps,Rest,Susps) :-
	gen_var_susp_list_for(Heads,[Head|Terms],VarDict,Rest,_,_),
	functor(Head,F,A),
	gen_var(Susps),
	head_info(Head,A,_Vars,Susp,_VarsSusp,HeadPairs),
	get_constraint_mode(F/A,Mode),
	head_arg_matches(HeadPairs,Mode,VarDict,_,NVarDict),
	passive_delegate_variables(Head,Heads,Terms,NVarDict,HeadVars),
	append(HeadVars,[Susp,Susps|Rest],VarsSusps).

	% returns
	%	VarDict		for the copies of variables in the original heads
	%	VarsSuspsList	list of lists of arguments for the successive heads
	%	FirstVarsSusp	top level arguments
	%	SuspList	list of all suspensions
	%	Iterators	list of all iterators
gen_var_susp_list_for_b([Head],NextHeads,VarDict,[HeadVars],VarsSusp,[Susp],[]) :-
	!,
	functor(Head,F,A),
	head_info(Head,A,_Vars,Susp,VarsSusp,HeadPairs),			% make variables for argument positions
	get_constraint_mode(F/A,Mode),
	head_arg_matches(HeadPairs,Mode,[],_,VarDict),				% copy variables inside arguments, build dictionary
	extra_active_delegate_variables(Head,NextHeads,VarDict,ExtraVars),	% decide what additional variables are needed
	append(VarsSusp,ExtraVars,HeadVars).					% add additional variables to head variables
gen_var_susp_list_for_b([Head|Heads],NextHeads,NVarDict,[Vars|RestVars],FirstVarsSusp,[Susp|SuspList],[Susps|Iterators]) :-
	gen_var_susp_list_for_b(Heads,[Head|NextHeads],VarDict,RestVars,FirstVarsSusp,SuspList,Iterators),
	functor(Head,F,A),
	gen_var(Susps),
	head_info(Head,A,_Vars,Susp,_VarsSusp,HeadPairs),
	get_constraint_mode(F/A,Mode),
	head_arg_matches(HeadPairs,Mode,VarDict,_,NVarDict),
	passive_delegate_variables(Head,Heads,NextHeads,NVarDict,HeadVars),
	append(HeadVars,[Susp,Susps],Vars).

get_prop_inner_loop_vars([Head],Terms,HeadVars,VarDict,Susp,[]) :-
	!,
	functor(Head,F,A),
	head_info(Head,A,_Vars,Susp,VarsSusp,Pairs),
	get_constraint_mode(F/A,Mode),
	head_arg_matches(Pairs,Mode,[],_,VarDict),
	extra_active_delegate_variables(Head,Terms,VarDict,ExtraVars),
	append(VarsSusp,ExtraVars,HeadVars).
get_prop_inner_loop_vars([Head|Heads],Terms,VarsSusps,NVarDict,MainSusp,[Susp|RestSusps]) :-
	get_prop_inner_loop_vars(Heads,[Head|Terms],RestVarsSusp,VarDict,MainSusp,RestSusps),
	functor(Head,F,A),
	gen_var(Susps),
	head_info(Head,A,_Vars,Susp,_VarsSusp,Pairs),
	get_constraint_mode(F/A,Mode),
	head_arg_matches(Pairs,Mode,VarDict,_,NVarDict),
	passive_delegate_variables(Head,Heads,Terms,NVarDict,HeadVars),
	append(HeadVars,[Susp,Susps|RestVarsSusp],VarsSusps).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ____               _             _   _                _ 
%% |  _ \ __ _ ___ ___(_)_   _____  | | | | ___  __ _  __| |
%% | |_) / _` / __/ __| \ \ / / _ \ | |_| |/ _ \/ _` |/ _` |
%% |  __/ (_| \__ \__ \ |\ V /  __/ |  _  |  __/ (_| | (_| |
%% |_|   \__,_|___/___/_| \_/ \___| |_| |_|\___|\__,_|\__,_|
%%                                                          
%%  ____      _        _                 _ 
%% |  _ \ ___| |_ _ __(_) _____   ____ _| |
%% | |_) / _ \ __| '__| |/ _ \ \ / / _` | |
%% |  _ <  __/ |_| |  | |  __/\ V / (_| | |
%% |_| \_\___|\__|_|  |_|\___| \_/ \__,_|_|
%%                                         
%%  ____                    _           _             
%% |  _ \ ___  ___  _ __ __| | ___ _ __(_)_ __   __ _ 
%% | |_) / _ \/ _ \| '__/ _` |/ _ \ '__| | '_ \ / _` |
%% |  _ <  __/ (_) | | | (_| |  __/ |  | | | | | (_| |
%% |_| \_\___|\___/|_|  \__,_|\___|_|  |_|_| |_|\__, |
%%                                              |___/ 

reorder_heads(RuleNb,Head,RestHeads,RestIDs,NRestHeads,NRestIDs) :-
	( chr_pp_flag(reorder_heads,on), length(RestHeads,Length), Length =< 6 ->
		reorder_heads_main(RuleNb,Head,RestHeads,RestIDs,NRestHeads,NRestIDs)
		
	;
		NRestHeads = RestHeads,
		NRestIDs = RestIDs
	).

reorder_heads_main(RuleNb,Head,RestHeads,RestIDs,NRestHeads,NRestIDs) :-
	term_variables(Head,Vars),
	InitialData = entry([],[],Vars,RestHeads,RestIDs,RuleNb),
	copy_term_nat(InitialData,InitialDataCopy),
	a_star(InitialDataCopy,FD,(final_data(FD)),N^EN^C,(expand_data(N,EN,C)),FinalData),
	InitialDataCopy = InitialData,
	FinalData   = entry(RNRestHeads,RNRestIDs,_,_,_,_),
	reverse(RNRestHeads,NRestHeads),
	reverse(RNRestIDs,NRestIDs).

final_data(Entry) :-
	Entry = entry(_,_,_,_,[],_).	

expand_data(Entry,NEntry,Cost) :-
	Entry = entry(Heads,IDs,Vars,NHeads,NIDs,RuleNb),
	select2(Head1,ID1,NHeads,NIDs,NHeads1,NIDs1),
	term_variables([Head1|Vars],Vars1),
	NEntry = entry([Head1|Heads],[ID1|IDs],Vars1,NHeads1,NIDs1,RuleNb),
	order_score(Head1,ID1,Vars,NHeads1,RuleNb,Cost).

	% Assigns score to head based on known variables and heads to lookup
order_score(Head,ID,KnownVars,RestHeads,RuleNb,Score) :-
	functor(Head,F,A),
	get_store_type(F/A,StoreType),
	order_score(StoreType,Head,ID,KnownVars,RestHeads,RuleNb,Score).


order_score(default,Head,_ID,KnownVars,RestHeads,RuleNb,Score) :-
	term_variables(Head,HeadVars),
	term_variables(RestHeads,RestVars),
	order_score_vars(HeadVars,KnownVars,RestVars,Score).
order_score(multi_inthash(Indexes),Head,_ID,KnownVars,RestHeads,RuleNb,Score) :-
	order_score_indexes(Indexes,Head,KnownVars,0,Score).
order_score(multi_hash(Indexes),Head,_ID,KnownVars,RestHeads,RuleNb,Score) :-
	order_score_indexes(Indexes,Head,KnownVars,0,Score).
order_score(global_ground,Head,ID,KnownVars,RestHeads,RuleNb,Score) :-
	term_variables(Head,HeadVars),
	term_variables(RestHeads,RestVars),
	order_score_vars(HeadVars,KnownVars,RestVars,Score_),
	Score is Score_ * 2.
order_score(global_singleton,_Head,ID,_KnownVars,_RestHeads,_RuleNb,Score) :-
	Score = 1.		% guaranteed O(1)
			
order_score(multi_store(StoreTypes),Head,ID,KnownVars,RestHeads,RuleNb,Score) :-
	find_with_var_identity(
		S,
		t(Head,KnownVars,RestHeads),
		( member(ST,StoreTypes), order_score(ST,Head,ID,KnownVars,RestHeads,RuleNb,S) ),
		Scores
	),
	min_list(Scores,Score).
		

order_score_indexes([],_,_,Score,NScore) :-
	Score > 0, NScore = 100.
order_score_indexes([I|Is],Head,KnownVars,Score,NScore) :-
	multi_hash_key_args(I,Head,Args),
	( forall(Arg,Args,memberchk_eq(Arg,KnownVars)) ->
		Score1 is Score + 1 	
	;
		Score1 = Score
	),
	order_score_indexes(Is,Head,KnownVars,Score1,NScore).

order_score_vars(Vars,KnownVars,RestVars,Score) :-
	order_score_count_vars(Vars,KnownVars,RestVars,K-R-O),
	( K-R-O == 0-0-0 ->
		Score = 0
	; K > 0 ->
	        max( 10 - K , 0 , Score )
%		Score is max(10 - K,0)
	; R > 0 ->
	        max( 10 - R , 1 , S ),
		Score is S * 10
%		Score is max(10 - R,1) * 10
	; 
%		Score is max(10-O,1) * 100
		max(10-O,1, S),
		Score is S * 100
	).	
order_score_count_vars([],_,_,0-0-0).
order_score_count_vars([V|Vs],KnownVars,RestVars,NK-NR-NO) :-
	order_score_count_vars(Vs,KnownVars,RestVars,K-R-O),
	( memberchk_eq(V,KnownVars) ->
		NK is K + 1,
		NR = R, NO = O
	; memberchk_eq(V,RestVars) ->
		NR is R + 1,
		NK = K, NO = O
	;
		NO is O + 1,
		NK = K, NR = R
	).


max( A , B, A1 ) :- A1 is A, B1 is B, A1 >= B1,!.
max( _ , B, A  ) :- A is B.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  ___       _ _       _             
%% |_ _|_ __ | (_)_ __ (_)_ __   __ _ 
%%  | || '_ \| | | '_ \| | '_ \ / _` |
%%  | || | | | | | | | | | | | | (_| |
%% |___|_| |_|_|_|_| |_|_|_| |_|\__, |
%%                              |___/ 

%% SWI begin
create_get_mutable_ref(V,M,GM) :- GM = (M = mutable(V)).
%% SWI end

%% SICStus begin
%% create_get_mutable_ref(V,M,GM) :- GM = get_mutable(V,M).
%% SICStus end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  _   _ _   _ _ _ _
%% | | | | |_(_) (_) |_ _   _
%% | | | | __| | | | __| | | |
%% | |_| | |_| | | | |_| |_| |
%%  \___/ \__|_|_|_|\__|\__, |
%%                      |___/

gen_var(_).
gen_vars(N,Xs) :-
   length(Xs,N). 

head_info(Head,A,Vars,Susp,VarsSusp,HeadPairs) :-
   vars_susp(A,Vars,Susp,VarsSusp),
   Head =.. [_|Args],
   pairup(Args,Vars,HeadPairs).
 
inc_id([N|Ns],[O|Ns]) :-
   O is N + 1.
dec_id([N|Ns],[M|Ns]) :-
   M is N - 1.

extend_id(Id,[0|Id]).

next_id([_,N|Ns],[O|Ns]) :-
   O is N + 1.

build_head(F,A,Id,Args,Head) :-
   buildName(F,A,Id,Name),
   ( (chr_pp_flag(debugable,on) ; is_stored(F/A),
	( may_trigger(F/A) ; 
		get_allocation_occurrence(F/A,AO), 
		get_max_occurrence(F/A,MO), 
	MO >= AO) ) ->	
	   Head =.. [Name|Args]
   ;
	   init(Args,ArgsWOSusp),	% XXX not entirely correct!
	   Head =.. [Name|ArgsWOSusp]
  ).

buildName(Fct,Aty,List,Result) :-
   ( (chr_pp_flag(debugable,on) ; (once((is_stored(Fct/Aty), ( has_active_occurrence(Fct/Aty) ; chr_pp_flag(late_allocation,off)), 
   ( may_trigger(Fct/Aty) ; get_allocation_occurrence(Fct/Aty,AO), get_max_occurrence(Fct/Aty,MO), 
   MO >= AO ) ; List \= [0])) ) ) -> 
	atom_concat(Fct, (/) ,FctSlash),
	atomic_concat(FctSlash,Aty,FctSlashAty),
	buildName_(List,FctSlashAty,Result)
   ;
	Result = Fct
   ).

buildName_([],Name,Name).
buildName_([N|Ns],Name,Result) :-
  buildName_(Ns,Name,Name1),
  atom_concat(Name1,'__',NameDash),    % '_' is a char :-(
  atomic_concat(NameDash,N,Result).

vars_susp(A,Vars,Susp,VarsSusp) :-
   length(Vars,A),
   append(Vars,[Susp],VarsSusp).

make_attr(N,Mask,SuspsList,Attr) :-
	length(SuspsList,N),
	Attr =.. [v,Mask|SuspsList].

or_pattern(Pos,Pat) :-
	Pow is Pos - 1,
	Pat is 1 << Pow.      % was 2 ** X

and_pattern(Pos,Pat) :-
	X is Pos - 1,
	Y is 1 << X,          % was 2 ** X
	Pat is (-1)*(Y + 1).

make_name(Prefix,F/A,Name) :-
	atom_concat_list([Prefix,F,(/),A],Name).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Storetype dependent lookup
lookup_passive_head(Head,PreJoin,VarDict,Goal,AllSusps) :-
	functor(Head,F,A),
	get_store_type(F/A,StoreType),
	lookup_passive_head(StoreType,Head,PreJoin,VarDict,Goal,AllSusps).

lookup_passive_head(default,Head,PreJoin,VarDict,Goal,AllSusps) :-
	functor(Head,F,A),
	passive_head_via(Head,PreJoin,VarDict,Goal,AllSusps).   
lookup_passive_head(multi_inthash(Indexes),Head,_PreJoin,VarDict,Goal,AllSusps) :-
	once((
		member(Index,Indexes),
		multi_hash_key_args(Index,Head,KeyArgs),	
		(translate(KeyArgs,VarDict,KeyArgCopies) ;
		 ground(KeyArgs), KeyArgCopies = KeyArgs )
	)),
	( KeyArgCopies = [KeyCopy] ->
		true
	;
		KeyCopy =.. [k|KeyArgCopies]
	),
	functor(Head,F,A),
	multi_hash_via_lookup_name(F/A,Index,ViaName),
	Goal =.. [ViaName,KeyCopy,AllSusps],
	update_store_type(F/A,multi_inthash([Index])).
lookup_passive_head(multi_hash(Indexes),Head,_PreJoin,VarDict,Goal,AllSusps) :-
	once((
		member(Index,Indexes),
		multi_hash_key_args(Index,Head,KeyArgs),	
		(translate(KeyArgs,VarDict,KeyArgCopies) ;
		 ground(KeyArgs), KeyArgCopies = KeyArgs )
	)),
	( KeyArgCopies = [KeyCopy] ->
		true
	;
		KeyCopy =.. [k|KeyArgCopies]
	),
	functor(Head,F,A),
	multi_hash_via_lookup_name(F/A,Index,ViaName),
	Goal =.. [ViaName,KeyCopy,AllSusps],
	update_store_type(F/A,multi_hash([Index])).
lookup_passive_head(global_ground,Head,_PreJoin,_VarDict,Goal,AllSusps) :-
	functor(Head,F,A),
	global_ground_store_name(F/A,StoreName),
	make_get_store_goal(StoreName,AllSusps,Goal), % Goal = nb_getval(StoreName,AllSusps),
	update_store_type(F/A,global_ground).
lookup_passive_head(global_singleton,Head,_PreJoin,_VarDict,Goal,AllSusps) :-
	functor(Head,F,A),
	global_singleton_store_name(F/A,StoreName),
	make_get_store_goal(StoreName,Susp,GetStoreGoal),
	Goal = (GetStoreGoal,Susp \== [],AllSusps = [Susp]),
	update_store_type(F/A,global_singleton).
lookup_passive_head(multi_store(StoreTypes),Head,PreJoin,VarDict,Goal,AllSusps) :-
	once((
		member(ST,StoreTypes),
		lookup_passive_head(ST,Head,PreJoin,VarDict,Goal,AllSusps)
	)).

existential_lookup(global_singleton,Head,_PreJoin,_VarDict,SuspTerm,State,Goal,Susp,Pairs,Pairs) :- !,
	functor(Head,F,A),
	global_singleton_store_name(F/A,StoreName),
	make_get_store_goal(StoreName,Susp,GetStoreGoal),
	Goal = 	(
			GetStoreGoal, % nb_getval(StoreName,Susp),
			Susp \== [],
			Susp = SuspTerm
		),
	update_store_type(F/A,global_singleton).
existential_lookup(multi_store(StoreTypes),Head,PreJoin,VarDict,SuspTerm,State,Goal,Susp,Pairs,NPairs) :- !,
	once((
		member(ST,StoreTypes),
		existential_lookup(ST,Head,PreJoin,VarDict,SuspTerm,State,Goal,Susp,Pairs,NPairs)
	)).
existential_lookup(multi_inthash(Indexes),Head,_PreJoin,VarDict,SuspTerm,State,Goal,Susp,Pairs,NPairs) :- !,
	once((
		member(Index,Indexes),
		multi_hash_key_args(Index,Head,KeyArgs),	
		(translate(KeyArgs,VarDict,KeyArgCopies) ;
		 ground(KeyArgs), KeyArgCopies = KeyArgs )
	)),
	( KeyArgCopies = [KeyCopy] ->
		true
	;
		KeyCopy =.. [k|KeyArgCopies]
	),
	functor(Head,F,A),
	multi_hash_via_lookup_name(F/A,Index,ViaName),
	LookupGoal =.. [ViaName,KeyCopy,AllSusps],
	create_get_mutable_ref(active,State,GetMutable),
	sbag_member_call(Susp,AllSusps,Sbag),
	Goal =	(
			LookupGoal,
			Sbag,
			Susp = SuspTerm,		% not inlined
			GetMutable
		),
	hash_index_filter(Pairs,Index,NPairs),
	update_store_type(F/A,multi_inthash([Index])).
existential_lookup(multi_hash(Indexes),Head,_PreJoin,VarDict,SuspTerm,State,Goal,Susp,Pairs,NPairs) :- !,
	once((
		member(Index,Indexes),
		multi_hash_key_args(Index,Head,KeyArgs),	
		(translate(KeyArgs,VarDict,KeyArgCopies) ;
		 ground(KeyArgs), KeyArgCopies = KeyArgs )
	)),
	( KeyArgCopies = [KeyCopy] ->
		true
	;
		KeyCopy =.. [k|KeyArgCopies]
	),
	functor(Head,F,A),
	multi_hash_via_lookup_name(F/A,Index,ViaName),
	LookupGoal =.. [ViaName,KeyCopy,AllSusps],
	sbag_member_call(Susp,AllSusps,Sbag),
	create_get_mutable_ref(active,State,GetMutable),
	Goal =	(
			LookupGoal,
			Sbag,
			Susp = SuspTerm,		% not inlined
			GetMutable
		),
	hash_index_filter(Pairs,Index,NPairs),
	update_store_type(F/A,multi_hash([Index])).
existential_lookup(StoreType,Head,PreJoin,VarDict,SuspTerm,State,Goal,Susp,Pairs,Pairs) :-
	lookup_passive_head(StoreType,Head,PreJoin,VarDict,UGoal,Susps),	
	sbag_member_call(Susp,Susps,Sbag),
	create_get_mutable_ref(active,State,GetMutable),
	Goal =	(
			UGoal,
			Sbag,
			Susp = SuspTerm,		% not inlined
			GetMutable
		).



hash_index_filter(Pairs,Index,NPairs) :-
	( integer(Index) ->
		NIndex = [Index]
	;
		NIndex = Index
	),
	hash_index_filter(Pairs,NIndex,1,NPairs).

hash_index_filter([],_,_,[]).
hash_index_filter([P|Ps],Index,N,NPairs) :-
	( Index = [I|Is] ->
		NN is N + 1,
		( I > N ->
			NPairs = [P|NPs],
			hash_index_filter(Ps,[I|Is],NN,NPs)
		; I == N ->
			NPairs = NPs,
			hash_index_filter(Ps,Is,NN,NPs)
		)	
	;
		NPairs = [P|Ps]
	).	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
assume_constraint_stores([]).
assume_constraint_stores([C|Cs]) :-
	( only_ground_indexed_arguments(C),
	  is_stored(C),
	  get_store_type(C,default) ->
		get_indexed_arguments(C,IndexedArgs),
		% TODO: O(2^n) is not robust for too many indexed arguments, 
		%	reject some possible indexes... 
		% 	or replace brute force index generation with other approach
		length(IndexedArgs,NbIndexedArgs),
		( NbIndexedArgs > 10 ->
			findall([Index],member(Index,IndexedArgs),Indexes)
		;
			findall(Index,(sublist(Index,IndexedArgs), Index \== []),UnsortedIndexes),
			predsort(longer_list,UnsortedIndexes,Indexes)
		),
		( get_functional_dependency(C,1,Pattern,Key), 
		  all_distinct_var_args(Pattern), Key == [] ->
			assumed_store_type(C,global_singleton)
		;
		    ( get_constraint_type(C,Type),
		    findall(Index,(member(Index,Indexes), Index = [I],
		    nth(I,Type,dense_int)),IndexesA),
		    IndexesA \== [] ->
			list_difference_eq(Indexes,IndexesA,IndexesB),
			( IndexesB \== [] ->
			    assumed_store_type(C,multi_store([multi_inthash(IndexesA),multi_hash(IndexesB),global_ground]))	
			;
			    assumed_store_type(C,multi_store([multi_inthash(IndexesA),global_ground]))	
			)
		    ;
			assumed_store_type(C,multi_store([multi_hash(Indexes),global_ground]))	
		    )
		)
	;
		true
	),
	assume_constraint_stores(Cs).

longer_list(R,L1,L2) :-
	length(L1,N1),
	length(L2,N2),
	compare(Rt,N2,N1),
	( Rt == (=) ->
		compare(R,L1,L2)
	;
		R = Rt
	).

all_distinct_var_args(Term) :-
	Term =.. [_|Args],
	copy_term_nat(Args,NArgs),
	all_distinct_var_args_(NArgs).

all_distinct_var_args_([]).
all_distinct_var_args_([X|Xs]) :-
	var(X),
	X = t,	
	all_distinct_var_args_(Xs).

get_indexed_arguments(C,IndexedArgs) :-
	C = F/A,
	get_indexed_arguments(1,A,C,IndexedArgs).

get_indexed_arguments(I,N,C,L) :-
	( I > N ->
		L = []
	; 	( is_indexed_argument(C,I) ->
			L = [I|T]
		;
			L = T
		),
		J is I + 1,
		get_indexed_arguments(J,N,C,T)
	).
	
validate_store_type_assumptions([]).
validate_store_type_assumptions([C|Cs]) :-
	validate_store_type_assumption(C),
	validate_store_type_assumptions(Cs).	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% new code generation
universal_search_iterator_end([CurrentHead|PrevHeads],NextHeads,Rule,F/A,Id,L,T) :-
	Rule = rule(H1,_,Guard,Body),
	( H1 == [],
	  functor(CurrentHead,CF,CA),
	  check_fd_lookup_condition(CF,CA,CurrentHead,PrevHeads) ->
		L = T
	;
		gen_var_susp_list_for_b(PrevHeads,[CurrentHead,NextHeads,Guard,Body],_,VarsAndSuspsList,FirstVarsSusp,_,PrevIterators),
		universal_search_iterator_failure_vars(PrevHeads,Id,VarsAndSuspsList,FirstVarsSusp,PrevIterators,PrevVarsAndSusps,PrevId),
		flatten(VarsAndSuspsList,VarsAndSusps),
		Vars = [ [] | VarsAndSusps],
		build_head(F,A,Id,Vars,Head),
		build_head(F,A,PrevId,PrevVarsAndSusps,PredecessorCall),
		Clause = ( Head :- PredecessorCall),
		L = [Clause | T]
	).

	% skips back intelligently over global_singleton lookups
universal_search_iterator_failure_vars(PrevHeads,Id,VarsAndSuspsList,BaseCallArgs,PrevIterators,PrevVarsAndSusps,PrevId) :-
	( Id = [0|_] ->
		next_id(Id,PrevId),
		PrevVarsAndSusps = BaseCallArgs
	;
		VarsAndSuspsList = [_|AllButFirstList],
		dec_id(Id,PrevId1),
		( PrevHeads  = [PrevHead|PrevHeads1],
		  functor(PrevHead,F,A),
		  check_fd_lookup_condition(F,A,PrevHead,PrevHeads1) ->
			PrevIterators = [_|PrevIterators1],
			universal_search_iterator_failure_vars(PrevHeads1,PrevId1,AllButFirstList,BaseCallArgs,PrevIterators1,PrevVarsAndSusps,PrevId)
		;
			PrevId = PrevId1,
			flatten(AllButFirstList,AllButFirst),
			PrevIterators = [PrevIterator|_],
			PrevVarsAndSusps = [PrevIterator|AllButFirst]
		)
	).

universal_search_iterator([NextHead|RestHeads],[CurrentHead|PreHeads],Rule,F/A,Id,L,T) :-
	Rule = rule(_,_,Guard,Body),
	gen_var_susp_list_for_b(PreHeads,[CurrentHead,NextHead,RestHeads,Guard,Body],VarDict,PreVarsAndSuspsList,FirstVarsSusp,AllSusps,PrevIterators),
	init(AllSusps,PreSusps),
	flatten(PreVarsAndSuspsList,PreVarsAndSusps),
	gen_var(OtherSusps),
	functor(CurrentHead,OtherF,OtherA),
	gen_vars(OtherA,OtherVars),
	head_info(CurrentHead,OtherA,OtherVars,OtherSusp,_VarsSusp,HeadPairs),
	get_constraint_mode(OtherF/OtherA,Mode),
	head_arg_matches(HeadPairs,Mode,VarDict,FirstMatching,VarDict1),
	
	% BEGIN NEW - Customizable suspension term layout
	% OtherSuspension =.. [suspension,_,State,_,_,_,_|OtherVars],
	delay_phase_end(validate_store_type_assumptions,
		( static_suspension_term(OtherF/OtherA,OtherSuspension),
		  get_static_suspension_term_field(state,OtherF/OtherA,OtherSuspension,State),
		  get_static_suspension_term_field(arguments,OtherF/OtherA,OtherSuspension,OtherVars)
		)
	),
	% END NEW

	different_from_other_susps(CurrentHead,OtherSusp,PreHeads,PreSusps,DiffSuspGoals),
	create_get_mutable_ref(active,State,GetMutable),
	CurrentSuspTest = (
	   OtherSusp = OtherSuspension,
	   GetMutable,
	   DiffSuspGoals,
	   FirstMatching
	),
        lookup_passive_head(NextHead,[CurrentHead|PreHeads],VarDict1,NextSuspGoal,NextSusps),
	inc_id(Id,NestedId),
	ClauseVars = [[OtherSusp|OtherSusps]|PreVarsAndSusps],
	build_head(F,A,Id,ClauseVars,ClauseHead),
	passive_delegate_variables(CurrentHead,PreHeads,[NextHead,RestHeads,Guard,Body],VarDict1,CurrentHeadVars),
	append([NextSusps|CurrentHeadVars],[OtherSusp,OtherSusps|PreVarsAndSusps],NestedVars),
	build_head(F,A,NestedId,NestedVars,NestedHead),
	
	( check_fd_lookup_condition(OtherF,OtherA,CurrentHead,PreHeads) ->	% iterator (OtherSusps) is empty at runtime
		universal_search_iterator_failure_vars(PreHeads,Id,PreVarsAndSuspsList,FirstVarsSusp,PrevIterators,PreVarsAndSusps1,PrevId),
		RecursiveVars = PreVarsAndSusps1
	;
		RecursiveVars = [OtherSusps|PreVarsAndSusps],
		PrevId = Id
	),
	build_head(F,A,PrevId,RecursiveVars,RecursiveHead),

	Clause = (
	   ClauseHead :-
	   (   CurrentSuspTest,
	       NextSuspGoal
	       ->
	       NestedHead
	   ;   RecursiveHead
	   )
	),   
	L = [Clause|T].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Observation Analysis
% 
% CLASSIFICATION
%   Enabled 
%
% Analysis based on Abstract Interpretation paper.
% 
% TODO: 
%   stronger analysis domain [research]

:- chr_constraint
	initial_call_pattern/1,
	call_pattern/1,
	final_answer_pattern/2,
	abstract_constraints/1,
	depends_on/2,
	depends_on_ap/4,
	depends_on_goal/2,
	ai_observed_internal/2,
	ai_observed/2,
	ai_not_observed_internal/2,
	ai_not_observed/2,
	ai_is_observed/2,
	depends_on_as/3,
	ai_observation_gather_results/0.

:- chr_option(mode,initial_call_pattern(+)).
:- chr_option(mode,call_pattern(+)).
:- chr_option(mode,final_answer_pattern(+,+)).
:- chr_option(mode,abstract_constraints(+)).
:- chr_option(mode,depends_on(+,+)).
:- chr_option(mode,depends_on_as(+,+,+)).
:- chr_option(mode,depends_on_ap(+,+,+,+)).
:- chr_option(mode,depends_on_goal(+,+)).
:- chr_option(mode,ai_observed(+,+)).
:- chr_option(mode,ai_is_observed(+,+)).
:- chr_option(mode,ai_not_observed(+,+)).
:- chr_option(mode,ai_observed(+,+)).
:- chr_option(mode,ai_not_observed_internal(+,+)).
:- chr_option(mode,ai_observed_internal(+,+)).

ai_observed_internal(C,O) \ ai_not_observed_internal(C,O) <=> true.
ai_not_observed_internal(C,O) \ ai_not_observed_internal(C,O) <=> true.
ai_observed_internal(C,O) \ ai_observed_internal(C,O) <=> true.

ai_not_observed(C,O) \ ai_is_observed(C,O) <=> fail.
ai_is_observed(_,_) <=> true.

ai_observation_gather_results \ ai_observed_internal(C,O) <=> ai_observed(C,O).
ai_observation_gather_results \ ai_not_observed_internal(C,O) <=> ai_not_observed(C,O).
ai_observation_gather_results <=> true.

ai_observation_analysis(ACs) :-
    ( chr_pp_flag(ai_observation_analysis,on),
	get_target_module(Module), Module \== chr_translate ->
	list_to_ord_set(ACs,ACSet),
	abstract_constraints(ACs),
	ai_observation_schedule_initial_calls(ACs),
	ai_observation_gather_results
    ;
	true
    ).

ai_observation_schedule_initial_calls([]).
ai_observation_schedule_initial_calls([AC|ACs]) :-
	ai_observation_schedule_initial_call(AC),
	ai_observation_schedule_initial_calls(ACs).

ai_observation_schedule_initial_call(AC) :-
	ai_observation_top(AC,CallPattern),	
	initial_call_pattern(CallPattern).

ai_observation_schedule_new_calls([],AP).
ai_observation_schedule_new_calls([AC|ACs],AP) :-
	AP = odom(_,Set),
	initial_call_pattern(odom(AC,Set)),
	ai_observation_schedule_new_calls(ACs,AP).

final_answer_pattern(CP,AP1) \ final_answer_pattern(CP,AP2)
	<=>
		ai_observation_leq(AP2,AP1)
	|
		true.

initial_call_pattern(CP) \ initial_call_pattern(CP) <=> true.

initial_call_pattern(CP) ==> call_pattern(CP).

initial_call_pattern(CP), final_answer_pattern(CP,AP),
	abstract_constraints(ACs) ==>
	ai_observation_schedule_new_calls(ACs,AP).

call_pattern(CP) \ call_pattern(CP) <=> true.	

depends_on(CP1,CP2), final_answer_pattern(CP2,AP) ==>
	final_answer_pattern(CP1,AP).

	% AbstractGoala
call_pattern(odom([],Set)) ==> 
	final_answer_pattern(odom([],Set),odom([],Set)).

	% AbstractGoalb
call_pattern(odom([G|Gs],Set)) ==>
	CP1 = odom(G,Set),
	depends_on_goal(odom([G|Gs],Set),CP1),
	call_pattern(CP1).

depends_on_goal(CP1,CP2), final_answer_pattern(CP2,AP2) \ depends_on(CP1,_) # ID
	<=> true pragma passive(ID).
depends_on_goal(CP1,CP2), final_answer_pattern(CP2,AP2)
	==> 
		CP1 = odom([_|Gs],_),
		AP2 = odom([],Set),
		CCP = odom(Gs,Set),
		call_pattern(CCP),
		depends_on(CP1,CCP).

	% AbstractSolve
call_pattern(odom(builtin,Set)) ==>
	% writeln('  - AbstractSolve'),
	ord_empty(EmptySet),
	final_answer_pattern(odom(builtin,Set),odom([],EmptySet)).

	% AbstractDrop
call_pattern(odom(occ(C,O),Set)), max_occurrence(C,MO) ==>
	O > MO |
	% writeln('  - AbstractDrop'),
	final_answer_pattern(odom(occ(C,O),Set),odom([],Set)).

	% AbstractActivate
call_pattern(odom(AC,Set)), abstract_constraints(ACs)
	==>
		memberchk_eq(AC,ACs)
	|
		% writeln('  - AbstractActivate'),
		CP = odom(occ(AC,1),Set),
		call_pattern(CP),
		depends_on(odom(AC,Set),CP).

	% AbstractSimplify (passive)
call_pattern(odom(occ(C,O),Set)), abstract_constraints(ACs), occurrence(C,O,RuleNb,ID), rule(RuleNb,Rule)
==>
	Rule = pragma(rule(H1,H2,G,Body),ids(IDs1,_),_,_,_),
	memberchk_eq(ID,IDs1), is_passive(RuleNb,ID) |
%	 writeln('  - AbstractSimplify(passive)'(C,O)),
	% DEFAULT
	NO is O + 1,
	DCP = odom(occ(C,NO),Set),
	call_pattern(DCP),
%	final_answer_pattern(odom(occ(C,O),Set),odom([],Set)),
	depends_on(odom(occ(C,O),Set),DCP).


	% AbstractSimplify
call_pattern(odom(occ(C,O),Set)), abstract_constraints(ACs), occurrence(C,O,RuleNb,ID), rule(RuleNb,Rule) ==>
	Rule = pragma(rule(H1,H2,G,Body),ids(IDs1,_),_,_,_),
	memberchk_eq(ID,IDs1), \+ is_passive(RuleNb,ID) |
%	 writeln('  - AbstractSimplify'(C,O)),
	% SIMPLIFICATION
	once(select2(ID,_,IDs1,H1,_,RestH1)),
	ai_observation_abstract_constraints(RestH1,ACs,ARestHeads),
	ai_observation_observe_list(odom([],Set),ARestHeads,odom([],Set1)),
	ai_observation_abstract_constraints(H2,ACs,AH2),
	ai_observation_observe_list(odom([],Set1),AH2,odom([],Set2)),
	ai_observation_abstract_goal_(H1,H2,G,Body,ACs,AG),
	call_pattern(odom(AG,Set2)),
	% DEFAULT
	NO is O + 1,
	DCP = odom(occ(C,NO),Set),
	call_pattern(DCP),
	depends_on_as(odom(occ(C,O),Set),odom(AG,Set2),DCP),
	% DEADLOCK AVOIDANCE
	final_answer_pattern(odom(occ(C,O),Set),odom([],Set)).

depends_on_as(CP,CPS,CPD),
	final_answer_pattern(CPS,APS),
	final_answer_pattern(CPD,APD) ==>
	ai_observation_lub(APS,APD,AP),
	final_answer_pattern(CP,AP).	

	% AbstractPropagate (passive)
call_pattern(odom(occ(C,O),Set)), abstract_constraints(ACs), occurrence(C,O,RuleNb,ID), rule(RuleNb,Rule) ==>
	Rule = pragma(rule(H1,H2,G,Body),ids(_,IDs2),_,_,_),
	memberchk_eq(ID,IDs2), is_passive(RuleNb,ID)
	|
%	 writeln('  - AbstractPropagate (passive)'(C,O)),
	% DEFAULT
	NO is O + 1,
	DCP = odom(occ(C,NO),Set),
	call_pattern(DCP),
	final_answer_pattern(odom(occ(C,O),Set),odom([],Set)),
	depends_on(odom(occ(C,O),Set),DCP).

	% AbstractPropagate
call_pattern(odom(occ(C,O),Set)), abstract_constraints(ACs), occurrence(C,O,RuleNb,ID), rule(RuleNb,Rule) ==>
	Rule = pragma(rule(H1,H2,G,Body),ids(_,IDs2),_,_,_),
	memberchk_eq(ID,IDs2), \+ is_passive(RuleNb,ID)
	|
%	 writeln('  - AbstractPropagate'(C,O)),
	% observe partners
	once(select2(ID,_,IDs2,H2,_,RestH2)),
	ai_observation_abstract_constraints(RestH2,ACs,ARestHeads),
	ai_observation_observe_list(odom([],Set),ARestHeads,odom([],Set1)),
	ai_observation_abstract_constraints(H1,ACs,AH1),
	ai_observation_observe_list(odom([],Set1),AH1,odom([],Set2)),
	ord_add_element(Set2,C,Set3),
	ai_observation_abstract_goal_(H1,H2,G,Body,ACs,AG),
	call_pattern(odom(AG,Set3)),
	( ord_memberchk(C,Set2) ->
		Delete = no
	;
		Delete = yes
	),
	% DEFAULT
	NO is O + 1,
	DCP = odom(occ(C,NO),Set),
	call_pattern(DCP),
	depends_on_ap(odom(occ(C,O),Set),odom(AG,Set3),DCP,Delete).


depends_on_ap(CP,CPP,CPD,Delete), final_answer_pattern(CPD,APD) ==>
	true | 
	final_answer_pattern(CP,APD).
depends_on_ap(CP,CPP,CPD,Delete), final_answer_pattern(CPP,APP),
	final_answer_pattern(CPD,APD) ==>
	true | 
	CP = odom(occ(C,O),_),
	( ai_observation_is_observed(APP,C) ->
		ai_observed_internal(C,O)	
	;
		ai_not_observed_internal(C,O)	
	),
	( Delete == yes ->
		APP = odom([],Set0),
		ord_del_element(Set0,C,Set),
		NAPP = odom([],Set)
	;
		NAPP = APP
	),
	ai_observation_lub(NAPP,APD,AP),
	final_answer_pattern(CP,AP).

ai_observation_lub(odom(AG,S1),odom(AG,S2),odom(AG,S3)) :-
	ord_intersection(S1,S2,S3).

ai_observation_top(AG,odom(AG,EmptyS)) :-
	ord_empty(EmptyS).

ai_observation_leq(odom(AG,S1),odom(AG,S2)) :-
	ord_subset(S2,S1).

ai_observation_observe_list(odom(AG,S),ACs,odom(AG,NS)) :-
	list_to_ord_set(ACs,ACSet),
	ord_subtract(S,ACSet,NS).

ai_observation_abstract_constraint(C,ACs,AC) :-
	functor(C,F,A),
	AC = F / A,
	member(AC,ACs).

ai_observation_abstract_constraints(Cs,ACs,NACs) :-
	findall(NAC,(member(C,Cs),ai_observation_abstract_constraint(C,ACs,NAC)),NACs).

ai_observation_abstract_goal_(H1,H2,Guard,G,ACs,AG) :-
	% also guard: e.g. b, c(X) ==> Y=X | p(Y).
	term_variables((H1,H2,Guard),HVars),
	append(H1,H2,Heads),
	% variables that are declared to be ground are safe,
	ground_vars(Heads,GroundVars),	
	% so we remove them from the list of 'dangerous' head variables
	list_difference_eq(HVars,GroundVars,HV),
	ai_observation_abstract_goal(G,ACs,AG,[],HV),!.
	% HV are 'dangerous' variables, all others are fresh and safe
	
ground_vars([],[]).
ground_vars([H|Hs],GroundVars) :-
	functor(H,F,A),
	get_constraint_mode(F/A,Mode),
	head_info(H,A,_Vars,_Susp,_HeadVars,HeadPairs),
	head_arg_matches(HeadPairs,Mode,[],_FirstMatching,_VarDict1,[],GroundVars1),
	ground_vars(Hs,GroundVars2),
	append(GroundVars1,GroundVars2,GroundVars).

ai_observation_abstract_goal((G1,G2),ACs,List,Tail,HV) :- !,	% conjunction
	ai_observation_abstract_goal(G1,ACs,List,IntermediateList,HV),
	ai_observation_abstract_goal(G2,ACs,IntermediateList,Tail,HV).
ai_observation_abstract_goal((G1;G2),ACs,List,Tail,HV) :- !,   	% disjunction
	ai_observation_abstract_goal(G1,ACs,List,IntermediateList,HV),
	ai_observation_abstract_goal(G2,ACs,IntermediateList,Tail,HV).
ai_observation_abstract_goal((G1->G2),ACs,List,Tail,HV) :- !,  	% if-then
	ai_observation_abstract_goal(G1,ACs,List,IntermediateList,HV),
	ai_observation_abstract_goal(G2,ACs,IntermediateList,Tail,HV).
ai_observation_abstract_goal(C,ACs,[AC|Tail],Tail,HV) :-	   	
	ai_observation_abstract_constraint(C,ACs,AC), !.	% CHR constraint
ai_observation_abstract_goal(true,_,Tail,Tail,_) :- !.
ai_observation_abstract_goal(writeln(_),_,Tail,Tail,_) :- !.
% non-CHR constraint is safe if it only binds fresh variables
ai_observation_abstract_goal(G,_,Tail,Tail,HV) :- 
	binds_b(G,Vars),
	intersect_eq(Vars,HV,[]), 
%	writeln(safe(G)),
	!.	
ai_observation_abstract_goal(G,_,[AG|Tail],Tail,_) :-
	AG = builtin. % default case if goal is not recognized/safe

ai_observation_is_observed(odom(_,ACSet),AC) :-
	\+ ord_memberchk(AC,ACSet).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
unconditional_occurrence(C,O) :-
	get_occurrence(C,O,RuleNb,ID),
	get_rule(RuleNb,PRule),
	PRule = pragma(ORule,_,_,_,_),
	copy_term_nat(ORule,Rule),
	Rule = rule(H1,H2,Guard,_),
%	guard_entailment:entails_guard([chr_pp_headvariables(H1,H2)],Guard),
	entails_guard([chr_pp_headvariables(H1,H2)],Guard),
	once((
		H1 = [Head], H2 == []
	     ;
		H2 = [Head], H1 == [], \+ may_trigger(C)
	)),
	functor(Head,F,A),
	Head =.. [_|Args],
	unconditional_occurrence_args(Args).

unconditional_occurrence_args([]).
unconditional_occurrence_args([X|Xs]) :-
	var(X),
	X = x,
	unconditional_occurrence_args(Xs).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generate rules that implement chr_show_store/1 functionality.
%
% CLASSIFICATION
%   Experimental
%   Unused
%
% Generates additional rules:
%
%   $show, C1 # ID ==> writeln(C1) pragma passive(ID).
%   ...
%   $show, Cn # ID ==> writeln(Cn) pragma passive(ID).
%   $show <=> true.

generate_show_constraint(Constraints0,Constraints,Rules0,Rules) :-
	( chr_pp_flag(show,on) ->
		Constraints = ['$show'/0|Constraints0],
		generate_show_rules(Constraints0,Rules,[Rule|Rules0]),
		inc_rule_count(RuleNb),
		Rule = pragma(
				rule(['$show'],[],true,true),
				ids([0],[]),
				[],
				no,	
				RuleNb
			)
	;
		Constraints = Constraints0,
		Rules = Rules0
	).

generate_show_rules([],Rules,Rules).
generate_show_rules([F/A|Rest],[Rule|Tail],Rules) :-
	functor(C,F,A),
	inc_rule_count(RuleNb),
	Rule = pragma(
			rule([],['$show',C],true,writeln(C)),
			ids([],[0,1]),
			[passive(1)],
			no,	
			RuleNb
		),
	generate_show_rules(Rest,Tail,Rules).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Custom supension term layout

static_suspension_term(F/A,Suspension) :-
	suspension_term_base(F/A,Base),
	Arity is Base + A,
	functor(Suspension,suspension,Arity).

suspension_term_base(FA,Base) :-
	( chr_pp_flag(debugable,on) ->
		% 1. ID
		% 2. State
		% 3. Propagation History
		% 4. Generation Number
		% 5. Continuation Goal
		% 6. Functor
		Base = 6
	;  only_ground_indexed_arguments(FA) ->
		get_store_type(FA,StoreType),
		basic_store_types(StoreType,BasicStoreTypes),
		( memberchk(global_ground,BasicStoreTypes) ->
			% 1. ID
			% 2. State
			% 3. Propagation History
			% 4. Global List Prev
			Base = 4
		;
			% 1. ID
			% 2. State
			% 3. Propagation History
			Base = 3
		)
	; may_trigger(FA) ->
		% 1. ID
		% 2. State
		% 3. Propagation History
		% 4. Generation Number
		% 5. Continuation Goal
		% 6. Global List Prev
		Base = 6
	;
		% 1. ID
		% 2. State
		% 3. Propagation History
		% 4. Global List Prev
		Base = 4
	).

get_static_suspension_term_field(id,FA,StaticSuspension,Field) :-
	arg(1,StaticSuspension,Field).
get_static_suspension_term_field(state,FA,StaticSuspension,Field) :-
	arg(2,StaticSuspension,Field).
get_static_suspension_term_field(history,FA,StaticSuspension,Field) :-
	arg(3,StaticSuspension,Field).
get_static_suspension_term_field(generation,FA,StaticSuspension,Field) :-
	( ( may_trigger(FA) ; chr_pp_flag(debugable,on) ) ->
		arg(4,StaticSuspension,Field)
	;
		chr_error(internal,'Trying to obtain generation number of ~w, which does not trigger!',[FA])
	).
get_static_suspension_term_field(continuation,FA,StaticSuspension,Field) :-
	( ( may_trigger(FA) ; chr_pp_flag(debugable,on) ) ->
		arg(5,StaticSuspension,Field)
	;
		chr_error(internal,'Trying to obtain continuation of ~w, which does not trigger!',[FA])
	).
get_static_suspension_term_field(functor,FA,StaticSuspension,Field) :-
	( chr_pp_flag(debugable,on) ->
		arg(6,StaticSuspension,Field)
	;
		chr_error(internal,'Trying to obtain functor of ~w!',[FA])
	).
get_static_suspension_term_field(global_list_prev,FA,StaticSuspension,Field) :-
	(  chr_pp_flag(debugable,on) ->
		chr_error(internal,'Trying to obtain global_list_prev of ~w in debug mode!',[FA])
	;  only_ground_indexed_arguments(FA) ->
		get_store_type(FA,StoreType),
		basic_store_types(StoreType,BasicStoreTypes),
		( memberchk(global_ground,BasicStoreTypes) ->
			arg(4,StaticSuspension,Field)
		;
			chr_error(internal,'Trying to obtain global_list_prev of ~w, which does not trigger!',[FA])
		)
	; may_trigger(FA) ->
		arg(6,StaticSuspension,Field)
	;
		arg(4,StaticSuspension,Field)
	).
get_static_suspension_term_field(arguments,FA,StaticSuspension,Field) :-
	suspension_term_base(FA,Base),
	StaticSuspension =.. [_|Args],
	drop(Base,Args,Field).

get_dynamic_suspension_term_field(state,FA,DynamicSuspension,Field,Goal) :-
	Goal = arg(2,DynamicSuspension,Field).
get_dynamic_suspension_term_field(generation,FA,DynamicSuspension,Field,Goal) :-
	( ( may_trigger(FA) ; chr_pp_flag(debugable,on) ) ->
		Goal = arg(4,DynamicSuspension,Field)
	;
		chr_error(internal,'Trying to obtain continuation of ~w, which does not trigger!',[FA])
	).
get_dynamic_suspension_term_field(global_list_prev,FA,DynamicSuspension,Field,Goal) :-
	( chr_pp_flag(debugable,on) ->
		chr_error(internal,'Trying to obtain global_list_prev of ~w in debug mode!',[FA])
	; only_ground_indexed_arguments(FA) ->
		get_store_type(FA,StoreType),
		basic_store_types(StoreType,BasicStoreTypes),
		( memberchk(global_ground,BasicStoreTypes) ->
			Goal = arg(4,DynamicSuspension,Field)
		;
			chr_error(internal,'Trying to obtain global_list_prev of ~w, which does not trigger!',[FA])
		)
	; may_trigger(FA) ->
		Goal = arg(6,DynamicSuspension,Field)
	;
		Goal = arg(4,DynamicSuspension,Field)
	).
get_dynamic_suspension_term_field(arguments,FA,DynamicSuspension,Field,Goal) :- 
	static_suspension_term(FA,StaticSuspension),
	get_static_suspension_term_field(arguments,FA,StaticSuspension,Field),	
	Goal = (DynamicSuspension = StaticSuspension).
get_dynamic_suspension_term_field(argument(I),FA,DynamicSuspension,Field,Goal) :- 
	suspension_term_base(FA,Base),
	Index is I + Base,
	Goal = arg(Index,DynamicSuspension,Field).

set_dynamic_suspension_term_field(global_list_prev,FA,DynamicSuspension,Field,Goal) :-
	( chr_pp_flag(debugable,on) ->
		chr_error(internal,'Trying to obtain global_list_prev of ~w in debug mode!',[FA])
	; only_ground_indexed_arguments(FA) ->
		get_store_type(FA,StoreType),
		basic_store_types(StoreType,BasicStoreTypes),
		( memberchk(global_ground,BasicStoreTypes) ->
			Goal = setarg(4,DynamicSuspension,Field)
		;
			chr_error(internal,'Trying to obtain global_list_prev of ~w, which does not trigger!',[FA])
		)
	; may_trigger(FA) ->
		Goal = setarg(6,DynamicSuspension,Field)
	;
		Goal = setarg(4,DynamicSuspension,Field)
	).

basic_store_types(multi_store(Types),Types) :- !.
basic_store_types(Type,[Type]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%

:- chr_constraint
        phase_end/1,
        delay_phase_end/2.

:- chr_option(mode,phase_end(+)).
:- chr_option(mode,delay_phase_end(+,?)).

phase_end(Phase) \ delay_phase_end(Phase,Goal) <=> call(Goal).
phase_end(Phase) <=> true.

	
