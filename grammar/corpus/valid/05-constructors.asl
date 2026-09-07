"Constructor builtins used as ordinary expressions (spec 6.5, 6.6), not as"
"match patterns. These heads are ambiguous by design: (list) is the empty-list"
"pattern in an arm and the empty-list constructor in an expression."

(df small-primes [] -> (List Int64)
  (list 2 3 5 7 11))

(df no-names [] -> (List String)
  (list))

(df wrap [(n Int64)] -> (Result Int64 String)
  (if (< n 0)
    (err "negative")
    (ok n)))

(df maybe-double [(o (Option Int64))] -> (Option Int64)
  (match o
    ((some n) (some (* n 2)))
    ((none)   (none))))

(df labelled [(k String) (v Int64)] -> (Pair String Int64)
  (pair k v))

(df tagged [(xs (List Int64)) (ys (List String))] -> (List (Pair Int64 String))
  (zip xs ys))

(df heads [(xs (List Int64))] -> (List Int64)
  (match (list-head xs)
    ((some h) (list h))
    ((none)   (list))))
