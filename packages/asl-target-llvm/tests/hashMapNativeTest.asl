(module asl-target-llvm/tests/hashMapNativeTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/hashRt :a hashRt)
      (asl-target-llvm/tests/rcTest :a rct)])

; (:m :ref INTHASHMAP :do "the native HashMap wiring under untraced RC: the slot bodies are spliced (the in-place marker is in the IR), 50000 sets on a unique map allocate only the vectors growth needs instead of one copy per set, and sets, removes and inserts on aliases still leave the original as it was; the traced build runs the reference bodies and prints the same line")
fn want -> String
  "50000 1249975000 1 10 2 0 0 3 2 1 10 2 0 0 3 2\n"

fn ! build! libs: rct/Libs dir: String name: String mode: String -> (Result (Pair String rct/Captured) String)
  (match (lk/linkEntry! (str "asl/packages/asl-target-llvm/tests/fixtures/hashMap/" name ".asl"))
    ((err ds) (err (str name " links: " (rct/diagText ds))))
    ((ok m)
      (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
        ((err ds) (err (str name " emits in mode " mode ": " (rct/diagText ds))))
        ((ok code)
          (let [(ll (str dir "/" name "." mode ".ll"))
                (exe (str dir "/" name "." mode))]
            (match (fileWrite ll code)
              ((err e) (err (str "cannot write " ll ": " e)))
              ((ok _)
                (let [(linked (rct/sh (rct/linkCmd libs mode ll exe)))]
                  (if (!= linked.exitCode 0)
                    (err (str name " " mode " links: " linked.stderr))
                    (ok (pair code (rct/sh (rct/shellQuote exe)))))))))))))

fn ! runWith libs: rct/Libs -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/hashMapNativeTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do
      (assert (ok? made) "work directory created")
      (match (build! libs dir "hashInPlace" "notrace")
        ((err e) (assert false (str "untraced build: " e)))
        ((ok r)
          (let [(code (pairFirst r)) (run (pairSecond r)) (large (rct/statOf run.stderr "large"))]
            (do
              (assert (= run.exitCode 0) (str "untraced hashInPlace exits 0: " run.stderr))
              (assert (= run.stdout (want)) (str "untraced HashMap keeps every key and leaves aliases unchanged: " run.stdout))
              (assert (stringContains? code (hashRt/nativeMarker)) "the untraced build splices the native slot set (the in-place path exists)")
              (assert (and (>= large 0) (< large 400)) (str "50000 sets on a unique map write in place: large allocations " large " (one copy per set would be over 50000)"))))))
      (match (build! libs dir "hashInPlace" "0")
        ((err e) (assert false (str "traced build: " e)))
        ((ok r)
          (let [(code (pairFirst r)) (run (pairSecond r))]
            (do
              (assert (= run.stdout (want)) (str "the traced build runs the reference bodies and prints the same line: " run.stdout))
              (refute (stringContains? code (hashRt/nativeMarker)) "the traced build keeps the persistent reference set")))))
      (match (build! libs dir "hashPresized" "notrace")
        ((err e) (assert false (str "pre-sized build: " e)))
        ((ok r)
          (let [(run (pairSecond r)) (large (rct/statOf run.stderr "large"))]
            (do
              (assert (= run.stdout "50000 1\n") (str "the pre-sized map keeps every key: " run.stdout))
              (assert (and (>= large 1) (<= large 2)) (str "hashMapWithCapacity 50000 allocates its table once, no growth: large allocations " large))))))
      (match (build! libs dir "hashSemantics" "notrace")
        ((err e) (assert false (str "untraced semantics build: " e)))
        ((ok r)
          (let [(run (pairSecond r))]
            (do
              (assert (= run.exitCode 0) (str "the prelude HashMap suite passes on the native bodies: exit " run.exitCode " " run.stderr))
              (assert (= run.stdout "true\n") (str "the native suite returns true: " run.stdout))))))
      (assert (ok? (pathRemove (str dir "/hashInPlace.notrace"))) "untraced binary removed")
      true))

fn ! runTests -> Bool
  (match (rct/runtimes!)
    ((err e) (do (assert false (str "runtimes: " e)) false))
    ((ok libs) (runWith libs)))
