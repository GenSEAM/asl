(module asl-target-llvm/tests/fixtures/recordScalar/alloc/record
  :x [main step posOf Body]
  :i [])

; (:m :ref RECSROA :do "bench/native/record with the Body passed to posOf, so it escapes and recordScalar keeps one Body allocation per step: the allocation workload of the collector and RC suites")
(schema Body
  (:f pos Int64)
  (:f vel Int64))

fn posOf b: Body -> Int64
  b.pos

fn step i: Int64 n: Int64 b: Body -> Body
  (if (= i n) b
    (let [(p (+ (posOf b) b.vel))
          (v (if (> p 1000) (- b.vel 3) (+ b.vel 1)))]
      (step (+ i 1) n (Body :pos (mod p 100003) :vel v))))

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "1000")) 1000))
        (b (step 0 n (Body :pos 0 :vel 1)))]
    (do (println (str b.pos " " b.vel))
        (ok ())))
