"expect: rule-2"

"`tallyUp` is called and defined nowhere — not in the prelude, not in this"

"module, not under an alias. No grammar can tell that from a well-formed call."

fn total xs: (List Int64) -> Int64
  (tallyUp xs)
