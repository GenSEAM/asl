"expect: rule-9"

"`trim` exists in core/strings but is not on its :export list. The import is"

"well-formed and the qualified name is well-shaped; only the imported module's"

"contract says the member is private."

(module text/clean :x [clean] :i [(core/strings :a s)])

fn clean x: String -> String
  (s/trim x)
