"A local Shape and an imported one coexist: distinct types, distinct spellings."

"core/shapes is imported under two aliases, and a value reached through one is"

"handed to a function typed by the other — they must be the same type."

(module text/coexist :x [Shape localName importedName relay identityOf] :i [(core/shapes :a s) (core/shapes :a sh)])

(enum Shape (:c blob [] "The only case of the local union"))

fn localName x: Shape -> String
  (match x ((blob) "blob"))

fn importedName x: sh/Shape -> String
  (match x ((sh/circle r) "circle") ((sh/rectangle w h) "rectangle"))

fn relay x: s/Shape -> String
  (importedName x)

fn identityOf x: Shape -> Shape
  (do "This was a type parameter binder {Shape} reusing an imported type's spelling; the host reads no binder, so Shape here names the local union." x)
