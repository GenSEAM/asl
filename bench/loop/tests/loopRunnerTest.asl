(module aslBench/loop/tests/loopRunnerTest
  :x [runTests]
  :i [(aslBench/loop/core :a lc)
      (aslBench/gen/core :a gc)])

; (:m :ref LOOPBENCH :do "the loop runner end to end on the ASL arm with a canned model: a script that reads, fixes the seeded defect, tests and says done is solved; a script that edits the wrong constant and says done is not; the pure parts (task blocks, tag calls, item regions, whole-word rename, the solved rule) are pinned, so an inverted solved rule turns both halves red")

fn sampleTask -> String
  "#@ task demo bugfix\n#@ prompt\nFix it.\nSecond line.\n\n#@ seed src/a.asl\n(+ a 1)\n#@ with\n(+ a 2)\n#@ refAll src/a.asl\nold\n#@ with\nnew\n#@ accept tests/acceptTest.asl\n(module x)\n\nfn runTests -> Bool\n  true\n#@ absent\nsumKahan\n"

fn sampleSource -> String
  "(module demo/a\n  :x [mean total]\n  :i [])\n\n; (:m :ref X :do \"note\")\nfn mean xs: (List Float64) -> Float64\n  (/ (total xs) 2.0)\n\nfn ! total xs: (List Float64) -> Float64\n  (meanOf xs)\n\nschema Box\n  (:f v Int64)\n"

fn ! testPure -> Bool
  (let [(half (lc/halfOf (lc/blocksOf (sampleTask))))
        (seed (optionOr (listHead half.seeds) (lc/Edit :file "" :old "" :new "" :all false)))
        (ref (optionOr (listHead half.refs) (lc/Edit :file "" :old "" :new "" :all false)))
        (lines (stringLines (sampleSource)))
        (reply "I will fix it.\n<tool>edit</tool>\n<path>src/a.asl</path>\n<old>\n  (a\n   b)\n</old>\n<new>x</new>")
        (renamed (lc/renameWord "(mean xs) (meanOf xs) ds/mean mean" "mean" "avg"))]
    (assert (= half.prompt "Fix it.\nSecond line.") "the prompt block keeps its lines and drops trailing blank lines")
    (assert (and (= seed.file "src/a.asl") (= seed.old "(+ a 1)") (= seed.new "(+ a 2)") (not seed.all)) "a seed block pairs with its with block")
    (assert (and ref.all (= ref.new "new")) "refAll marks a replace-everywhere edit")
    (assert (= half.accepts (list (pair "tests/acceptTest.asl" "(module x)\n\nfn runTests -> Bool\n  true\n"))) "an accept block is a file with its text")
    (assert (= half.absent (list "sumKahan")) "an absent block is a text that must not remain")
    (assert (= (lc/tagOf reply "tool") (some "edit")) "the tool name is read from its tag")
    (assert (= (lc/tagOf reply "old") (some "  (a\n   b)")) "a multi-line argument keeps its inner indentation and loses the framing newlines")
    (assert (= (lc/tagOf reply "body") (none)) "an absent argument is none")
    (assert (= (lc/countOf "a-b-a-a" "a") 3) "occurrences are counted")
    (assert (and (lc/pathOk? "src/a.asl") (not (lc/pathOk? "../x")) (not (lc/pathOk? "/etc/passwd")) (not (lc/pathOk? ""))) "paths stay inside the package")
    (assert (= (lc/itemRegion lines "mean") (some (pair 5 7))) "a fn region runs from its header to the last line before the next item")
    (assert (= (lc/itemRegion lines "total") (some (pair 8 10))) "an effectful fn is found by its name after the ! mark")
    (assert (= (lc/itemRegion lines "Box") (some (pair 11 13))) "a schema is an item")
    (assert (= (lc/itemRegion lines "absent") (none)) "an unknown name has no region")
    (assert (= (lc/headerName "def trimmed_mean(xs: Sequence[float], frac: float) -> float:") "trimmed_mean") "a Python def header names its function")
    (assert (= renamed (pair "(avg xs) (meanOf xs) ds/avg avg" 3)) "rename replaces whole words only and counts them")
    (assert (stringContains? (lc/outlineOf (sampleSource)) "6: fn mean xs: (List Float64) -> Float64") "the outline lists item headers with line numbers")
    (assert (= (lc/loadOf "21:30  up 2 days, 10:13, 4 users, load averages: 45.52 39.59 36.48") 45) "the one-minute load is read from uptime on macOS")
    (assert (= (lc/loadOf " 21:30:01 up 2 days,  1 user,  load average: 3.10, 2.50, 2.00") 3) "and on Linux")
    (assert (= (lc/cleanOut (lc/Sandbox :lang "asl" :trial "/w/t-1" :pkg "/w/t-1/asl/packages/asl-stats" :pristine "")
                            "FAIL x: ERR_NATIVE_UNSUPPORTED: /home/u/.asl/cache/nativeTest/outsidePkg/abc/aslLoopBenchSandbox/src/interval.asl:60:3: ERR_ARITY\n/w/t-1/asl/packages/asl-stats/tests/a.asl:1:1: ERR_ASSERT")
               "FAIL x: ERR_NATIVE_UNSUPPORTED: src/interval.asl:60:3: ERR_ARITY\ntests/a.asl:1:1: ERR_ASSERT")
            "tool output names files relative to the package, without sandbox or cache prefixes")
    (assert (lc/solvedOf true true true) "solved needs the suite, the hidden tests and the absent check")
    (assert (not (lc/solvedOf false true true)) "a red suite is not solved")
    (assert (not (lc/solvedOf true false true)) "red hidden tests are not solved")
    (assert (not (lc/solvedOf true true false)) "a leftover old name is not solved")
    (assert (and (= (lc/armLang "pyB") "py") (= (lc/armLang "aslB") "asl") (lc/armRich? "aslB") (not (lc/armRich? "aslA"))) "arms map to a language and a tool set")
    true)

fn goodScript -> (List String)
  (list "<tool>grep</tool>\n<pattern>(int64ToFloat64 n)</pattern>"
        "The interpolation index uses n where it needs n - 1.\n<tool>read</tool>\n<path>src/describe.asl</path>\n<from>64</from>\n<to>78</to>"
        "<tool>edit</tool>\n<path>src/describe.asl</path>\n<old>(int64ToFloat64 n) p)</old>\n<new>(int64ToFloat64 (- n 1)) p)</new>"
        "<tool>test</tool>\n<path>tests/describeTest.asl</path>"
        "<tool>done</tool>")

fn badScript -> (List String)
  (list "<tool>read</tool>\n<path>src/interval.asl</path>\n<from>1</from>\n<to>30</to>"
        "<tool>edit</tool>\n<path>src/interval.asl</path>\n<old>(* 4.0 nf)</old>\n<new>(* 8.0 nf)</new>"
        "<tool>bogus</tool>"
        "<tool>done</tool>")

fn ! testLoop root: String -> Bool
  (let [(work (resultOr (realPath (let [(d (str (optionOr (envGet "TMPDIR") "/tmp") "/aslLoopBenchTest-" (stringFromInt64 (nowNs))))
                                        (made (dirCreate d))]
                                    d))
                        ""))
        (cfg (lc/Cfg :root root :aslBin (str root "/bin/asl") :work work :out (str work "/trials.asn") :maxTurns 8 :maxTokens 1000
                     :trialTokens 100000 :resultClip 6000 :priceIn 150000 :priceOut 600000 :capPico 1000000000000 :loadMax 1000 :loadWaitS 0))
        (tasks (resultOr (lc/loadTasks root) (list)))
        (taskOf (fn [(id String)] -> lc/LoopTask
                  (optionOr (listFind (fn [(t lc/LoopTask)] -> Bool (= t.id id)) tasks)
                            (lc/LoopTask :id "" :kind "" :asl (lc/halfOf (list)) :py (lc/halfOf (list))))))
        (caller (lc/scriptCaller (list (pair "aslA|bugPercentile" (goodScript)) (pair "aslA|bugWilson" (badScript)))))
        (good (pairSecond (lc/loopTrial! cfg (lc/Trial :arm "aslA" :task (taskOf "bugPercentile") :model "fake" :rep 1) caller 0 0)))
        (bad (pairSecond (lc/loopTrial! cfg (lc/Trial :arm "aslA" :task (taskOf "bugWilson") :model "fake" :rep 1) caller 0 0)))
        (row (lc/trialRow good good.acc.spent))
        (cleaned (lc/removeWork! work))]
    (assert (>= (listLength tasks) 8) "at least eight tasks load")
    (assert good.verdict.solved (str "the script that fixes the seeded defect is solved: " good.verdict.detail " " good.acc.error))
    (assert (and good.verdict.suiteOk good.verdict.acceptOk good.verdict.absentOk) "its suite, hidden tests and absent check are all green")
    (assert (and (= good.acc.stop "done") (= good.acc.turns 5)) "it stops on done after five replies")
    (assert (= good.acc.calls (list "grep" "read src/describe.asl" "edit src/describe.asl" "test tests/describeTest.asl" "done")) "every call is recorded in order")
    (assert (and (= good.acc.files (list "src/describe.asl")) (> good.acc.bytesRead 200)) "one file was read and its bytes are counted")
    (assert (and (> (listSum good.acc.tokIn) 0) (> (listSum good.acc.tokOut) 0) (> good.acc.spent 0)) "tokens and spend are recorded")
    (assert (not bad.verdict.solved) "the script that edits the wrong constant is not solved")
    (assert (and (not bad.verdict.suiteOk) (= bad.acc.stop "done") (= bad.acc.turns 4)) "its suite is red and the unknown tool cost one reply")
    (assert (and (stringContains? row ":solved true") (stringContains? row ":filesRead 1 ") (stringContains? row ":stop \"done\"")) "the trial row carries the verdict and the read counts")
    (assert cleaned "the work directory is removed")
    true)

fn ! runTests -> Bool
  (let [(given (optionOr (envGet "ASL_CLI_ROOT") "."))
        (root (resultOr (realPath given) given))]
    (and (testPure) (testLoop root)))
