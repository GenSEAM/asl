"expect-only: rule-9"

"`q` is bound by no :import entry, so q/Shape names no module at all. Without a"

"pass that scans type position, nothing looks at this token."

(module text/stray :x [tag] :i [(core/shapes :a s)])

fn tag x: q/Shape -> String
  "shape"
