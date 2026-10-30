(module asl-target-llvm/tests/emitScaleTest
  :x [runTests]
  :i [(asl-ir/lower :a low)
      (asl-parser/ast :a ast)
      (asl-target-llvm :a llvm)])

fn listSource n: Int64 -> String
  (let [(items (stringJoin (map (fn [(i Int64)] -> String "1") (range 0 n)) " "))]
    (str "(module scale :x [main])\n(fn main [] -> Int64 (do (list " items ") 0))"))

fn straightSource n: Int64 -> String
  (let [(items (stringJoin (map (fn [(i Int64)] -> String "1") (range 0 n)) " "))]
    (str "(module straight :x [main])\n(fn main [] -> Int64 (do " items "))"))

fn ! cpuMicros -> Int64
  (let [(usageResult (procRusage))]
    (match usageResult
      ((err e) (do (assert (ok? usageResult) (str "procRusage failed: " e)) 0))
      ((ok usage) (+ usage.selfUserUs usage.selfSysUs))))

fn ! emitCpu source: String -> Int64
  (match (low/lowerSource source)
    ((err ds) (do (println "emitScale lower diagnostic:" ds) -1))
    ((ok m) (let [(startEmit (cpuMicros))
                  (emitted (llvm/emitLlvmProgram m "main"))
                  (endEmit (cpuMicros))]
              (match emitted
                ((err ds) (do (println "emitScale emit diagnostic:" ds) -1))
                ((ok text) (- endEmit startEmit))))))

; (:m :ref FLAKES-EMITSCALE :do "a size is sampled five times and the minimum CPU time kept: load inflates single samples, never the least disturbed one, so the 2.6x bound on the ratio of minima still separates linear from quadratic emission (4x)")
fn ! emitMin source: String -> Int64
  (fold (fn [(best Int64) (i Int64)] -> Int64
          (let [(t (emitCpu source))]
            (if (<= t 0) best (if (or (< best 0) (< t best)) t best))))
        -1 (range 0 5))

fn ! testEmitScales -> Bool
  (let [(warm (emitCpu (listSource 1000)))
        (a (emitMin (listSource 4000)))
        (b (emitMin (listSource 8000)))
        (straightA (emitMin (straightSource 4000)))
        (straight (emitMin (straightSource 8000)))]
    (do
      (println "emitScale emission CPU us, list 1000/4000/8000:" warm a b "straight 4000/8000:" straightA straight)
      (assert (and (> a 0) (> b 0)) "literal emission measurements succeeded")
      (assert (and (> straightA 0) (> straight 0)) "straight-line emission measurements succeeded")
      (assert (<= (/ (* 1000 b) (max 1 a)) 2600) "emission 4000->8000 list literal is at most 2.6x")
      (assert (<= (/ (* 1000 straight) (max 1 straightA)) 2600) "emission 4000->8000 straight-line body is at most 2.6x")
      true))

fn ! runTests -> Bool
  (do
    (assert (testEmitScales) "list literal and straight-line emission scaling")
    true)
