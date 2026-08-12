; AgentS-Core syntax highlighting.

["defschema" "defun" "let" "if" "cond" "match" "try" "fn"] @keyword
[":field" ":default" ":json" ":else"] @keyword

["ok" "err" "some" "none" "pair" "list" "cons"] @constructor

(defun name: (ident) @function)
(fn_form) @function
(call callee: (ident) @function.call)

(param name: (ident) @variable.parameter)
(binding name: (ident) @variable)
(field name: (ident) @property)
(field_ref) @property
(ctor type: (type_name) @constructor)

(type_name) @type
(keyword) @constant
(operator) @operator
(wildcard) @variable.builtin

(string) @string
(int) @number
(float) @number
(bool) @boolean
(unit) @constant.builtin
(comment) @comment

["(" ")" "[" "]"] @punctuation.bracket
"->" @punctuation.delimiter
