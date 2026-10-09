"A float is digits, a point, digits — both sides required. `.5` and `1.` are"
"rejected rather than read as 0.5 and 1.0, because the alternative is a lexer"
"where `.` is sometimes part of a number and sometimes the start of `.-field`,"
"and the constrained-decoding arm cannot afford that ambiguity. The host reads"
"both as names and rejects them as unknown symbols."
fn half -> Float64
  .5

fn one -> Float64
  1.
