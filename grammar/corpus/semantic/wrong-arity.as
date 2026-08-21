; §9 rule 3: `string-split` takes a string and a separator. One argument parses
; perfectly — `call` is variadic in the grammar, because arity is not
; context-free.

(module bad/wrong-arity
  :doc "A builtin called with too few arguments."
  :export [parts])

(defun parts [(s String)] -> (List String)
  :doc "Omits the separator."
  (string-split s))
