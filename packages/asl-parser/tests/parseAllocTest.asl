(module asl-parser/tests/parseAllocTes
  :x [runTests main]
  :i [(asl-parser/ast :a ast)
      (tools/nativeTest :a nt)
      (tools/fleet/run :a fr)])

fn thisFile -> String
  "asl/packages/asl-parser/tests/parseAllocTest.asl"

fn workload -> (List String)
  (list "asl/prelude/prelude.asl" "asl/packages/asl-json/src/json.asl" "asl/packages/asl-json/tests/jsonTest.asl")

fn ! sources -> (List String)
  (map (fn [(p String)] -> String (mt (fileRead p) ((ok s) s) ((err _) ""))) (workload))

fn formCount src: String -> Int64
  (mt (ast/parse src) ((ok forms) (listLength forms)) ((err _) -1))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listGet args 0) "parse"))
        (srcs (sources))]
    (cond
      ((listAny? (fn [(s String)] -> Bool (stringEmpty? s)) srcs) (err "a workload file cannot be read"))
      ((= mode "read") (do (println (str "parseAlloc read files " (listLength srcs))) (ok 0)))
      ((= mode "parse") (do (println (str "parseAlloc parse forms " (stringJoin (map (fn [(s String)] -> String (stringFromInt64 (formCount s))) srcs) " "))) (ok 0)))
      (else (err (str "unknown mode " mode "; expected read or parse")))))

fn statsLine text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringSplit text "\n"))) "")

fn bytesAllocated line: String -> Int64
  (let [(tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens ":bytesAllocated")
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! runMode mode: String -> (Pair Int64 String)
  (let [(built (nt/prepareRun (thisFile) (nt/fingerprint)))]
    (mt built.binary
      ((none) (do (assert false (str "parseAllocTest builds natively: " built.reason)) (pair -1 "")))
      ((some bin)
       (let [(done (fr/runOneLimited (fr/job (list bin mode) "." (fr/childEnv (list "ASL_GC_STATS=1"))) (fr/limits 300 4)))]
         (do (assert (= done.exit 0) (str mode " run exits 0 (" done.verdict "): " done.out))
             (pair (bytesAllocated (statsLine done.out)) done.out))))))

fn ! runTests -> Bool
  (let [(readRun (runMode "read"))
        (parseRun (runMode "parse"))
        (parseBytes (- (pairFirst parseRun) (pairFirst readRun)))]
    (do
      (println (str "parseAlloc read " (pairFirst readRun) " parse " (pairFirst parseRun) " delta " parseBytes))
      (assert (stringContains? (pairSecond parseRun) "parseAlloc parse forms 252 28 12") (str "every workload module parses to its form count: " (pairSecond parseRun)))
      (assert (and (> (pairFirst readRun) 0) (> parseBytes 0)) "both runs report bytesAllocated and parsing allocates")
      (assert (< parseBytes 241000000) (str "parsing prelude and the jsonTest closure allocates < 241 MB (0.5x base 482 MB), got " parseBytes))
      true))
