(module asl-target-llvm/tests/fixtures/recordScalar/loops
  :x [main step grow hold keep capture pass same rebuilt]
  :i [])

schema Body
  pos: Int64
  vel: Int64

schema Named
  name: String
  count: Int64
  ratio: Float64

fn step i: Int64 n: Int64 b: Body -> Body
  (if (= i n) b
    (let [(p (+ b.pos b.vel))
          (v (if (> p 1000) (- b.vel 3) (+ b.vel 1)))]
      (step (+ i 1) n (Body :pos (mod p 100003) :vel v))))

fn grow i: Int64 n: Int64 acc: Named -> Named
  (if (= i n) acc
    (grow (+ i 1) n (Named :name (if (= (mod i 2) 0) "even" "odd") :count (+ acc.count i) :ratio (* acc.ratio 0.5))))

fn hold i: Int64 n: Int64 b: Body -> Int64
  (if (= i n) (+ (* b.pos 1000) b.vel)
    (if (= (mod i 3) 0)
      (hold (+ i 1) n b)
      (hold (+ i 1) n (Body :pos (+ b.pos 1) :vel b.vel))))

fn keep i: Int64 n: Int64 b: Body acc: (List Body) -> (List Body)
  (if (= i n) acc (keep (+ i 1) n (Body :pos (+ b.pos 1) :vel b.vel) (cons b acc)))

fn capture i: Int64 n: Int64 b: Body f: (fn [Int64] -> Int64) -> Int64
  (if (= i n) (f 0) (capture (+ i 1) n (Body :pos (+ b.pos i) :vel b.vel) (fn [(x Int64)] -> Int64 (+ x b.pos))))

fn total b: Body -> Int64
  (+ b.pos b.vel)

fn pass i: Int64 n: Int64 b: Body s: Int64 -> Int64
  (if (= i n) s (pass (+ i 1) n (Body :pos (+ b.pos 1) :vel (+ b.vel 2)) (+ s (total b))))

fn same i: Int64 n: Int64 b: Body c: Int64 -> Int64
  (if (= i n) c (same (+ i 1) n (Body :pos (mod i 3) :vel 0) (if (= b (Body :pos 1 :vel 0)) (+ c 1) c)))

fn rebuilt i: Int64 n: Int64 b: Body -> (List Body)
  (if (= i n) (list b b) (rebuilt (+ i 1) n (Body :pos (+ b.pos b.vel) :vel (- b.vel 1))))

fn bodyText b: Body -> String
  (str b.pos "/" b.vel)

fn ! main -> (Result Int64 String)
  (let [(s (step 0 5000 (Body :pos 0 :vel 1)))
        (g (grow 0 7 (Named :name "start" :count 0 :ratio 64.0)))
        (k (keep 0 4 (Body :pos 10 :vel 2) (list)))
        (r (rebuilt 0 3 (Body :pos 1 :vel 5)))]
    (do (println (str "step " (bodyText s)))
        (println (str "grow " g.name " " g.count " " g.ratio))
        (println (str "hold " (hold 0 10 (Body :pos 5 :vel 7))))
        (println (str "keep " (stringJoin (map bodyText k) ",")))
        (println (str "capture " (capture 0 5 (Body :pos 1 :vel 0) (fn [(x Int64)] -> Int64 (- x 1)))))
        (println (str "pass " (pass 0 6 (Body :pos 1 :vel 1) 0)))
        (println (str "same " (same 0 9 (Body :pos 0 :vel 0) 0)))
        (println (str "rebuilt " (stringJoin (map bodyText r) ",")))
        (ok 0)))
