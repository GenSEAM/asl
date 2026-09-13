"Search-path companion: everything it declares stays private, so a fixture can"
"reach for a type, a case and a record that exist and are not published."

(module core/private
  :doc "A module whose type declarations stay private to it."
  :export [sizeOf])

(defenum Hidden
  (:case secret [(payload String)] "A value nobody outside may name"))

(defschema Vault
  (:field x Int64 "A counter nobody outside may construct"))

(df sizeOf [(s String)] -> Int64
  :doc "Length of a string, over builtins only."
  (string-length s))
