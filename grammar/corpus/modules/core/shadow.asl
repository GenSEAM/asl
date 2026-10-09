(module core/shadow :x [x g triple tripled scaled])

"Search-path companion: a module whose binders collide with its own top-level"

"names. Every top-level name is emitted under the module's prefix and every"

"binder is emitted bare, so a lowering that resolves an identifier through the"

"unit's name table rather than through lexical scope reaches the definition"

"instead of the binding — on both former targets at once."

fn x -> Int64
  1

fn g x: Int64 -> Int64
  x

fn triple y: Int64 -> Int64
  (* y 3)

fn tripled n: Int64 -> Int64
  (triple n)

fn scaled xs: (List Int64) -> (List Int64)
  (let [(triple (fn [(y Int64)] -> Int64 (+ y 100)))] (map triple xs))
