(module asl-ir/tests/arityAllocTest
  :x [runTests main]
  :i [(asl-ir/lower :a lw)])

fn ! loopArity i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc
    (loopArity (+ i 1) n (+ acc (optionOr (lw/builtinArity "parquetKvMetadata") 0))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str "result " (loopArity 0 20000 0))) (ok 0))

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn statsLine text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringLines text))) "")

fn tokenAfter tokens: (List String) key: String -> (Option String)
  (mt (listIndexOf tokens key)
    ((some i) (listGet tokens (+ i 1)))
    (none none))

fn objectsAllocated line: String -> Int64
  (optionOr (mt (tokenAfter (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")) ":objectsAllocated")
              ((some v) (stringToInt64 (stringReplace v ")" "")))
              (none none))
            -1)

fn ! testArityCorrectness -> Bool
  (do
    (assert (= (lw/builtinArity "+") (some 2)) "first table entry still resolves")
    (assert (= (lw/builtinArity "parquetKvMetadata") (some 2)) "last table entry still resolves")
    (assert (= (lw/builtinArity "notARealBuiltinName") (none)) "an unknown name is none, not a trap")
    (assert (= (lw/builtinArity "parMap") (some 3)) "parMap's primary arity is its full slot count")
    (assert (= (lw/builtinArityFor "parMap" 2) (some 2)) "parMap/2 matches the alt arity (the CPU-count default omitted)")
    (assert (= (lw/builtinArityFor "parMap" 3) (some 3)) "parMap/3 matches the primary arity")
    (assert (= (lw/builtinArityFor "parMap" 4) (none)) "parMap/4 matches neither arity")
    (assert (= (lw/builtinArityFor "parFold" 4) (some 4)) "parFold's alt arity")
    (assert (= (lw/builtinArityFor "notARealBuiltinName" 1) (none)) "an unknown name has no arity to match against")
    true)

fn ! testArityAllocation -> Bool
  (let [(out (sh "ASL_GC_STATS=1 asl/host/out/asl-host run asl/packages/asl-ir/tests/arityAllocTest.asl arity 2>&1 1>/dev/null"))
        (line (statsLine out.stdout))
        (allocated (objectsAllocated line))]
    (do
      (assert (= out.exitCode 0) (str "the arity subprocess exits 0: " out.stdout))
      (assert (> allocated 0) (str "a (:gcStats ...) line with objectsAllocated was captured: " out.stdout))
      (assert (< allocated 5000000) (str "20000 builtinArity lookups allocate under 5M objects (cond dispatch measures ~23K; the old per-call mapFromPairs rebuild measured ~317.68M): " line))
      true))

fn ! runTests -> Bool
  (do
    (assert (testArityCorrectness) "builtinArity/builtinArityFor dispatch agrees with the table at its edges")
    (assert (testArityAllocation) "builtinArity's per-call allocation stays near the cond-dispatch floor, not the old table-rebuild cost")
    true)
