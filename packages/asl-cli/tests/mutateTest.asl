(module asl-cli/tests/mutateTest
  :x [runTests suiteWallS]
  :i [(asl-tools/fleet/run :a fr) (asl-cli/mutate :a mu)])

; (:m :ref TEST-MUTATE :do "asl mutate FILE --symbol S --test T against a fixture package written under .asl/tmp (never indexed, removed at the end): the site engine yields single-site mutants in source then operator order and never touches the header; a strong test kills every mutant of pick, a weak one leaves the comparison flip at 6:8 alive and the run exits 1 with its source line; a doubled 1.0e308 is unbuildable; an if forced true in spin is a timeout; a red baseline, an unknown fn, a fn with no site and a FILE outside the test's closure are refused with exit 2; FILE keeps its bytes through every run, no hidden copy is left, and a plain asl test afterwards builds from the original and passes. Each child is one bin/asl run through fleet/run with a timeout and a descendant limit")
fn suiteWallS -> Int64
  1800

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! stamp! -> String
  (stringFromInt64 (monotonicNs))

fn calcSource -> String
  (str "(module mutfx/calc\n  :x [pick spin huge plain]\n  :i [])\n\n"
       "fn pick a: Int64 b: Int64 -> Int64\n  (if (< a b) 1 2)\n\n"
       "fn spin n: Int64 -> Int64\n  (if (> n 0) (spin (- n 1)) n)\n\n"
       "fn huge -> Float64\n  1.0e308\n\n"
       "fn plain x: Int64 -> Int64\n  x\n")

fn suiteSource name: String body: String -> String
  (str "(module mutfx/" name "\n  :x [runTests]\n  :i [(mutfx/calc :a c)])\n\nfn runTests -> Bool\n  (do " body "\n      true)\n")

fn fixtureFiles dir: String -> (List (Pair String String))
  (list
    (pair (str dir "/manifest.asn") "(:package mutfx\n :version \"0.1.0\"\n :entry \"src/calc.asl\"\n :dependencies [])\n")
    (pair (str dir "/src/calc.asl") (calcSource))
    (pair (str dir "/tests/strongTest.asl") (suiteSource "strongTest" "(assert (= (c/pick 1 2) 1) \"below\")\n      (assert (= (c/pick 2 2) 2) \"equal\")\n      (assert (= (c/pick 3 2) 2) \"above\")"))
    (pair (str dir "/tests/weakTest.asl") (suiteSource "weakTest" "(assert (= (c/pick 1 2) 1) \"below only\")"))
    (pair (str dir "/tests/redTest.asl") (suiteSource "redTest" "(assert (= (c/pick 1 2) 2) \"red on the original on purpose\")"))
    (pair (str dir "/tests/spinTest.asl") (suiteSource "spinTest" "(assert (= (c/spin 3) 0) \"spin counts down to 0\")"))
    (pair (str dir "/tests/hugeTest.asl") (suiteSource "hugeTest" "(assert (> (c/huge) 1.0e307) \"huge is huge\")"))
    (pair (str dir "/tests/otherTest.asl") "(module mutfx/otherTest\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do (assert (= (+ 1 1) 2) \"needs nothing of calc\")\n      true)\n"))

fn parentOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! writeAll! files: (List (Pair String String)) -> (Result Unit String)
  (match (listHead files)
    ((none) (ok ()))
    ((some f) (match (dirCreate (parentOf (pairFirst f)))
                ((err e) (err (str "cannot create " (parentOf (pairFirst f)) ": " e)))
                ((ok _) (match (fileWrite (pairFirst f) (pairSecond f))
                          ((err e) (err (str "cannot write " (pairFirst f) ": " e)))
                          ((ok _) (writeAll! (optionOr (listTail files) (list)))))))))

fn ! asl! args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons (str (repoRoot!) "/bin/asl") args) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! mutate! rel: String symbol: String test: String more: (List String) -> fr/Done
  (asl! (listAppend (list "mutate" (str rel "/src/calc.asl") "--symbol" symbol "--test" (str rel "/tests/" test ".asl")) more))

fn ! digestOf path: String -> String
  (match (fileReadBytes path) ((ok b) (bytesSha256 b)) ((err e) (str "unreadable " e)))

fn ! hiddenIn dir: String -> (List String)
  (filter (fn [(n String)] -> Bool (stringStartsWith? n ".")) (resultOr (dirList dir) (list)))

fn ! testSiteEngine -> Bool
  (let [(src "fn pick a: Int64 b: Int64 -> Int64\n  (if (< a b) 1 2)\n")
        (ms (resultOr (mu/mutantsOf src "pick" (list)) (list)))
        (logic "fn f xs: (List Int64) x: Bool -> Bool\n  (and (not x) (or (listEmpty? xs) true))\n")
        (ls (resultOr (mu/mutantsOf logic "f" (list)) (list)))
        (cmp (listGet ms 2))]
    (do (assert (= (map (fn [(m mu/Mutant)] -> String m.op) ms) (list "ifConst" "ifConst" "cmpFlip" "argSwap" "intShift" "intShift" "intShift" "intShift")) "pick yields its mutants in source order, then operator order")
        (assert (= (map (fn [(m mu/Mutant)] -> String (mu/siteOf src m.start)) ms) (list "2:7" "2:7" "2:8" "2:10" "2:15" "2:15" "2:17" "2:17")) "each mutant names its site as line:column")
        (assert (= (match cmp ((some m) (mu/applyMutant src m)) ((none) "")) "fn pick a: Int64 b: Int64 -> Int64\n  (if (<= a b) 1 2)\n") "a mutant changes one site and keeps every other byte")
        (assert (= (map (fn [(m mu/Mutant)] -> String (str m.op " " m.from " " m.to)) ls) (list "logicFlip and or" "notDrop (not x) x" "logicFlip or and" "boolFlip true false")) "and/or flips, a dropped not and a boolean flip; the (List Int64) of the header is no site")
        (assert (= (map (fn [(m mu/Mutant)] -> String m.op) (resultOr (mu/mutantsOf src "pick" (list "intShift")) (list))) (list "intShift" "intShift" "intShift" "intShift")) "--ops keeps the named operators only")
        (assert (= (match (mu/mutantsOf src "nope" (list)) ((ok _) "") ((err e) e)) "no top-level fn nope") "an unknown fn is an error")
        (assert (= (mu/mutantCopyName "calc.asl" 42 3) ".calc.mut.42.3.asl") "a mutant copy is a dot file beside its file, named by pid and number")
        (assert (= (mu/mutantCopyPid ".calc.mut.42.3.asl") (some 42)) "the stale-copy sweep reads the pid back")
        (assert (= (mu/mutantCopyPid ".calc.only.42.asl") (none)) "a selection copy is no mutant copy")
        true))

fn ! strongAndWeak! dir: String rel: String -> Bool
  (let [(calc (str dir "/src/calc.asl"))
        (before (digestOf calc))
        (strong (mutate! rel "pick" "strongTest" (list)))
        (afterStrong (digestOf calc))
        (weak (mutate! rel "pick" "weakTest" (list "--ops" "cmpFlip,argSwap" "--jobs" "2")))
        (afterWeak (digestOf calc))
        (plain (asl! (list "test" (str rel "/tests/strongTest.asl"))))]
    (do (assert (= strong.exit 0) (str "a strong test kills every mutant, exit 0: " strong.out))
        (assert (stringContains? strong.out ":total 8 :killed 8 :survived 0 :timeout 0 :unbuildable 0 :baselineMs ") (str "all 8 mutants of pick are killed: " strong.out))
        (assert (stringContains? strong.out "(:mutant :n 3 :site \"6:8\" :op cmpFlip :from \"<\" :to \"<=\" :status killed :ms ") (str "the comparison flip is killed by the equal case: " strong.out))
        (refute (stringContains? strong.out "(:survived ") (str "no survivor line: " strong.out))
        (assert (= afterStrong before) "calc.asl keeps its bytes through the strong run")
        (assert (= weak.exit 1) (str "a weak test leaves a survivor, exit 1: " weak.out))
        (assert (stringContains? weak.out "(:mutant :n 1 :site \"6:8\" :op cmpFlip :from \"<\" :to \"<=\" :status survived :ms ") (str "the comparison flip at 6:8 survives the weak test: " weak.out))
        (assert (stringContains? weak.out "(:mutant :n 2 :site \"6:10\" :op argSwap :from \"(< a b)\" :to \"(< b a)\" :status killed :ms ") (str "the operand swap is killed even by the weak test: " weak.out))
        (assert (stringContains? weak.out "(:survived :n 1 :site \"6:8\" :line \"(if (< a b) 1 2)\")") (str "the survivor is shown with its source line: " weak.out))
        (assert (stringContains? weak.out ":total 2 :killed 1 :survived 1 :timeout 0 :unbuildable 0 ") (str "the summary counts the survivor apart from the kill: " weak.out))
        (assert (= afterWeak before) "calc.asl keeps its bytes through the weak run")
        (assert (and (= plain.exit 0) (stringContains? plain.out "strongTest.asl: 3 assertion(s) executed (3 passed)")) (str "after mutate, a plain asl test builds from the original and passes: " plain.out))
        (assert (listEmpty? (hiddenIn (str dir "/src"))) (str "no hidden copy is left beside calc.asl: " (stringJoin (hiddenIn (str dir "/src")) " ")))
        true))

fn ! unbuildableAndTimeout! dir: String rel: String -> Bool
  (let [(calc (str dir "/src/calc.asl"))
        (before (digestOf calc))
        (huge (mutate! rel "huge" "hugeTest" (list)))
        (plainHuge (asl! (list "test" (str rel "/tests/hugeTest.asl"))))
        (spin (mutate! rel "spin" "spinTest" (list "--ops" "ifConst" "--max" "1" "--wall" "5")))]
    (do (assert (= huge.exit 0) (str "no mutant of huge survives: " huge.out))
        (assert (stringContains? huge.out "(:mutant :n 1 :site \"12:3\" :op floatPerturb :from \"1.0e308\" :to ") (str "the doubled literal is mutant 1: " huge.out))
        (assert (stringContains? huge.out ":status unbuildable") (str "1.0e308 doubled is no literal, so that mutant is unbuildable: " huge.out))
        (assert (stringContains? huge.out "(:mutant :n 2 :site \"12:3\" :op floatPerturb :from \"1.0e308\" :to \"0.0\" :status killed :ms ") (str "the zeroed literal builds and is killed: " huge.out))
        (assert (stringContains? huge.out ":total 2 :killed 1 :survived 0 :timeout 0 :unbuildable 1 ") (str "unbuildable is counted apart from killed and survived: " huge.out))
        (assert (and (= plainHuge.exit 0) (stringContains? plainHuge.out "hugeTest.asl: 1 assertion(s) executed (1 passed)")) (str "the unbuildable mutant left no checker verdict behind: a plain asl test of hugeTest passes: " plainHuge.out))
        (assert (= spin.exit 0) (str "a timeout counts as killed: " spin.out))
        (assert (stringContains? spin.out "(:mutant :n 1 :site \"9:7\" :op ifConst :from \"(> n 0)\" :to \"true\" :status timeout :ms ") (str "an if forced true never ends and is a timeout: " spin.out))
        (assert (stringContains? spin.out ":total 1 :killed 0 :survived 0 :timeout 1 :unbuildable 0 ") (str "the timeout is reported apart: " spin.out))
        (assert (stringContains? spin.out ":wallS 5)") (str "--wall sets the mutant limit: " spin.out))
        (assert (= (digestOf calc) before) "calc.asl keeps its bytes through the unbuildable and timeout runs")
        (assert (listEmpty? (hiddenIn (str dir "/src"))) "no hidden copy is left after them")
        true))

fn ! refusals! dir: String rel: String -> Bool
  (let [(red (mutate! rel "pick" "redTest" (list)))
        (unknown (mutate! rel "nope" "strongTest" (list)))
        (noSite (mutate! rel "plain" "strongTest" (list)))
        (outside (mutate! rel "pick" "otherTest" (list)))
        (usage (asl! (list "mutate" (str rel "/src/calc.asl") "--symbol" "pick")))
        (badOp (mutate! rel "pick" "strongTest" (list "--ops" "flipAll")))]
    (do (assert (and (= red.exit 2) (stringContains? red.out "ERR_BASELINE_RED")) (str "a test red on the original stops the run, exit 2: " red.out))
        (refute (stringContains? red.out "(:mutant ") (str "no mutant runs on a red baseline: " red.out))
        (assert (and (= unknown.exit 2) (and (stringContains? unknown.out "ERR_UNKNOWN_SYMBOL") (stringContains? unknown.out "no top-level fn nope"))) (str "an unknown fn is refused: " unknown.out))
        (assert (and (= noSite.exit 2) (stringContains? noSite.out "ERR_NO_SITE")) (str "a fn with no mutable site is refused: " noSite.out))
        (assert (and (= outside.exit 2) (stringContains? outside.out "ERR_NOT_IN_CLOSURE")) (str "a FILE outside the test's closure is refused, every mutant would survive: " outside.out))
        (assert (and (= usage.exit 2) (stringContains? usage.out "ERR_USAGE")) (str "a missing --test is a usage error: " usage.out))
        (assert (and (= badOp.exit 2) (stringContains? badOp.out "unknown operators flipAll")) (str "an unknown operator is a usage error: " badOp.out))
        true))

; (:m :ref TEST-MUTATE :do "each test writes its own fixture package .asl/tmp/mutateFx_PID_STAMP and removes it, so asl test --only runs one of them alone; a failed assertion ends the run before that removal, so each test first removes the fixtures of a dead pid")
fn ! dropDeadFixtures! -> Int64
  (let [(tmp (str (repoRoot!) "/.asl/tmp"))]
    (fold (fn [(n Int64) (name String)] -> Int64
            (match (stringToInt64 (optionOr (listGet (stringSplit name "_") 1) ""))
              ((some pid) (if (and (stringStartsWith? name "mutateFx_") (and (!= pid (procSelf)) (not (resultOr (procAlive? pid) true)))) (do (pathRemove (str tmp "/" name)) (+ n 1)) n))
              ((none) n)))
          0 (resultOr (dirList tmp) (list))))

fn ! inFixture! check: (fn [String String] -> Bool) -> Bool
  (let [(_ (dropDeadFixtures!))
        (rel (str ".asl/tmp/mutateFx_" (stringFromInt64 (procSelf)) "_" (stamp!)))
        (dir (str (repoRoot!) "/" rel))]
    (match (writeAll! (fixtureFiles dir))
      ((err e) (let [(_ (pathRemove dir))] (assert false (str "fixture setup failed: " e))))
      ((ok _) (let [(r (check dir rel)) (_ (pathRemove dir))] r))))

fn ! testStrongAndWeak -> Bool
  (inFixture! strongAndWeak!)

fn ! testUnbuildableAndTimeout -> Bool
  (inFixture! unbuildableAndTimeout!)

fn ! testRefusals -> Bool
  (inFixture! refusals!)

fn ! runTests -> Bool
  (let [(engine (testSiteEngine)) (sw (testStrongAndWeak)) (ut (testUnbuildableAndTimeout)) (rf (testRefusals))]
    (and engine (and sw (and ut rf))))
