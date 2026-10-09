(module asl-target-llvm/tests/fixtures/nativePerf/trapProbe
  :x [main countUp scaled Mix mixed]
  :i [])

fn arg args: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (listGet args i) "0")) 0)

(schema Mix
  (:f i Int64)
  (:f r Float64)
  (:f b Bool)
  (:f s String))

fn mixed m: Mix k: Int64 -> String
  (str (+ m.i k) " " (* m.r 2.0) " " (if m.b "yes" "no") " " m.s " " m.i)

fn countUp i: Int64 n: Int64 acc: Int64 -> Int64
  (if (= i n) acc (countUp (+ i 1) n (+ acc 1)))

fn scaled i: Int64 n: Int64 acc: Int64 -> Int64
  (if (= i n) acc (scaled (+ i 1) n (mod (+ (* acc 31) i) 1000000007)))

fn ! main args: (List String) -> (Result Unit String)
  (let [(which (optionOr (listHead args) ""))
        (a (arg args 1))
        (b (arg args 2))]
    (do
      (cond
        ((= which "add") (println (stringFromInt64 (+ a b))))
        ((= which "sub") (println (stringFromInt64 (- a b))))
        ((= which "mul") (println (stringFromInt64 (* a b))))
        ((= which "div") (println (stringFromInt64 (/ a b))))
        ((= which "mod") (println (stringFromInt64 (mod a b))))
        ((= which "modConst") (println (stringFromInt64 (mod a 7))))
        ((= which "divConst") (println (stringFromInt64 (/ a -1))))
        ((= which "neg") (println (stringFromInt64 (- 0 a))))
        ((= which "countUp") (println (stringFromInt64 (countUp a b 0))))
        ((= which "scaled") (println (stringFromInt64 (scaled a b 0))))
        ((= which "modMul") (println (stringFromInt64 (* (mod a b) (arg args 3)))))
        ((= which "modConstMul") (println (stringFromInt64 (* (mod a 3037000501) b))))
        ((= which "fields") (println (mixed (Mix :i a :r (int64ToFloat64 b) :b (> a b) :s which) b)))
        ((= which "mapOrder") (println (str (map (fn [(x Int64)] -> Int64 (do (print (str x ",")) (* x b))) (range 0 a)))))
        ((= which "filterOrder") (println (str (filter (fn [(x Int64)] -> Bool (do (print (str x ",")) (= (mod x b) 0))) (range 0 a)))))
        ((= which "mapTrap") (println (str (map (fn [(x Int64)] -> Int64 (+ x b)) (list 1 a 3)))))
        ((= which "filterNonBool") (println (str (filter (fn [x] (+ x b)) (list a 2)))))
        ((= which "index") (println (stringFromInt64 (i64ArrayGet (i64ArrayGenerate a (fn [(i Int64)] -> Int64 (* i 2))) b))))
        ((= which "listOps") (let [(xs (range 0 a))] (println (str (listHead xs) " " (listTail xs) " " (listEmpty? xs)))))
        ((= which "listOpsVal") (println (str ((fn [xs] (listHead xs)) a))))
        ((= which "bytesGet") (println (stringFromInt64 (bytesGet (bytesAlloc a) b))))
        ((= which "bytesLength") (println (stringFromInt64 (bytesLength (bytesAlloc a)))))
        ((= which "stringLength") (println (stringFromInt64 (stringLength (str which a)))))
        ((= which "stringLengthVal") (println (str ((fn [s] (stringLength s)) a))))
        (else (println (str "unknown case " which))))
      (ok ())))
