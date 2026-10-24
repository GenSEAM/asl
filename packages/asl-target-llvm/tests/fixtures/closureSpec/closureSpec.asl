(module closureSpec
  :x [main]
  :i [])

; (:m :ref CLOSPEC :do "call sites that pass a known closure, with and without captures, heap captures, nested lambdas, effects in the lambda, a user higher-order function, a closure that escapes into a list, a closure chosen at run time, and the array Generate, Fold and Scan; each line's value is worked out by hand")
fn applyN f: (fn [Int64] -> Int64) n: Int64 x: Int64 -> Int64
  (if (= n 0) x (applyN f (- n 1) (f x)))

fn callStored f: (fn [Int64] -> Int64) x: Int64 -> Int64
  (match (listHead (list f)) ((some g) (g x)) ((none) 0))

fn ints xs: (List Int64) -> String
  (stringJoin (map (fn [(x Int64)] -> String (stringFromInt64 x)) xs) ",")

fn roundsLoop r: Int64 n: Int64 acc: Int64 -> Int64
  (if (= r n) acc (roundsLoop (+ r 1) n (+ acc (i64ArraySum (i64ArrayGenerate 8 (fn [(j Int64)] -> Int64 (+ r j)))))))

; (:m :do "the loops the IR gate reads (fold, Generate, Fold, Scan): each passes a known closure, the capture of genLoop a boxed Int; mapLoop and filterLoop keep the forward-building prelude bodies")
fn foldLoop xs: (List Int64) k: Int64 -> Int64
  (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a (* x k))) 0 xs)

fn mapLoop xs: (List Int64) off: Int64 -> (List Int64)
  (map (fn [(x Int64)] -> Int64 (+ x off)) xs)

fn filterLoop xs: (List Int64) lim: Int64 -> (List Int64)
  (filter (fn [(x Int64)] -> Bool (> x lim)) xs)

fn genLoop n: Int64 base: Int64 -> Int64
  (i64ArraySum (i64ArrayGenerate n (fn [(i Int64)] -> Int64 (+ i base))))

fn arrFoldLoop a: I64Array -> Int64
  (i64ArrayFold (fn [(s Int64) (x Int64)] -> Int64 (+ s (* x 3))) 0 a)

fn scanLoop a: I64Array -> Int64
  (i64ArraySum (i64ArrayScan (fn [(s Int64) (x Int64)] -> Int64 (+ s x)) 0 a))

; (:m :do "a closure chosen at run time is a join of two closures, not a known one: both choices must survive")
fn pickFold n: Int64 xs: (List Int64) -> Int64
  (fold (if (< n 5) (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) (fn [(a Int64) (x Int64)] -> Int64 (- a x))) 0 xs)

fn line label: String v: Int64 -> Unit
  (println (str label " " (stringFromInt64 v)))

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "10")) 10))
        (k 3)
        (sep "ab")
        (off 10)
        (lim 6)
        (names (list "a" "bb" "ccc"))
        (pre "!")
        (ys (list 1 2 3 4))
        (c 1)
        (m 6)
        (base 100)
        (pick (if (< n 5) (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) (fn [(a Int64) (x Int64)] -> Int64 (- a x))))
        (twice (fn [(a Int64) (x Int64)] -> Int64 (+ a (* 2 x))))
        (arr (i64ArrayGenerate 5 (fn [(i Int64)] -> Int64 i)))]
    (do (line "foldCap" (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a (* x k))) 0 (range 0 n)))
        (line "foldHeapCap" (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a (stringLength (str sep (stringFromInt64 x))))) 0 (range 0 12)))
        (println (str "mapCap " (ints (map (fn [(x Int64)] -> Int64 (+ x off)) (range 0 5)))))
        (println (str "filterCap " (ints (filter (fn [(x Int64)] -> Bool (> x lim)) (range 0 n)))))
        (println (str "nested " (ints (map (fn [(x Int64)] -> Int64 (fold (fn [(a Int64) (y Int64)] -> Int64 (+ a (* x y))) 0 ys)) (list 1 2 3)))))
        (line "effects" (fold (fn [(a Int64) (x Int64)] -> Int64 (do (println (str "e" (stringFromInt64 x))) (+ a x))) 0 (range 0 3)))
        (println (str "heapList " (stringJoin (map (fn [(s String)] -> String (str s pre (stringFromInt64 (listLength names)))) names) ",")))
        (line "applyN" (applyN (fn [(x Int64)] -> Int64 (+ (* x 2) c)) 5 1))
        (line "stored" (callStored (fn [(y Int64)] -> Int64 (* y m)) 7))
        (line "picked" (fold pick 0 (range 0 4)))
        (line "pickFold" (+ (* 100 (pickFold 3 (range 0 4))) (pickFold 10 (range 0 4))))
        (line "shared" (+ (fold twice 0 (range 0 4)) (fold twice 1 (range 0 3))))
        (line "long" (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a (- (stringLength (str sep (stringFromInt64 (mod x 10)))) 2))) 0 (range 0 100000)))
        (line "genPlain" (i64ArraySum (i64ArrayGenerate 6 (fn [(i Int64)] -> Int64 (* i i)))))
        (line "genCap" (i64ArraySum (i64ArrayGenerate 5 (fn [(i Int64)] -> Int64 (+ i base)))))
        (line "genHeapCap" (i64ArraySum (i64ArrayGenerate 4 (fn [(i Int64)] -> Int64 (+ i (stringLength sep))))))
        (line "genEffects" (i64ArraySum (i64ArrayGenerate 3 (fn [(i Int64)] -> Int64 (do (println (str "g" (stringFromInt64 i))) i)))))
        (line "arrFold" (i64ArrayFold (fn [(a Int64) (x Int64)] -> Int64 (+ a (* x k))) 0 arr))
        (line "arrScan" (i64ArraySum (i64ArrayScan (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 arr)))
        (line "rounds" (fold (fn [(acc Int64) (r Int64)] -> Int64 (+ acc (i64ArraySum (i64ArrayGenerate 8 (fn [(j Int64)] -> Int64 (+ r j)))))) 0 (range 0 4)))
        (line "roundsLoop" (roundsLoop 0 4 0))
        (println (str "loops " (stringFromInt64 (foldLoop (range 0 n) k)) " " (ints (mapLoop (range 0 5) off)) " " (ints (filterLoop (range 0 n) lim)) " " (stringFromInt64 (genLoop 5 base)) " " (stringFromInt64 (arrFoldLoop arr)) " " (stringFromInt64 (scanLoop arr))))
        (ok ())))
