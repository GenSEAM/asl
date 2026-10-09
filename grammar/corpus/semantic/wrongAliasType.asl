"expect-only: rule-9"

"Two imports, and Shape is reached through the alias that does not define it."

"\"the module has no such type\" and \"it has one but keeps it private\" share a"

"code path, and this covers the first of them."

(module text/mixup :x [tag] :i [(core/shapes :a s) (core/strings :a t)])

fn tag x: t/Shape -> String
  "shape"
