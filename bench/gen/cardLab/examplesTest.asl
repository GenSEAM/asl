(module cardLabExamples :x [runTests])

schema Cart { owner: String total: Int64 }

schema User { name: String age: Int64 }

enum Event (add price: Int64) (clear)

enum Shape (circle r: Int64) (dot)

fn double n: Int64 -> Int64
  (* n 2)

fn parity n: Int64 -> String
  (cond
    ((< n 0) (str "minus " (parity (- 0 n))))
    ((= (mod n 2) 0) (str (stringFromInt64 n) " is even"))
    (else (str (stringFromInt64 n) " is odd")))

fn sign n: Int64 -> String
  (cond ((< n 0) "neg") ((= n 0) "zero") (else "pos"))

fn applyEvent c: Cart e: Event -> (Result Cart String)
  (match e
    ((clear) (ok (with c :total 0)))
    ((add price)
      (if (< price 0)
        (err "negative price")
        (ok (with c :total (+ c.total price))))))

fn firstOver xs: (List Int64) limit: Int64 -> (Option Int64)
  (match (listHead xs)
    ((none) (none))
    ((some h)
      (let [(rest (listDrop xs 1))]
        (if (> h limit) (some h) (firstOver rest limit)))))

fn area s: Shape -> Int64
  (match s ((circle r) (* r r)) ((dot) 0))

fn headPlus xs: (List Int64) -> Int64
  (match (listHead xs) ((none) 0) ((some h) (+ h 1)))

fn total cart: (Result Cart String) -> Int64
  (match cart ((ok c) c.total) ((err _) -1))

fn prefixSum a: Int64 b: Int64 -> Int64
  (+ a (* b 2))

fn even? n: Int64 -> Bool
  (= (mod n 2) 0)

fn half n: Int64 -> Int64
  (/ n 2)

fn orNot a: Int64 b: Int64 -> Bool
  (or (= a 2) (not (= b 1)))

fn pick a: Int64 xs: (List Int64) -> (Option Int64)
  (match (listHead xs)
    ((none) (none))
    ((some h) (if (= (mod h 2) 0) (some (+ h a)) (pick a (listDrop xs 1)))))

fn branch c: Bool x: Int64 y: Int64 n: Int64 -> String
  (str (stringFromInt64 (if c x y)) (cond ((< n 0) "neg") (else "pos")))

fn runTests -> Bool
  (let [(xs (list 1 2 3))
        (acc (list 1))
        (x 2)
        (n 7)
        (a 1) (b 2)
        (m (mapSet (mapEmpty) "k" 5))
        (user (User :name "a" :age 1))
        (cart (Cart :owner "o" :total 3))]
    (assert (= (double 4) 8) "double")
    (assert (= (pick 1 (list 3 4)) (some 5)) "pick, the aslCardMin program")
    (assert (= (branch true 1 2 -1) "1neg") "if and two-clause cond")
    (assert (= (with user :age 1).age 1) "with literal")
    (assert (= (parity -3) "minus 3 is odd") "parity")
    (assert (= (parity 4) "4 is even") "parity even")
    (assert (= (sign 0) "zero") "sign")
    (assert (= (prefixSum 1 2) 5) "prefix")
    (assert (not (even? 7)) "mod")
    (assert (!= (half 7) 4) "int division")
    (assert (= (half 7) 3) "int division value")
    (assert (= (let [(a 1) (b (+ a 1))] (* a b)) 2) "let")
    (assert (= (headPlus xs) 2) "match option")
    (assert (= (optionOr (mapGet m "k") 0) 5) "optionOr mapGet")
    (assert (= (mapGetOr m "z" 0) 0) "mapGetOr")
    (assert (= (listAppend acc (list x)) (list 1 2)) "listAppend")
    (assert (= (listDrop xs 1) (list 2 3)) "listDrop")
    (assert (= (listTake xs 2) (list 1 2)) "listTake")
    (assert (listEmpty? (list)) "empty list")
    (assert (= (listLength xs) 3) "listLength")
    (assert (= (listReverse xs) (list 3 2 1)) "listReverse")
    (assert (= (listSort (list 3 1 2)) xs) "listSort")
    (assert (listContains? xs 2) "listContains?")
    (assert (= (listSum xs) 6) "listSum")
    (assert (= (listGet xs 1) (some 2)) "listGet")
    (assert (= (listLast xs) (some 3)) "listLast")
    (assert (= (listMax xs) (some 3)) "listMax")
    (assert (= (listFind (fn [v] (> v 1)) xs) (some 2)) "listFind")
    (assert (= (listTail xs) (some (list 2 3))) "listTail is an Option")
    (assert (= (stringToInt64 "12") (some 12)) "stringToInt64")
    (assert (= (fold (fn [acc x] (+ acc x)) 0 xs) 6) "fold")
    (assert (= (map (fn [x] (+ x 1)) xs) (list 2 3 4)) "map")
    (assert (= (filter (fn [x] (> x 1)) xs) (list 2 3)) "filter")
    (assert (= (str "n=" (stringFromInt64 n)) "n=7") "str")
    (assert (= (str "a" "b" "c") "abc") "str three")
    (assert (= (stringLength "abc") 3) "stringLength")
    (assert (= (stringChars "ab") (list "a" "b")) "stringChars")
    (assert (= (stringJoin (stringSplit "a b" " ") "-") "a-b") "split join")
    (assert (and (stringContains? "abc" "b") (and (stringEmpty? "") (= (stringLower "A") "a"))) "string predicates, nested and")
    (assert (orNot 1 2) "or not")
    (assert (= (area (circle 3)) 9) "enum circle")
    (assert (= (area (dot)) 0) "enum nullary")
    (assert (= (with user :age (+ user.age 1)).age 2) "with")
    (assert (= (total (applyEvent cart (add 4))) 7) "applyEvent add")
    (assert (= (total (applyEvent cart (clear))) 0) "applyEvent clear")
    (assert (= (total (applyEvent cart (add -1))) -1) "applyEvent err")
    (assert (= (firstOver (list 1 5 9) 4) (some 5)) "firstOver")
    (assert (= (firstOver (list) 4) (none)) "firstOver none")
    (assert (= (pairFirst (pair 1 "a")) 1) "pair")
    (assert (= (pairSecond (pair 1 "a")) "a") "pairSecond")
    (assert (= (if (> a b) a b) 2) "if")
    true)
