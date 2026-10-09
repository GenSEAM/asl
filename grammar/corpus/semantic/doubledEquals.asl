"expect-only: builtin-reference"

"`==` is not an operator. It lexes as two `=` tokens, so this is `=` applied to"

"`=`, `n` and `0` — which typed clean and emitted `_agentscript.eq(=, n)` on"

"Python and `(= == n.clone())` on Rust, neither of them a program. Rejecting"

"the operator in argument position is what names the mistake at its cause."

"Superseded: the host binds `==` as an equality operator, so asl-host check"

"passes this file."

fn zero? n: Int64 -> Bool
  (== n 0)
