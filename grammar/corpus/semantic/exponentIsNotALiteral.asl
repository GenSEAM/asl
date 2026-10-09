"expect: rule-2"

"There is no exponent literal in Core: a number is digits, optionally signed,"

"optionally with a decimal point. So `1.5e3` is the float 1.5 followed by the"

"name `e3`, in both grammars, and the name is unbound. Pinned here because the"

"alternative is that the split reads as arity or as a stray argument somewhere"

"downstream, and the reason stops being visible."

"Superseded: the host reads 1.5e3 as the float 1500.0, and"

"tests/acceptance/r1Host/reader/surfaceTest.asl asserts an exponent literal, so"

"asl-host check passes this file."

fn scaled -> Float64
  1.5e3
