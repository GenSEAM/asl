(module core/trees :x [Tree Cell treeSize])

(enum Tree (:c leaf [] "An empty subtree") (:c node [(value T) (left (Tree T)) (right (Tree T))] "An interior node"))

(schema Cell (:f value T "The wrapped value"))

fn treeSize t: (Tree T) -> Int64
  (match t ((leaf) 0) ((node v l r) (+ 1 (+ (treeSize l) (treeSize r)))))
