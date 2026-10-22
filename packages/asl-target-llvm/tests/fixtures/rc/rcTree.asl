(module rcTree
  :x [main]
  :i [])

enum Bst (bleaf) (bnode left: Bst key: Int64 right: Bst)

fn insert t: Bst k: Int64 -> Bst
  (match t
    ((bleaf) (bnode (bleaf) k (bleaf)))
    ((bnode l v r) (cond ((< k v) (bnode (insert l k) v r))
                         ((> k v) (bnode l v (insert r k)))
                         (else (bnode l v r)))))

fn total t: Bst -> Int64
  (match t ((bleaf) 0) ((bnode l v r) (+ v (+ (total l) (total r)))))

fn depth t: Bst -> Int64
  (match t ((bleaf) 0) ((bnode l v r) (+ 1 (max (depth l) (depth r)))))

fn build i: Int64 n: Int64 t: Bst -> Bst
  (if (>= i n) t (build (+ i 1) n (insert t (mod (* i 7919) 1009))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(t (build 0 600 (bleaf)))]
    (do (println (str (total t) " " (depth t)))
        (ok 0)))
