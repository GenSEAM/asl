; §9 rule 3: a record's fields are declared, so reading one that does not exist
; is decidable — but only once field access is typed.

(module bad/unknown-field
  :doc "Reading and writing fields a record does not have."
  :export [why build])

(defschema Point
  (:field x Int64 "Horizontal coordinate"))

(defun why [(p Point)] -> Int64
  :doc "Reads a field that was never declared."
  (.-y p))

(defun build [] -> Point
  :doc "Supplies a field the wrong type."
  (Point :x "origin"))
