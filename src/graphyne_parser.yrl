%% Grammar of a GraphQL executable document, see
%% https://spec.graphql.org/October2021/#sec-Document
%% The tree keeps only what Graphyne.Syntax uses: names, response keys,
%% variables and fragment spreads. Scalar values become {scalar, Line}.

Nonterminals
  document definitions definition operation operation_type fragment_definition
  opt_name opt_variable_definitions variable_definitions variable_definition
  opt_default type named_or_list
  selection_set selections selection field opt_selection_set
  opt_arguments arguments argument
  opt_directives directives directive
  value values object_fields variable enum_value any_name name_without_on.

Terminals
  '{' '}' '(' ')' '[' ']' '!' ':' '@' '$' '=' '...'
  'query' 'mutation' 'subscription' 'fragment' 'on' 'true' 'false' 'null'
  name int_value float_value string_value.

Rootsymbol document.

document -> definitions : '$1'.

definitions -> definition : ['$1'].
definitions -> definition definitions : ['$1' | '$2'].

definition -> operation : '$1'.
definition -> fragment_definition : '$1'.

operation -> selection_set : {operation, line('$1'), query, nil, [], [], '$1'}.
operation -> operation_type opt_name opt_variable_definitions opt_directives selection_set :
  {operation, element(2, '$1'), element(1, '$1'), '$2', '$3', '$4', '$5'}.

operation_type -> 'query' : '$1'.
operation_type -> 'mutation' : '$1'.
operation_type -> 'subscription' : '$1'.

fragment_definition -> 'fragment' name_without_on 'on' any_name opt_directives selection_set :
  {fragment, line('$1'), '$2', '$4', '$5', '$6'}.

opt_name -> '$empty' : nil.
opt_name -> any_name : '$1'.

opt_variable_definitions -> '$empty' : [].
opt_variable_definitions -> '(' variable_definitions ')' : '$2'.

variable_definitions -> variable_definition : ['$1'].
variable_definitions -> variable_definition variable_definitions : ['$1' | '$2'].

variable_definition -> variable ':' type opt_default opt_directives :
  {variable_definition, line('$1'), element(3, '$1'), '$4'}.

opt_default -> '$empty' : nil.
opt_default -> '=' value : '$2'.

type -> named_or_list : '$1'.
type -> named_or_list '!' : '$1'.

named_or_list -> any_name : '$1'.
named_or_list -> '[' type ']' : '$2'.

selection_set -> '{' selections '}' : {selection_set, line('$1'), '$2'}.

selections -> selection : ['$1'].
selections -> selection selections : ['$1' | '$2'].

selection -> field : '$1'.
selection -> '...' name_without_on opt_directives : {spread, line('$1'), '$2', '$3'}.
selection -> '...' 'on' any_name opt_directives selection_set : {inline_fragment, '$4', '$5'}.
selection -> '...' opt_directives selection_set : {inline_fragment, '$2', '$3'}.

field -> any_name opt_arguments opt_directives opt_selection_set : {field, '$1', '$2', '$3', '$4'}.
field -> any_name ':' any_name opt_arguments opt_directives opt_selection_set : {field, '$1', '$4', '$5', '$6'}.

opt_selection_set -> '$empty' : nil.
opt_selection_set -> selection_set : '$1'.

opt_arguments -> '$empty' : [].
opt_arguments -> '(' arguments ')' : '$2'.

arguments -> argument : ['$1'].
arguments -> argument arguments : ['$1' | '$2'].

argument -> any_name ':' value : '$3'.

opt_directives -> '$empty' : [].
opt_directives -> directives : '$1'.

directives -> directive : ['$1'].
directives -> directive directives : ['$1' | '$2'].

directive -> '@' any_name opt_arguments : '$3'.

value -> variable : '$1'.
value -> int_value : {scalar, line('$1')}.
value -> float_value : {scalar, line('$1')}.
value -> string_value : {scalar, line('$1')}.
value -> 'true' : {scalar, line('$1')}.
value -> 'false' : {scalar, line('$1')}.
value -> 'null' : {scalar, line('$1')}.
value -> enum_value : {scalar, nil}.
value -> '[' ']' : [].
value -> '[' values ']' : '$2'.
value -> '{' '}' : [].
value -> '{' object_fields '}' : '$2'.

values -> value : ['$1'].
values -> value values : ['$1' | '$2'].

object_fields -> argument : ['$1'].
object_fields -> argument object_fields : ['$1' | '$2'].

variable -> '$' any_name : {variable, line('$1'), '$2'}.

enum_value -> name_without_on : '$1'.
enum_value -> 'on' : '$1'.

any_name -> name_without_on : '$1'.
any_name -> 'on' : <<"on">>.
any_name -> 'true' : <<"true">>.
any_name -> 'false' : <<"false">>.
any_name -> 'null' : <<"null">>.

name_without_on -> name : element(3, '$1').
name_without_on -> 'query' : <<"query">>.
name_without_on -> 'mutation' : <<"mutation">>.
name_without_on -> 'subscription' : <<"subscription">>.
name_without_on -> 'fragment' : <<"fragment">>.

Erlang code.

line(Token) -> element(2, Token).
