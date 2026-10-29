(module asl-tools/coord/tests/gateGuardTest
  :x [runTests]
  :i [(asl-tools/coord/gateGuard :a gg) (tools/fleet/freePool :a fp)])

; (:m :ref CONDHARDEN :do "pure coverage of the gate-stage guards: importer finder over given file texts, deletion-ratio refusal, and the Leon launch argv/cwd/env; each assert goes red when its check is removed or weakened")
fn files -> (List (Pair String String))
  (list (pair "a/vps.asl" "(module tools/remote/vps\n  :x [main]\n  :i [])")
        (pair "a/remoteOps.asl" "(module asl/agentLoop/remoteOps\n  :x [ops]\n  :i [(tools/remote/vps :a vps) (asl-x/y :a y)])")
        (pair "a/near.asl" "(module asl/near\n  :i [(tools/remote/vpsExtra :a v)])")
        (pair "a/bare.asl" "(module asl/bare\n  :i [tools/remote/vps])")
        (pair "a/none.asl" "(module asl/none\n  :i [(asl-x/y :a y)])"))

fn ! testImporters -> Bool
  (let [(got (gg/importers (files) (list "tools/remote/vps") (list "a/vps.asl")))]
    (do (assert (= (gg/moduleName "(module tools/remote/vps\n  :x [main])") "tools/remote/vps") "module name read from the header")
        (assert (= (gg/moduleName "no header") "") "no header, no name")
        (assert (listContains? got "a/remoteOps.asl") (str "an importer is found: " (stringJoin got ",")))
        (assert (listContains? got "a/bare.asl") "a bare name in :i counts")
        (assert (not (listContains? got "a/near.asl")) "a longer module name sharing the prefix is not an importer")
        (assert (not (listContains? got "a/none.asl")) "an unrelated file is not an importer")
        (assert (not (listContains? got "a/vps.asl")) "the owned file itself is left out")
        (assert (= (listLength got) 2) "exactly the two importers")
        (assert (not (gg/importsModule? "(module tools/remote/vps\n :i [])" "tools/remote/vps")) "a module header alone is not an import")
        (assert (<= (listLength (gg/importers (map (fn [(i Int64)] -> (Pair String String) (pair (str "f" (stringFromInt64 i)) "(module m :i [(tools/remote/vps :a v)])")) (range 0 100)) (list "tools/remote/vps") (list))) (gg/maxImporters)) "importer list is bounded")
        true))

fn ! testShrink -> Bool
  (do (assert (gg/shrunk? 1481 24) "1481 to 24 lines is a shrink")
      (assert (not (gg/shrunk? 100 50)) "exactly half kept is not more than half lost")
      (assert (gg/shrunk? 100 49) "one line past half is a shrink")
      (assert (not (gg/shrunk? 0 0)) "an owned file new on this branch has no base to lose")
      (assert (not (gg/shrunk? 100 300)) "growth is no shrink")
      (assert (stringContains? (gg/shrinkSig "tools/remote/vps.asl" 1481 24 "fix the relay") "lost 1457 of 1481") "refusal names the loss")
      (assert (stringEmpty? (gg/shrinkSig "tools/remote/vps.asl" 1481 24 "Rewrite the relay from scratch")) "the word rewrite lifts the refusal, any case")
      (assert (stringEmpty? (gg/shrinkSig "x.asl" 100 90 "edit")) "a small loss passes")
      true)

fn ! testLeonLaunch -> Bool
  (let [(j (fp/leonJob "/repo/main" "/wt/UNIT" "/home/h" "task text" (list "p/a.asl") (list "./bin/asl test t/xTest.asl") "/no-such-keys"))
        (form (optionOr (listGet j.argv 1) ""))]
    (do (assert (= (optionOr (listHead j.argv) "") "/repo/main/bin/asl") (str "Leon binary is the repo build: " (optionOr (listHead j.argv) "")))
        (assert (= j.cwd "/wt/UNIT") "the worktree is the working directory")
        (assert (listContains? j.env "ASL_ROOT=/wt/UNIT") "the worktree is the workspace root")
        (assert (not (listAny? (fn [(a String)] -> Bool (stringContains? a "/wt/UNIT/bin")) j.argv)) "no argv entry points into the worktree's bin")
        (assert (stringContains? form ":gates (\"./bin/asl test t/xTest.asl\")") (str "the unit gate rides in the Leon form: " form))
        (assert (not (stringContains? (fp/leonForm "t" (list)) ":gates")) "no gates, no :gates key")
        true))

fn ! runTests -> Bool
  (do (assert (testImporters) "importers")
      (assert (testShrink) "shrink")
      (assert (testLeonLaunch) "leon launch")
      true)
