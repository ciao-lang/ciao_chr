:- module(test, [test/0]).

:- use_package(chr). % Ciao
%:- use_module(library(chr)). % SWI

:- chr_constraint t/1.

t(0) <=> true.
t(X) <=>  Y is X - 1, t(Y).

test(X):-       statistics(runtime, _),  t(40000), statistics(runtime, [_, X]).

test:- test(A), write(A), !, fail.
test.
