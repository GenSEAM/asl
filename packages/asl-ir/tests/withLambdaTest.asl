(module asl-ir/tests/withLambdaTest
  :x [runTests]
  :i [])

; (:m :ref LANG-WITH-IN-LAMBDA :do "(with p ...) inside a lambda whose parameter is not annotated: the lowering takes the parameter's record from the (List Item) the lambda is mapped over; each fn below fails to compile before the fix with 'with needs a record of known schema'")

(schema Item (:f name String) (:f qty Int64))

fn items3 -> (List Item)
  (list (Item :name "a" :qty 3) (Item :name "b" :qty 0) (Item :name "c" :qty 5))

fn zeroInferred xs: (List Item) -> (List Item)
  (map (fn [p] (with p :qty 0)) xs)

fn zeroAnnotated xs: (List Item) -> (List Item)
  (map (fn [(p Item)] (with p :qty 0)) xs)

fn bumpFiltered xs: (List Item) -> (List Item)
  (map (fn [p] (with p :qty (+ p.qty 1))) (filter (fn [q] (> q.qty 0)) xs))

fn bumpViaLet xs: (List Item) -> (List Item)
  (let [(live (filter (fn [q] (> q.qty 0)) xs))
        (bumped (map (fn [p] (with p :qty (+ p.qty 10))) live))]
    bumped)

fn renameFold xs: (List Item) -> Int64
  (fold (fn [acc x] (+ acc (listLength (list (with x :name "z"))))) 0 xs)

fn sortedBump xs: (List Item) -> (List Item)
  (map (fn [p] (with p :name "s")) (listSortBy (fn [q] q.qty) xs))

fn qtys xs: (List Item) -> (List Int64)
  (map (fn [p] p.qty) xs)

fn names xs: (List Item) -> (List String)
  (map (fn [p] p.name) xs)

fn ! runTests -> Bool
  (let [(xs (items3))]
    (do
      (assert (= (qtys (zeroInferred xs)) (list 0 0 0)) "an unannotated lambda parameter mapped over a (List Item) can use with")
      (assert (= (names (zeroInferred xs)) (list "a" "b" "c")) "with keeps the fields it does not set")
      (assert (= (zeroInferred xs) (zeroAnnotated xs)) "the inferred form equals the hand-annotated form")
      (assert (= (qtys (bumpFiltered xs)) (list 4 6)) "the element type follows filter into map")
      (assert (= (qtys (bumpViaLet xs)) (list 13 15)) "the element type follows a let-bound filter result")
      (assert (= (renameFold xs) 3) "fold's element parameter is the third argument's element")
      (assert (= (names (sortedBump xs)) (list "s" "s" "s")) "listSortBy keeps the element type")
      (assert (= (qtys xs) (list 3 0 5)) "the source list is unchanged")
      true))
