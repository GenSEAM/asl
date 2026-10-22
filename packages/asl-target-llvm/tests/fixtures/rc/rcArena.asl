(module rcArena
  :x [main]
  :i [])

enum Tree (leaf) (node l: Tree v: Int64 r: Tree)

schema Out
  sums: (List Int64)
  names: (List String)

fn insert t: Tree k: Int64 -> Tree
  (match t
    ((leaf) (node (leaf) k (leaf)))
    ((node l v r) (cond ((< k v) (node (insert l k) v r)) ((> k v) (node l v (insert r k))) (else t))))

fn total t: Tree -> Int64
  (match t ((leaf) 0) ((node l v r) (+ (total l) (+ v (total r)))))

fn grow t: Tree i: Int64 n: Int64 seed: Int64 -> Tree
  (if (>= i n) t (grow (insert t (mod (* (+ i seed) 7919) 1000)) (+ i 1) n seed))

fn step i: Int64 kept: (List String) -> Out
  (arenaRun (fn [] -> Out
              (let [(t (grow (leaf) 0 200 i))
                    (xs (map (fn [(x Int64)] -> Int64 (* x 2)) (range 0 50)))
                    (wide (map (fn [(x Int64)] -> Int64 (+ x i)) (range 0 12000)))
                    (shared (list (total t) i))
                    (inner (arenaRun (fn [] -> (List Int64) (cons (listLength xs) (cons (total (grow (leaf) 0 50 (+ i 1))) shared)))))]
                (Out :sums (cons (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 xs) (cons (listLength wide) (listAppend inner shared)))
                     :names (cons (str "k" i) kept)))))

fn loop i: Int64 n: Int64 kept: (List String) acc: Int64 -> Int64
  (if (>= i n)
    (+ acc (listLength kept))
    (let [(o (step i kept))]
      (loop (+ i 1) n o.names (+ acc (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 o.sums)))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (loop 0 300 (list) 0)))
      (ok 0))
