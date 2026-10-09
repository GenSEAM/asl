(module asl-forms/tests/parityTest :x [runTests] :i [(asl-forms/kernel :a k)])


(schema ParityTally (:f cases Int64) (:f failures Int64) (:f unported Int64) (:f aslNs Int64))


fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn envPrefix root: String caseRoot: String -> String
  (str "cd " (shellQuote root) " && unset ASL_ROOT ASL_SESSION; SCRIPT_DIR=" (shellQuote (str root "/bin")) " ROOT_DIR=" (shellQuote caseRoot) " ASL_VFS_DIR=" (shellQuote (str root "/.asl/parityVfs")))

fn aslCommand root: String caseRoot: String form: String -> String
  (str (envPrefix root caseRoot) " " (shellQuote (str root "/asl/host/out/asl-host")) " run " (shellQuote (str root "/asl/packages/asl-forms/src/main.asl"))
       " --root " (shellQuote caseRoot) " " (shellQuote form))

fn snapshotCommit -> String
  "4045414237cd7dbd7cee32ff062e7873e80239a8"

fn snapshotPaths -> (List String)
  (list ".asl/mem/inbox/workspace-20260924-scalarF64Helpers.asn" ".asl/mem/tasks/Phase602GatewaySubscriptionProxyAndSkillsRationalization.asn"
        "README.md" "asl/agentLoop/core.asl" "asl/agentLoop/coreCli.asl" "asl/bin/asl" "asl/grammar"
        "asl/packages/asl-checker/src/resolve.asl" "asl/packages/asl-cli/src/cli.asl" "asl/packages/asl-compiler/src/compiler.asl"
        "asl/packages/asl-ir/src/lower.asl" "asl/packages/asl-ir/src/types.asl" "asl/packages/asl-json/src/json.asl" "asl/packages/asl-lint/src/incongruity.asl"
        "asl/packages/asl-net/src/netClient.asl" "asl/packages/asl-pack/manifest.asn" "asl/packages/asl-pack/src/release.asl"
        "asl/packages/asl-parser/src/indentParser.asl" "asl/packages/asl-proc" "asl/packages/asl-target-llvm"
        "asl/packages/asl-transpile/src/core/asn.asl" "asl/packages/asl-transpile/src/multilens.asl" "asl/packages/asl-transpile/tests/codecTest.asl"
        "bin/asl" "bin/asl-gateway" "code-intel" "mem/tests/taskModularTest.asl" "scripts/agentLoop" (str "scripts/" "aslForms" ".py")
        "scripts/audit/foreignAllowlist.asn" "scripts/audit/foreignBaseline.asn" "scripts/audit/runner.py"
        "tests/acceptance/agentLoop/capBudgetTest.sh" "tests/acceptance/agentLoop/cardTest.sh" "tests/acceptance/agentLoop/truncationTest.sh"
        "tests/acceptance/gateway/configV2Test.sh" "tests/acceptance/observe/tokenCostTest.sh" "tests/agentEval/cases/implement-one-line-fix/truth.asn"
        "tests/fixtures/agentLoop/mvp/fixEcho.asn" "tests/fixtures/agentLoop/mvp/resume.asn" "tools/preCommit.asl")

fn snapshotCommand root: String -> String
  (str "d=$(mktemp -d \"${TMPDIR:-/tmp}/formsParity.XXXXXX\") && git -C " (shellQuote root) " archive --format=tar -o \"$d.tar\" " (snapshotCommit) " --"
       (stringJoin (map (fn [(p String)] -> String (str " " (shellQuote p))) (snapshotPaths)) "")
       " && tar -xf \"$d.tar\" -C \"$d\" && rm -f \"$d.tar\" && cd \"$d\" && pwd -P")

fn materializeSnapshot! root: String -> (Result String String)
  (let [(out (processRun (snapshotCommand root)))
        (dir (stringTrim out.stdout))]
    (if (and (= out.exitCode 0) (stringStartsWith? dir "/") (fileExists? (str dir "/scripts/agentLoop/loop.py")))
      (ok dir)
      (err (str "snapshot of " (snapshotCommit) " failed: exit " (stringFromInt64 out.exitCode) " " out.stderr))))

fn caseRootOf root: String snapshot: String kw: (Map String String) -> String
  (mt (mapGet kw "root")
    ((none) snapshot)
    ((some r) (str root "/" r)))

fn firstDiff a: String b: String i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (!= (stringSlice a i (+ i 1)) (stringSlice b i (+ i 1)))) i (firstDiff a b (+ i 1) n))

fn around s: String at: Int64 -> String
  (optionOr (stringSlice s (max 0 (- at 60)) (min (stringLength s) (+ at 60))) "")

fn timed! cmd: String -> (Pair ProcessOutput Int64)
  (let [(t0 (monotonicNs))
        (out (processRun cmd))]
    (pair out (- (monotonicNs) t0)))

fn rawCRName! root: String -> String
  (let [(dir (str root "/asl/packages/asl-forms/tests/fixtures/ws"))
        (names (resultOr (dirList dir) (list)))]
    (optionOr (listHead (filter (fn [(name String)] -> Bool (listAny? (fn [(c String)] -> Bool (= (charCode c) 13)) (stringChars name))) names)) ""))

fn checkCase! root: String snapshot: String line: String tally: ParityTally -> ParityTally
  (let [(parsed (k/parseStep line))
        (kw parsed.kwargs)
        (formTemplate (stringReplace (optionOr (mapGet kw "form") "") "@ROOT@" root))
        (form (stringReplace formTemplate "@RAWCR@" (rawCRName! root)))
        (caseRoot (caseRootOf root snapshot kw))
        (expect (optionOr (mapGet kw "expect") "exact"))
        (asl (timed! (aslCommand root caseRoot form)))
        (aslOut (pairFirst asl))
        (want (stringReplace (optionOr (mapGet kw "want") "") "@ROOT@" root))
        (wantExit (optionOr (stringToInt64 (optionOr (mapGet kw "exit") "")) -1))
        (got aslOut.stdout)
        (unported (stringContains? got "ERR_NOT_PORTED"))
        (same (if (= expect "fallback")
                (and (stringContains? got ":error ERR_NOT_PORTED") (= wantExit 1) (= want got) (= wantExit aslOut.exitCode))
                (and (= want got) (= wantExit aslOut.exitCode))))
        (at (firstDiff want got 0 (max (stringLength want) (stringLength got))))]
    (do
      (if same
        (print "")
        (println (str "(:parityDiff :case " (stringFromInt64 (+ tally.cases 1)) " :form \"" (k/escapeAsnVal form) "\" :expect " expect
                      " :wantExit " (stringFromInt64 wantExit) " :aslExit " (stringFromInt64 aslOut.exitCode) " :byte " (stringFromInt64 at)
                      " :want \"" (k/escapeAsnVal (around want at)) "\" :asl \"" (k/escapeAsnVal (around got at)) "\" :aslErr \"" (k/escapeAsnVal aslOut.stderr) "\")")))
      (ParityTally :cases (+ tally.cases 1)
                   :failures (+ tally.failures (if same 0 1))
                   :unported (+ tally.unported (if unported 1 0))
                   :aslNs (+ tally.aslNs (pairSecond asl)))))

fn ms ns: Int64 -> String
  (stringFromInt64 (/ ns 1000000))

fn rawCrCaseAt! root: String line: String -> Bool
  (let [(formTemplate (optionOr (mapGet (k/parseStep line).kwargs "form") ""))
        (expanded (stringReplace formTemplate "@RAWCR@" (rawCRName! root)))]
    (and (stringContains? formTemplate "@RAWCR@")
         (listAny? (fn [(c String)] -> Bool (= (charCode c) 13)) (stringChars expanded))))

fn hasRawCr s: String -> Bool
  (listAny? (fn [(c String)] -> Bool (= (charCode c) 13)) (stringChars s))

fn formOfCase line: String -> String
  (optionOr (mapGet (k/parseStep line).kwargs "form") "")

fn isRawCrEcho line: String -> Bool
  (let [(form (formOfCase line))]
    (and (stringContains? form "(:echo :message") (hasRawCr form)))

fn isRawCrReadPath line: String -> Bool
  (let [(form (formOfCase line))]
    (and (stringContains? form "(:read :file \"cr") (hasRawCr form)))

fn workspaceVfsHasX! root: String -> Bool
  (listAny? (fn [(name String)] -> Bool
              (stringContains? (resultOr (fileReadString (str root "/.asl/vfs/" name)) "") "\"rel\": \"x.txt\""))
            (resultOr (dirList (str root "/.asl/vfs")) (list)))

fn markedFallbackCount lines: (List String) -> Int64
  (listLength (filter (fn [(l String)] -> Bool (= (optionOr (mapGet (k/parseStep l).kwargs "expect") "exact") "fallback")) lines))

fn recordedExpectation? line: String -> Bool
  (let [(kw (k/parseStep line).kwargs)]
    (and (some? (mapGet kw "want")) (some? (mapGet kw "exit"))))

fn recordedEvalResult? line: String -> Bool
  (let [(kw (k/parseStep line).kwargs)]
    (and (= (optionOr (mapGet kw "form") "") "(:eval \"1\")")
         (= (optionOr (mapGet kw "want") "") "(:eval :id 1 :status :ok :value \"1\" :stdout \"1\" :exit 0)\n")
         (= (optionOr (mapGet kw "exit") "") "0")))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (corpusText (resultOr (fileReadString (str root "/asl/packages/asl-forms/tests/fixtures/formsCorpus.asn")) ""))
        (caseLines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringSplit corpusText "\n")))
        (n (listLength caseLines))]
    (assert (stringContains? corpusText "Every case records its expected stdout in :want and exit code in :exit") "corpus documents recorded output and exit expectations")
    (assert (>= n 60) "the parity corpus holds at least 60 recorded forms")
    (assert (listAll? recordedExpectation? caseLines) "every corpus case records both stdout and exit expectations")
    (assert (listAny? recordedEvalResult? caseLines) "the live eval result and successful exit are pinned in the parity corpus")
    (assert (listAny? (fn [(l String)] -> Bool (rawCrCaseAt! root l)) caseLines) "the corpus marker expands into a filename containing raw CR")
    (assert (listAny? isRawCrEcho caseLines) "the echo corpus case contains a raw CR byte")
    (assert (listAny? isRawCrReadPath caseLines) "the near-miss read path contains a raw CR byte")
    (assert (listAny? (fn [(c String)] -> Bool (= (charCode c) 13)) (stringChars (rawCRName! root))) "the raw-CR filename marker resolves to a name containing byte 13")
    (assert (stringContains? corpusText (str ":snapshot \"" (snapshotCommit) "\"")) "corpus outputs were recorded against the pinned snapshot commit")
    (assert (ok? (dirCreate (str root "/.asl/parityVfs"))) "create isolated parity VFS")
    (let [(made (materializeSnapshot! root))
          (snapshot (resultOr made ""))]
      (assert (ok? made) (str "materialize the pinned live-tree snapshot: " (mt made ((ok d) d) ((err e) e))))
    (let [(tally (fold (fn [(t ParityTally) (l String)] -> ParityTally (checkCase! root snapshot l t)) (ParityTally :cases 0 :failures 0 :unported 0 :aslNs 0) caseLines))
          (unchanged (not (workspaceVfsHasX! root)))
          (snapshotRemoved (ok? (pathRemove snapshot)))
          (removed (ok? (pathRemove (str root "/.asl/parityVfs"))))]
      (println (str "(:parityTiming :cases " (stringFromInt64 tally.cases) " :failures " (stringFromInt64 tally.failures) " :unported " (stringFromInt64 tally.unported)
                    " :aslMs " (ms tally.aslNs) " :aslPerCallMs " (ms (/ tally.aslNs (max 1 n))) ")"))
      (assert (= tally.cases n) "every corpus case ran")
      (assert (= tally.failures 0) "every corpus form gives the recorded stdout bytes and exit code")
      (assert (= tally.unported (markedFallbackCount caseLines)) "only fallback-marked corpus cases report ERR_NOT_PORTED")
      (assert unchanged "parity writes never mutate the workspace root")
      (assert removed "remove isolated parity VFS before any assertion")
      (assert snapshotRemoved "remove the temporary live-tree snapshot")
      true)))
