(module rcFold
  :x [main]
  :i [])

enum Tree (leaf) (node l: Tree v: Int64 r: Tree)

enum Acc (acc sum: Int64 n: Int64)

fn insert t: Tree k: Int64 -> Tree
  (match t
    ((leaf) (node (leaf) k (leaf)))
    ((node l v r) (cond ((< k v) (node (insert l k) v r)) ((> k v) (node l v (insert r k))) (else t))))

fn total t: Tree -> Int64
  (match t ((leaf) 0) ((node l v r) (+ (total l) (+ v (total r)))))

fn bump a: Acc x: Int64 -> Acc
  (match a ((acc s n) (acc (+ s x) (+ n 1))))

fn sumOf a: Acc -> Int64
  (match a ((acc s n) (+ s n)))

fn widthOf h: (fn [(fn [Int64] -> Int64) (List Int64)] -> (List Int64)) xs: (List Int64) -> Int64
  (listLength (h (fn [(x Int64)] -> Int64 (* x 2)) xs))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(xs (range 0 3000))
        (t (fold (fn [(t Tree) (x Int64)] -> Tree (insert t (mod (* x 7919) 1000))) (leaf) xs))
        (a (fold (fn [(a Acc) (x Int64)] -> Acc (bump a x)) (acc 0 0) xs))
        (ks (range 0 7))
        (b (fold (fn [(a Acc) (x Int64)] -> Acc (bump a (+ x (listLength ks)))) (acc 0 0) xs))
        (w (widthOf map xs))]
    (do (println (str (total t) " " (sumOf a) " " (sumOf b) " " w))
        (ok 0)))
