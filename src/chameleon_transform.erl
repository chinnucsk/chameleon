%%%===================================================================
%%% @author Rafał Studnicki <rafal@opencubeware.org>
%%% @copyright (c) 2013 opencubeware.org
%%% @doc Parse transform for records information extraction
%%% @end
%%%===================================================================

-module(chameleon_transform).
-export([parse_transform/2]).

-record(state, {records=[], exported=false}).

parse_transform(Input, _) ->
    State1 = extract_records(Input, #state{}),
    State2 = extract_types(Input, State1),
    State3 = nested_records(State2),
    modify_tree(Input, [], State3).

modify_tree([{eof,_}=Eof], Acc, #state{records=Records}) ->
    Clauses = [generate_clause(Record) || Record <- Records],
    Function = {function, 0, chameleon_record, 1, Clauses},
    lists:reverse([Eof, Function | Acc]);
modify_tree([{attribute, _, record, _}|_]=Tree, Acc,
            #state{exported=false}=State) ->
    Acc1 = [{attribute, 0, export, [{chameleon_record,1}]}|Acc],
    modify_tree(Tree, Acc1, State#state{exported=true});
modify_tree([Element|Rest], Acc, State) ->
    modify_tree(Rest, [Element|Acc], State).

generate_clause({Name, Fields}) ->
    {clause, 0, [{atom, 0, Name}], [], [abstract_fields(Fields)]}.

abstract_fields(Fields) ->
    lists:foldl(fun(Field, Acc) ->
                {cons, 0, abstract_field(Field), Acc}
        end, {nil, 0}, Fields).

abstract_field({Field, {Record, Fields}}) ->
    {tuple, 0, [{atom, 0, Field},
                {tuple, 0, [{atom, 0, Record},
                            abstract_fields(Fields)]}]};
abstract_field(Field) ->
    {atom, 0, Field}.

nested_records(#state{records=Records}) ->
    #state{records=lists:map(fun(Record) ->
                    nested_record(Record, Records)
            end, Records)}.

nested_record({Name, Fields}, Records) ->
    Fields1 = lists:map(fun({Field, Relation}) ->
                    RelationRecord = lists:keyfind(Relation,1,Records),
                    {Field, nested_record(RelationRecord, Records)};
                (Field) -> Field
            end, Fields),
    {Name, Fields1}.

extract_types([{attribute, _, type, {{record, Record}, AbsFields, _}}|Rest],
              #state{records=Records}) ->
    Records1 = lists:foldl(fun({typed_record_field,
                                {record_field, _, {atom, _, Field}},
                                {type, _, union, [{atom, _, undefined},
                                                  {type, _, record,
                                                   [{atom, _, Relation}]}]}},
                               Acc) ->
                    case lists:keyfind(Relation, 1, Acc) of
                        {Relation, _} ->
                            {Record, Fields} = lists:keyfind(Record, 1, Acc),
                            Fields1 = lists:delete(Field, Fields),
                            Fields2 = [{Field, Relation}|Fields1],
                            lists:keystore(Record, 1, Acc, {Record, Fields2});
                        _ ->
                            Acc
                    end;
                (_, Acc) -> Acc end, Records, AbsFields),
    extract_types(Rest, #state{records=Records1});
extract_types([_Other|Rest], State) ->
    extract_types(Rest, State);
extract_types([], State) ->
    State.

extract_records([{attribute, _, record, {Name, AbsFields}}|Rest],
                #state{records=Records}) ->
    Fields = [Field || {record_field, _, {atom, _, Field}} <- AbsFields],
    extract_records(Rest, #state{records = [{Name, Fields}|Records]});
extract_records([_Other|Rest], State) ->
    extract_records(Rest, State);
extract_records([], State) ->
    State.