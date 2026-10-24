(module asl-target-llvm/tests/fixtures/recordScalar/spin
  :x [main step]
  :i [])

schema Body
  pos: Int64
  vel: Int64

fn step i: Int64 n: Int64 b: Body -> Body
  (if (= i n) b
    (let [(p (+ b.pos b.vel))
          (v (if (> p 1000) (- b.vel 3) (+ b.vel 1)))]
      (step (+ i 1) n (Body :pos (mod p 100003) :vel v))))

fn ! main -> (Result Int64 String)
  (let [(b (step 0 1000000 (Body :pos 0 :vel 1)))]
    (do (println (str "spin " b.pos " " b.vel)) (ok 0)))
