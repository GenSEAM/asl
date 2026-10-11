(module asl-ir/tests/declPositionsAllocTest
  :x [runTests]
  :i [(asl-ir/lower :a low)])

fn repeatOnto n: Int64 unit: String acc: String -> String
  (if (<= n 0) acc (repeatOnto (- n 1) unit (str acc unit)))

fn ! cpuMicros -> Int64
  (let [(usageResult (procRusage))]
    (mt usageResult
      ((err e) (do (assert (ok? usageResult) (str "procRusage failed: " e)) 0))
      ((ok usage) (+ usage.selfUserUs usage.selfSysUs))))

fn ! lowerSrc -> String
  (optionOr (resultToOption (fileRead "asl/packages/asl-ir/src/lower.asl")) "")

fn ! largeFixture -> String
  (repeatOnto 10 (lowerSrc) "")

fn lineOfLineStart text: String needle: String -> Int64
  (mt (stringIndexOf text needle)
    ((none) -1)
    ((some idx) (+ 2 (stringCountChar (optionOr (stringSlice text 0 idx) "") "\n"))))

fn ! assertExactPosition m: (Map String String) orig: String name: String -> Bool
  (let [(expectedLine (lineOfLineStart orig (str "\nfn " name " ")))
        (expected (str (stringFromInt64 expectedLine) ":1"))
        (got (optionOr (mapGet m name) "<missing>"))]
    (assert (= got expected) (str "declPositions places " name " at " expected " (derived from lower.asl's own content), got " got))
    true)

fn ! runTests -> Bool
  (let [(src (largeFixture))
        (orig (lowerSrc))]
    (do
      (assert (not (stringEmpty? src)) "lower.asl itself reads as the fixture source")
      (let [(startUs (cpuMicros))
            (m (low/declPositions src))
            (endUs (cpuMicros))
            (cpuUs (- endUs startUs))
            (lineCount (listLength (stringSplit src "\n")))]
        (do
          (println (str "declPositionsAlloc lines " lineCount " names " (listLength (mapKeys m)) " cpuUs " cpuUs))
          (assert (> (listLength (mapKeys m)) 0) "declPositions finds at least one declared name in the fixture")
          (assertExactPosition m orig "builtinArity")
          (assertExactPosition m orig "floatText?")
          (assertExactPosition m orig "declName")
          (assert (< cpuUs 2200000)
                  (str "declPositions on a " lineCount "-line source (lower.asl repeated 10x) stays under 2.2s CPU (~3x the ~0.7s measured for the linear fold; the quadratic listGet-per-line version measured ~7.5s here); got " cpuUs " us"))
          true))))
