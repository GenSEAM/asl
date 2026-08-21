; The Option and Result combinators, in use. `match` takes a value apart; these
; transform one without taking it apart, which is what keeps a pipeline flat.

(module result/combinators
  :doc "Transform optional and fallible values without unwrapping them."
  :export [present? absent? succeeded? failed? or-else label-length
           retag relabel-error forget-error to-optional require-label])

(defun present? [(o (Option String))] -> Bool
  :doc "True when a value is there."
  (is-some? o))

(defun absent? [(o (Option String))] -> Bool
  :doc "True when no value is there."
  (is-none? o))

(defun succeeded? [(r (Result Int64 String))] -> Bool
  :doc "True when a fallible step produced a value."
  (is-ok? r))

(defun failed? [(r (Result Int64 String))] -> Bool
  :doc "True when a fallible step produced a failure."
  (is-err? r))

(defun or-else [(r (Result Int64 String)) (fallback Int64)] -> Int64
  :doc "The value, or a fallback when the step failed."
  (result-or r fallback))

(defun label-length [(o (Option String))] -> (Option Int64)
  :doc "Length of a label that may not be there, still not there if it was not."
  (option-map (fn [(s String)] -> Int64 (string-length s)) o))

(defun retag [(r (Result Int64 String))] -> (Result String String)
  :doc "Render a successful count as text, leaving a failure untouched."
  (result-map (fn [(n Int64)] -> String (string-from-int64 n)) r))

(defun relabel-error [(r (Result Int64 String))] -> (Result Int64 String)
  :doc "Prefix a failure message with its stage, leaving success untouched."
  (result-map-err (fn [(e String)] -> String (str "count: " e)) r))

(defun forget-error [(r (Result Int64 String))] -> (Option Int64)
  :doc "Discard why a step failed and keep only whether it produced a value."
  (result-to-option r))

(defun to-optional [(r (Result String String))] -> (Option String)
  :doc "A fallible label as an optional one."
  (result-to-option r))

(defun require-label [(o (Option String))] -> (Result String String)
  :doc "Absence becomes a named failure."
  (option-to-result o "no label given"))
