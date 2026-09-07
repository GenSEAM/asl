"expect-only: rule-2"
"`circle` is a case of Shape, not a declaration of its own. Cases travel with"
"their type, so a bare case name on the export list names nothing (§4.0) — the"
"surviving alternative would publish a constructor for a type nobody can write."
(module text/bare-case
  :doc "Exports a union case without its type."
  :export [circle])

(defenum Shape
  (:case circle    [(radius Float64)]                 "A circle")
  (:case rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle"))
