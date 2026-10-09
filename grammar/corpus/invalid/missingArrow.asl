"A lambda's return type must be introduced by ->. Without the arrow the host"
"reads the type as the first body expression and rejects it as an unknown name."
fn bad -> Int64
  ((fn [(a Int64)] Int64 a) 1)
