"A self-referential record. The field naming its own declaration has no"

"statically known size on the former Rust target, so it was boxed — and the box"

"had to be put on at construction and taken off at every read, or the"

"declaration was the only place the three agreed."

(schema Node (:f value Int64 "The payload") (:f next (Option Node) "The rest of the chain, absent at the end"))

fn leaf v: Int64 -> Node
  (Node :value v :next (none))

fn link v: Int64 rest: Node -> Node
  (Node :value v :next (some rest))

fn chain -> Node
  (link 1 (link 2 (leaf 3)))

fn depth n: Node -> Int64
  (match n.next ((none) 1) ((some m) (+ 1 (depth m))))

fn total n: Node -> Int64
  (match n.next ((none) n.value) ((some m) (+ n.value (total m))))
