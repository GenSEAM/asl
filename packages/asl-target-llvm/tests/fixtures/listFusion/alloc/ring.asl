(module asl-target-llvm/tests/fixtures/listFusion/alloc/ring
  :x [main]
  :i [])

; (:m :ref WAVE6 :do "bench/native/ring with the reversed batch also read by listLength: the second use is one listFusion guard rejects, so every round still builds and frees cap cells and the RC soak keeps a per-element allocation workload")

fn pushBatch i: Int64 cap: Int64 start: Int64 acc: (List Int64) -> (List Int64)
  (if (= i cap) acc
    (pushBatch (+ i 1) cap start (cons (+ start i) acc)))

fn drainSum items: (List Int64) acc: Int64 -> Int64
  (match (listHead items)
    ((none) acc)
    ((some v) (drainSum (optionOr (listTail items) (list)) (+ acc v))))

fn runRounds i: Int64 total: Int64 cap: Int64 produced: Int64 acc: Int64 -> Int64
  (if (= i total) acc
    (let [(batch (listReverse (pushBatch 0 cap produced (list))))
          (sum (+ (drainSum batch 0) (listLength batch)))]
      (runRounds (+ i 1) total cap (+ produced cap) (+ acc sum))))

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "1000")) 1000))
        (cap 1024)
        (rounds (/ n cap))
        (acc (runRounds 0 rounds cap 0 0))]
    (do (println (stringFromInt64 acc))
        (ok ())))
