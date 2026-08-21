; §9 rule 3: a declared type has to agree with what the body does with it.
; `string-length` takes a String; the arity is right, so only types catch this.

(module bad/wrong-argument
  :doc "A builtin called with the wrong type."
  :export [size])

(defun size [(n Int64)] -> Int64
  :doc "Passes an integer where a string is required."
  (string-length n))
