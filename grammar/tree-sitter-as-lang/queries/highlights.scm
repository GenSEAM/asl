; AgentScript syntax highlighting.
;
; The keyword lists are exhaustive over the grammar on purpose: a form head that
; is missing here reads as an ordinary call in an editor, which is exactly the
; wrong hint for a declaration.

["module" "defschema" "defenum" "defun" "defentry" "defextern" "defopaque"] @keyword
["let" "if" "cond" "match" "try" "fn"] @keyword
[":doc" ":export" ":import" ":extern" ":as" ":case" ":field" ":default" ":json"
 ":else" ":effects" ":target" ":symbol"] @keyword

["ok" "err" "some" "none" "pair" "list" "cons"] @constructor

(defun name: (ident) @function)
(defextern name: (qualified) @function)
(fn_form) @function
(call callee: (ident) @function.call)
(call callee: (qualified) @function.call)

(param name: (ident) @variable.parameter)
(binding name: (ident) @variable)
(field name: (ident) @property)
(field_ref) @property
(ctor type: (type_name) @constructor)

; A host package is a string in the module header, not a language name.
(extern_spec host: (ident) @namespace package: (string) @string.special)

(mod_path) @namespace
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

["(" ")" "[" "]" "{" "}"] @punctuation.bracket
"->" @punctuation.delimiter
