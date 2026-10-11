(module asl-target-llvm/tests/fixtures/tailCall/tailProbe
  :x [main count even? odd? viaCond viaMt viaLet viaDo viaIf viaClosure viaValue badArity spin]
  :i [(asl-target-llvm/tests/fixtures/tailCall/tailHop :a th)])

fn count n: Int64 acc: Int64 -> Int64
  (if (= n 0) acc (count (- n 1) (+ acc 1)))

fn even? n: Int64 -> Bool
  (if (= n 0) true (odd? (- n 1)))

fn odd? n: Int64 -> Bool
  (if (= n 0) false (even? (- n 1)))

fn viaCond n: Int64 acc: Int64 -> Int64
  (cond ((= n 0) acc) ((= (mod n 2) 0) (viaCond (- n 1) (+ acc 1))) (else (viaCond (- n 1) (+ acc 1))))

fn viaMt n: Int64 acc: Int64 -> Int64
  (mt (if (= n 0) (none) (some (- n 1))) ((none) acc) ((some m) (viaMt m (+ acc 1))))

fn viaLet n: Int64 acc: Int64 -> Int64
  (if (= n 0) acc (let [(m (- n 1)) (next (+ acc 1))] (viaLet m next)))

fn viaDo n: Int64 acc: Int64 -> Int64
  (if (= n 0) acc (do (viaDo (- n 1) (+ acc 1))))

fn viaIf n: Int64 acc: Int64 -> Int64
  (if (> n 0) (viaIf (- n 1) (+ acc 1)) acc)

fn keep n: Int64 acc: (List Int64) -> (List Int64)
  (if (< n 3) (cons n acc) acc)

fn viaClosure n: Int64 acc: (List Int64) -> (List Int64)
  (if (= n 0) acc
    (let [(h (fn [(m Int64)] -> (List Int64) (viaClosure m (keep m acc))))]
      (h (- n 1))))

fn viaValue n: Int64 acc: (List Int64) -> (List Int64)
  (if (= n 0) acc
    (let [(g viaValue)] (g (- n 1) (keep (- n 1) acc))))

fn badArity n: Int64 -> (List Int64)
  (let [(g viaValue)] (g n))

fn spin n: Int64 acc: (List Int64) -> (List Int64)
  (if (= n 0) acc (th/hop (- n 1) (keep (- n 1) acc) spin))

fn run mode: String n: Int64 -> String
  (cond
    ((= mode "self") (stringFromInt64 (count n 0)))
    ((= mode "mutual") (if (even? n) "even" "odd"))
    ((= mode "arms") (stringFromInt64 (+ (viaCond n 0) (+ (viaMt n 0) (+ (viaLet n 0) (+ (viaDo n 0) (viaIf n 0)))))))
    ((= mode "closure") (stringFromInt64 (listLength (viaClosure n (list)))))
    ((= mode "value") (stringFromInt64 (listLength (viaValue n (list)))))
    ((= mode "arity") (stringFromInt64 (listLength (badArity n))))
    ((= mode "cross") (stringFromInt64 (listLength (spin n (list)))))
    (else (str "unknown mode " mode)))

fn ! main args: (List String) -> (Result Unit String)
  (let [(mode (optionOr (listHead args) "self"))
        (n (optionOr (stringToInt64 (optionOr (listGet args 1) "10")) 10))]
    (do (println (run mode n))
        (ok ())))
