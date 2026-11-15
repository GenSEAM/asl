(module asl-cli/tests/repairCmdTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a run)])

fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/repairCmdTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn seedSource -> String
  (str "(module repairFixture/fix\n"
       "  :x [runTests]\n"
       "  :i [])\n\n"
       "fn runTests -> Bool\n"
       "  (do\n"
       "    (assert (= 1 1) \"one\")\n"
       "    true))\n")

fn brokenSource -> String
  (str "(module repairFixture/broken\n  :x []\n  :i [])\n\nfn a -> String\n  \"unterminated\n")

fn readFile path: String -> String
  (resultOr (fileReadString path) "")

fn ! repairRun binary: String root: String env: (List String) args: (List String) -> run/Done
  (run/runOneLimited (run/job (listAppend (list binary "repair") args) root env) (run/limits 120 16))

fn ! cliRun binary: String root: String env: (List String) args: (List String) -> run/Done
  (run/runOneLimited (run/job (listAppend (list binary) args) root env) (run/limits 120 16))

fn goodSource -> String
  (str "(module repairFixture/fix\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do\n    (assert (= 1 1) \"one\")\n    true)\n")

fn receipt path: String changed: String -> String
  (str "(:repair :file \"" path "\" :changed " changed ")")

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (base (scratchBase!))
        (fix (str base "/fixTest.asl"))
        (chk (str base "/checkTest.asl"))
        (bad (str base "/badTest.asl"))
        (seed (seedSource))
        (broken (brokenSource))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)))
        (madeBase (dirCreate base))]
    (do
      (assert (some? built.binary) (str "asl/packages/asl-cli/src/native.asl builds natively: " built.reason))
      (assert (ok? madeBase) "scratch base directory is created")
      (let [(binary (optionOr built.binary ""))
            (env (list "PATH=/usr/bin:/bin" (str "HOME=" base)))
            (wroteFix (ok? (fileWrite fix seed)))
            (wroteChk (ok? (fileWrite chk seed)))
            (wroteBad (ok? (fileWrite bad broken)))]
        (do
          (assert (and wroteFix (and wroteChk wroteBad)) "the seeded files are written")
          (let [(c1 (repairRun binary root env (list "--check" chk)))
                (afterCheck (readFile chk))
                (r1 (repairRun binary root env (list fix)))
                (after1 (readFile fix))
                (r2 (repairRun binary root env (list fix)))
                (after2 (readFile fix))
                (c2 (repairRun binary root env (list "--check" fix)))
                (b1 (repairRun binary root env (list bad)))
                (afterBad (readFile bad))
                (b2 (repairRun binary root env (list "--check" bad)))
                (miss (repairRun binary root env (list (str base "/missing.asl"))))
                (none (repairRun binary root env (list)))
                (m1 (repairRun binary root env (list "--check" fix chk bad)))
                (afterMulti (readFile chk))
                (old (cliRun binary root env (list "fmt" fix)))
                (helpOut (cliRun binary root env (list "help")))
                (removed (pathRemove base))]
            (do
              (assert (= c1.exit 1) (str "--check on a misformatted file exits 1: " c1.out))
              (assert (stringContains? c1.out (receipt chk "true")) (str "--check reports :changed true: " c1.out))
              (assert (= afterCheck seed) "--check leaves the bytes unchanged")
              (assert (= r1.verdict "exit") (str "asl repair ends on its own: " r1.out))
              (assert (= r1.exit 0) (str "asl repair on a misformatted file exits 0: " r1.out))
              (assert (stringContains? r1.out (receipt fix "true")) (str "the first run reports :changed true: " r1.out))
              (assert (= after1 (goodSource)) (str "the stray closing paren is removed and nothing else changes: " after1))
              (assert (and (= r2.exit 0) (stringContains? r2.out (receipt fix "false"))) (str "a second run reports :changed false: " r2.out))
              (assert (= after2 after1) "a second run keeps the formatted text")
              (assert (and (= c2.exit 0) (stringContains? c2.out (receipt fix "false"))) (str "--check on a formatted file exits 0: " c2.out))
              (assert (= b1.exit 1) (str "an unparsable file exits 1: " b1.out))
              (assert (stringContains? b1.out (str "(:repair :file \"" bad "\" :error ")) (str "an unparsable file reports :error: " b1.out))
              (assert (= afterBad broken) "an unparsable file is untouched")
              (assert (= b2.exit 1) (str "--check on an unparsable file exits 1: " b2.out))
              (assert (= miss.exit 1) (str "a missing file exits 1: " miss.out))
              (assert (!= none.exit 0) (str "no file argument is refused: " none.out))
              (assert (= m1.exit 1) (str "multi-file --check with a changed and an erroring file exits 1: " m1.out))
              (assert (and (stringContains? m1.out (receipt fix "false")) (and (stringContains? m1.out (receipt chk "true")) (stringContains? m1.out (str "(:repair :file \"" bad "\" :error ")))) (str "three receipts: unchanged, changed, error: " m1.out))
              (assert (= (listLength (stringSplit (stringTrim m1.out) "\n")) 3) (str "exactly three receipt lines: " m1.out))
              (assert (= afterMulti seed) "multi-file --check writes nothing")
              (assert (and (!= old.exit 0) (stringContains? old.out "ERR_UNKNOWN_COMMAND")) (str "asl fmt is an unknown command: " old.out))
              (assert (= helpOut.exit 0) (str "asl help exits 0: " helpOut.out))
              (assert (stringContains? helpOut.out "repair <file...>") (str "help lists the fmt command: " helpOut.out))
              (assert (ok? removed) "scratch fixture tree removed")
              true))))))
