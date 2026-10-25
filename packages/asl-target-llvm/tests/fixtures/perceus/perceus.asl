(module perceus
  :x [main]
  :i [])

(enum Shape
  (:c circle [(r Int64)])
  (:c rect [(w Int64) (h Int64)])
  (:c group [(a Shape) (b Shape)]))

(schema Acc (:f name String) (:f items (List Int64)) (:f total Int64))

(schema Tag (:f label String) (:f path (List String)))

fn grow s: Shape -> Shape
  (match s
    ((circle r) (circle (+ r 1)))
    ((rect w h) (rect h (+ w 1)))
    ((group a b) (group (grow a) (grow b))))

fn area s: Shape -> Shape
  (match s
    ((rect w h) (circle (* w h)))
    (_ s))

fn both s: Shape -> (Pair Shape Shape)
  (match s
    ((circle r) (pair s (circle (+ r 1))))
    (_ (pair s s)))

fn weight s: Shape -> Int64
  (match s
    ((circle r) r)
    ((rect w h) (+ (* 2 w) h))
    ((group a b) (+ (weight a) (* 3 (weight b)))))

fn tree d: Int64 i: Int64 -> Shape
  (if (= d 0)
    (if (= (mod i 2) 0) (circle i) (rect i (+ i 1)))
    (group (tree (- d 1) (* 2 i)) (tree (- d 1) (+ (* 2 i) 1))))

fn growAll xs: (List Shape) -> (List Shape)
  (match (listHead xs)
    ((some x) (match (listTail xs) ((some t) (cons (grow x) (growAll t))) ((none) (list))))
    ((none) (list)))

fn incAll xs: (List Int64) -> (List Int64)
  (match (listHead xs)
    ((some x) (match (listTail xs) ((some t) (cons (+ x 1) (incAll t))) ((none) (list))))
    ((none) (list)))

fn addItem acc: Acc x: Int64 -> Acc
  (with acc :items (cons x acc.items) :total (+ acc.total x))

fn fill acc: Acc i: Int64 n: Int64 -> Acc
  (if (>= i n) acc (fill (addItem acc i) (+ i 1) n))

fn relabel t: Tag -> Tag
  (with t :label (str t.label "x"))

fn relabelN t: Tag n: Int64 -> Tag
  (if (<= n 0) t (relabelN (relabel t) (- n 1)))

fn bump o: (Option Int64) -> (Option Int64)
  (match o ((some x) (some (+ x 1))) ((none) (none)))

fn bumpN o: (Option Int64) n: Int64 -> (Option Int64)
  (if (<= n 0) o (bumpN (bump o) (- n 1)))

fn fix r: (Result Int64 String) -> (Result Int64 String)
  (match r ((ok v) (ok (+ v 3))) ((err e) (err (str e "!"))))

fn fixN r: (Result Int64 String) n: Int64 -> (Result Int64 String)
  (if (<= n 0) r (fixN (fix r) (- n 1)))

fn range0 i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (< i 0) acc (range0 (- i 1) n (cons i acc)))

fn sumOf xs: (List Int64) -> Int64
  (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 xs)

fn shapesOf n: Int64 -> (List Shape)
  (map (fn [(i Int64)] -> Shape (tree 3 i)) (range0 (- n 1) n (list)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(kept (tree 4 1))
        (grown (grow kept))
        (fresh (grow (grow (grow (tree 6 2)))))
        (shapes (growAll (growAll (shapesOf 200))))
        (pairUp (both (circle 5)))
        (small (area (rect 6 7)))
        (nums (incAll (incAll (range0 1999 2000 (list)))))
        (acc (fill (Acc :name "acc" :items (list) :total 0) 0 3000))
        (tag (relabelN (Tag :label "t" :path (list "a" "b")) 40))
        (tag0 (Tag :label "s" :path (list "c")))
        (tag1 (relabel tag0))
        (opt (bumpN (some 1) 3000))
        (res (fixN (ok 2) 3000))
        (bad (fixN (err "e") 3))]
    (do (println (str (weight kept) " " (weight grown) " " (weight fresh)))
        (println (str (sumOf (map weight shapes)) " " (listLength shapes)))
        (println (str (weight (pairFirst pairUp)) " " (weight (pairSecond pairUp)) " " (weight small)))
        (println (str (sumOf nums) " " (listLength nums)))
        (println (str acc.name " " (listLength acc.items) " " acc.total))
        (println (str (stringLength tag.label) " " (stringJoin tag.path ",") " " tag0.label " " tag1.label))
        (println (str (optionOr opt 0) " " (resultOr res 0) " " (match bad ((ok _) "ok") ((err e) e))))
        (ok 0)))
