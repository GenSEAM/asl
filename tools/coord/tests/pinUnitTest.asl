(module asl-tools/coord/tests/pinUnitTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIN-UNIT-PROVEN :do "a pin unit (task says regression guard) green on base reaches review on test-only diffs with an added assert; a non-pin green on base and a pin that touches source both stay refused, with 0 model calls")
fn lane alias: String tier: String -> l/Lane
  (l/Lane :alias alias :tier tier :allowance 5 :quality 0)

fn unitOf task: String -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task task :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list))

fn ! runOnce counter: String u: l/ReviewUnit diff: String gates: String -> l/Ruling
  (match (l/review u diff gates (list (lane "orNemotronUltraFree" "free") (lane "ocLongcat" "free") (lane "ocDeepseekFlash" "paid") (lane "ccKimi31Pro" "strong"))
           (fn [(a String) (p String)] -> (Result String String) (do (fileAppend counter "x\n") (ok "(:verdict :pass :defects () :model m)"))))
    ((ok r) r)
    ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e)))

fn ! calls counter: String -> Int64
  (listLength (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringLines (resultOr (fileReadString counter) ""))))

fn testDiff -> String
  (str "diff --git a/asl/tools/tests/fooTest.asl b/asl/tools/tests/fooTest.asl\n--- a/asl/tools/tests/fooTest.asl\n+++ b/asl/tools/tests/fooTest.asl\n+    (do (assert (= 1 1) \"pins\")\n")

fn srcDiff -> String
  (str (testDiff) "diff --git a/asl/tools/foo.asl b/asl/tools/foo.asl\n--- a/asl/tools/foo.asl\n+++ b/asl/tools/foo.asl\n+fn x -> Int64 1\n")

fn noAssertDiff -> String
  "diff --git a/asl/tools/tests/fooTest.asl b/asl/tools/tests/fooTest.asl\n--- a/asl/tools/tests/fooTest.asl\n+++ b/asl/tools/tests/fooTest.asl\n+; note\n"

fn ! runTests -> Bool
  (let [(dir (pf/scratch "pinUnit" "p"))
        (_ (dirCreate dir))
        (green "(:receipt U1 :gates ((:gate g :exit 0 :executed 12)))")
        (pinTask "regression guard: this unit pins present behaviour")
        (a (runOnce (str dir "/a") (unitOf pinTask) (testDiff) green))
        (b (runOnce (str dir "/b") (unitOf "plain task") (testDiff) green))
        (c (runOnce (str dir "/c") (unitOf pinTask) (srcDiff) green))
        (d (runOnce (str dir "/d") (unitOf pinTask) (noAssertDiff) green))
        (na (calls (str dir "/a")))
        (nb (calls (str dir "/b")))
        (nc (calls (str dir "/c")))
        (nd (calls (str dir "/d")))
        (_ (pathRemove dir))]
    (do (assert (and (= a.action "merge") (> na 0)) (str "pin with tests only reaches review: " a.action " " (stringFromInt64 na)))
        (assert (and (= b.action "fix") (= nb 0)) (str "non-pin green on base blocks: " b.action " " (stringFromInt64 nb)))
        (assert (and (= c.action "fix") (= nc 0)) (str "pin touching src blocks: " c.action " " (stringFromInt64 nc)))
        (assert (and (= d.action "fix") (= nd 0)) (str "pin with no added assert blocks: " d.action " " (stringFromInt64 nd)))
        true))
