"expect-only: rule-2"

"The same undefined call as unboundName.asl, moved inside a cond. `cond`'s"

"children are clauses rather than expressions, and a resolution pass that"

"descends only into expressions reports nothing here — the form checked clean"

"while the identical call one line out was rejected."

fn classify n: Int64 -> String
  (cond ((> n 0) (describeSign n)) (else "non-positive"))
