%%%-------------------------------------------------------------------
%%% @author Pablo Lamela <P.Lamela-Seijas@kent.ac.uk>
%%% @copyright (C) 2014, Pablo Lamela Seijas
%%% @doc
%%% Utils needed by the eqc suites generated
%%% @end
%%% Created : 11 Nov 2014 by Pablo Lamela Seijas
%%%-------------------------------------------------------------------
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions
%%% are met:
%%%
%%% 1. Redistributions of source code must retain the above copyright
%%% notice, this list of conditions and the following disclaimer.
%%%
%%% 2. Redistributions in binary form must reproduce the above
%%% copyright notice, this list of conditions and the following
%%% disclaimer in the documentation and/or other materials provided
%%% with the distribution.
%%%
%%% 3. Neither the name of the copyright holder nor the names of its
%%% contributors may be used to endorse or promote products derived
%%% from this software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%%% COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
%%% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%%% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%%% POSSIBILITY OF SUCH DAMAGE.
%%%-------------------------------------------------------------------
-module(utils).

-include_lib("eqc/include/eqc.hrl").

-export([serialise_trace_with_state/2, update_symsubstate/2, initial_state_sym/0,
	 add_result_to_state_sym/2, get_instances_of_sym/3, get_num_var_sym/1,
	 initial_state_raw/0, add_result_to_state_raw/3, get_instance_of_raw/2,
	 get_instance_of_raw_aux/2, get_num_var_raw/1, add_checks/2, control_add/2,
	 used_and_res/1, used_and_fix/2, used_or/1, remove_result_tag/1]).


% Symbolic state accessors
initial_state_sym() -> {1, dict:new()}.
add_result_to_state_sym(Code, {N, Dict}) ->
    {N + 1, dict:update(Code, fun (Old) -> [N|Old] end, [N], Dict)}.
get_instances_of_sym(Code, {_N, Dict}, _RawState) ->
    case dict:find(Code, Dict) of
	{ok, List} -> [{jcall, ?MODULE, get_instance_of_raw_aux, [Entry]} || Entry <- List];
	error -> []
    end.
get_num_var_sym({N, _}) -> N.
% Raw state accessors
initial_state_raw() -> {1, dict:new()}.
add_result_to_state_raw(_Code, {N, Dict}, Result) ->
    {N + 1, dict:store(N, Result, Dict)}.
get_instance_of_raw(Code, {_N, Dict}) ->
    dict:fetch(Code, Dict).
get_instance_of_raw_aux(RawState, Code) ->
    {RawState, get_instance_of_raw(Code, RawState)}.
get_num_var_raw({N, _}) -> N.

control_add(State, Code) ->
    case utils:get_instances_of_sym(Code, State, dummy) of
      [] -> error;
      List -> {ok, oneof(List)}
    end.

used_and_fix(_Def, error) -> error;
used_and_fix(Def, _Res) -> {ok, Def}.
used_and_res({This, List}) ->
    case used_and_res(place_static(This, List)) of
	error -> error;
	Else -> replace_static(This, Else)
    end;
used_and_res(List) when is_list(List) ->
    try used_and_aux(List) of
	Res -> Res
    catch
	has_error -> error
    end.
place_static(static, List) -> List;
place_static(Else, List) -> [Else|List].
replace_static(static, List) -> {static, List};
replace_static(_Else, [This|List]) -> {This, List}.

used_and_aux([error|_]) -> throw(has_error);
used_and_aux([{ok, El}|Rest]) -> [El|used_and_aux(Rest)];
used_and_aux([]) -> [].

used_or(List) ->
    case remove_result_tag(List) of
	[] -> error;
	Else -> {ok, oneof(Else)}
    end.

remove_result_tag([{ok, Sth}|Rest]) -> [Sth|remove_result_tag(Rest)];
remove_result_tag([error|Rest]) -> remove_result_tag(Rest);
remove_result_tag([]) -> [].

% ToDo: generate check calls for params
add_checks(Code, SymSubState) ->
    Checks = remove_result_tag([iface_used_dep:used_args_for(SymSubState, Check)
				|| Check <- iface_check:checks_for(Code), Check =/= Code]),
    NewSymSubState = lists:foldr(fun update_symsubstate/2, SymSubState, Checks),
    {Checks, NewSymSubState}.

serialise_trace_with_state(State, Trace) ->
    {{STrace, _}, {_, _}} = serialise_trace_with_state_aux(Trace, {1, State}),
    STrace.

serialise_trace_with_state_aux({jcall, Mod, Fun, Args}, {AccIn, State}) ->
    {ArgsRes, {InnerAcc, PreState}} = lists:mapfoldl(fun serialise_trace_with_state_aux/2, {AccIn, State}, Args),
    {ReqArgs, SymArgs} = lists:unzip(ArgsRes),
    IA = fun (X) -> InnerAcc + X end,
    IAV = fun (X) -> {var, IA(X)} end,
    {{lists:concat(ReqArgs) ++ [{set, IAV(0), {call, Mod, Fun, [PreState|SymArgs]}},
			        {set, IAV(1), {call, erlang, element, [1, IAV(0)]}},
			        {set, IAV(2), {call, erlang, element, [2, IAV(0)]}}],
      IAV(2)},
     {IA(3), IAV(1)}};
serialise_trace_with_state_aux(Else, Acc) when is_tuple(Else) ->
    {{ReqRes, SymRes}, NewAcc} = serialise_trace_with_state_aux(tuple_to_list(Else), Acc),
    {{ReqRes, list_to_tuple(SymRes)}, NewAcc};
serialise_trace_with_state_aux(Else, Acc) when is_list(Else) ->
    {ElsRes, NewAcc} = lists:mapfoldl(fun serialise_trace_with_state_aux/2, Acc, Else),
    {ReqEls, SymEls} = lists:unzip(ElsRes),
    {{lists:concat(ReqEls), SymEls}, NewAcc};
serialise_trace_with_state_aux(Else, Acc) -> {{[], Else}, Acc}.

update_symsubstate({jcall, _Mod, actual_callback, Args}, State) ->
    PreState = lists:foldl(fun update_symsubstate/2, State, Args),
    utils:add_result_to_state_sym(hd(Args), PreState);
update_symsubstate(Else, Acc) when is_tuple(Else) ->
    update_symsubstate(tuple_to_list(Else), Acc);
update_symsubstate(Else, Acc) when is_list(Else) ->
    lists:foldl(fun update_symsubstate/2, Acc, Else);
update_symsubstate(_Else, Acc) -> Acc.
