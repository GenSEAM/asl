(module asl-tools/fleet/tests/briefTest
  :x [runTests]
  :i [(asl-tools/fleet/brief :a br)])

; (:m :ref DS-ASSIST-ROLES :do "the BRIEFER validator offline: a brief naming real files, a real file#symbol, an owned new test and ./bin/asl test gates passes; a missing file, an unresolvable symbol, a missing or empty :owns, a gate that is not a test command, a gate on a missing test and an unbalanced form each fail with that item listed; the built (:agent) form parses and carries the root, model and unit")

fn good -> String
  "(:brief :task \"Unit X. Change: asl/tools/fleet/bounded.asl#parseArgs rejects zero. New test asl/tools/fleet/tests/xNewTest.asl in a temp dir.\" :owns (\"asl/tools/fleet/bounded.asl\" \"asl/tools/fleet/tests/xNewTest.asl\") :gates (\"env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl test asl/tools/fleet/tests/xNewTest.asl\" \"./bin/asl test asl/tools/fleet/tests/boundedTest.asl\"))"

fn ! errsOf! text: String -> String
  (stringJoin (br/validate! (resultOr (realPath ".") ".") text) " | ")

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (ok0 (br/validate! root (good)))
        (missingFile (errsOf! (stringReplace (good) "bounded.asl#parseArgs" "nofile.asl#parseArgs")))
        (badSym (errsOf! (stringReplace (good) "#parseArgs" "#noSuchFn")))
        (noOwns (errsOf! "(:brief :task \"Unit X. Change: asl/tools/fleet/bounded.asl#parseArgs.\" :gates (\"./bin/asl test asl/tools/fleet/tests/boundedTest.asl\"))"))
        (emptyOwns (errsOf! (stringReplace (good) "(\"asl/tools/fleet/bounded.asl\" \"asl/tools/fleet/tests/xNewTest.asl\")" "()")))
        (badGate (errsOf! (stringReplace (good) "./bin/asl test asl/tools/fleet/tests/boundedTest.asl" "rm -rf x")))
        (missGate (errsOf! (stringReplace (good) "tests/boundedTest.asl" "boundedMissingTest.asl")))
        (unbal (errsOf! (stringReplace (good) "))" ")")))
        (b (br/parseBrief (good)))
        (form (br/buildForm root "X" b "synDs41FlashT1H" 24 900 "X"))
        (parsed (br/parseBrief (stringReplace form "(:agent" "(:brief")))]
    (do (assert (listEmpty? ok0) (str "a good brief passes: " (stringJoin ok0 " | ")))
        (assert (stringContains? missingFile "path not found: asl/tools/fleet/nofile.asl") missingFile)
        (assert (stringContains? badSym "symbol not found: asl/tools/fleet/bounded.asl#noSuchFn") badSym)
        (assert (stringContains? noOwns "missing :owns") noOwns)
        (assert (stringContains? emptyOwns "empty :owns") emptyOwns)
        (assert (stringContains? badGate "gate is not ./bin/asl test PATH: rm -rf x") badGate)
        (assert (stringContains? missGate "gate test path not found") missGate)
        (assert (stringContains? unbal "form does not parse") unbal)
        (assert (and (= (listLength b.owns) 2) (= (listLength b.gates) 2)) "owns and gates are read")
        (assert (and (stringContains? form ":model synDs41FlashT1H") (stringContains? form ":unit \"X\"") (stringContains? form ":intent any")) form)
        (assert (and (listEmpty? parsed.errors) (= parsed.task b.task) (= (listLength parsed.owns) 2)) (str "the built form reads back: " (stringJoin parsed.errors " | ")))
        true))
