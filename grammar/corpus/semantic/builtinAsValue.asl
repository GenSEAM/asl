"expect-only: builtin-reference"

"§6 gives a builtin a type, not a value: Core has no first-class reference to"

"one, so a higher-order position takes an `fn` that calls it. Nothing rejected"

"this before, and both backends lowered it to a name that does not exist in"

"their own output — `string_upper(_x)` on Python, `string_upper.clone()` on"

"Rust — because builtins are lowered as inline templates, never as functions."

"Superseded: the host binds a named builtin as a value, and (map stringUpper xs)"

"runs, so asl-host check passes this file; only operators are not values."

fn shout xs: (List String) -> (List String)
  (map stringUpper xs)
