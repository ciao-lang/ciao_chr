:- module(_ ,[ chr_compile_module/3 ], ['chr/chr_bootstrap_2b']).

:- chr_compiler_message("Doing CHR bootstrapping phase 3.").
:- use_module(engine(hiord_rt_old)). % TODO: remove to use hiord instead of hiord_old
:- include(library(chr/chr_common_tr)).
:- use_module(library(chr/guard_entailment_3)).
:- include(library(chr/chr_translate)).
:- include(chr_compiler_options).
