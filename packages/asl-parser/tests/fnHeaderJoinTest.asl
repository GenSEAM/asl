(module asl-parser/tests/fnHeaderJoinTest
  :x [runTests]
  :i [(ast :a a)])

fn probeSource -> String
  (stringJoin (list "(module probe" "  :x [f]" "  :i [])" "fn f a: Int64" "     b: Int64" "     c: Int64 -> Int64" "  (+ a \"x\")" "") "\n")

fn declText -> String
  "fn f a: Int64\n     b: Int64\n     c: Int64 -> Int64\n  (+ a \"x\")\n"

fn testLineCount -> Bool
  (let [(joined (a/joinFnHeader (declText)))]
    (do (assert (= (listLength (stringSplit joined "\n")) (listLength (stringSplit (declText) "\n"))) (str "joined header keeps the line count: " joined))
        (assert (stringStartsWith? joined "fn f a: Int64 b: Int64 c: Int64 -> Int64\n") (str "the three header lines join onto the first: " joined))
        true))

fn ! testCheckerLine -> Bool
  (let [(made (processRun "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))
        (probe (str work "/probe.asl"))
        (written (fileWrite probe (probeSource)))
        (out (processRun (str "asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl check " probe)))]
    (do (assert (ok? written) "probe written")
        (assert (stringContains? out.stderr (str probe ":7:3: [type] argument to +: expected Int64, found String")) (str "native checker reports the body type error at line 7: " out.stderr))
        (assert (= (processRun (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))

fn ! runTests -> Bool
  (and (testLineCount) (testCheckerLine))
