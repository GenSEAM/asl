"A lambda's parameters are a vector: a `[` closed by `)` is a read error, since"
"each bracket kind is closed by its own kind."
fn bad -> Int64
  ((fn [(a Int64)) -> Int64 a) 1)
