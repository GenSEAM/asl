(module asl/agentLoop/tests/aslOpsTest
  :x [runTests]
  :i [(asl/agentLoop/aslOps :a o)
      (asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

fn getStr kv: (List (Pair String c/KvVal)) key: String -> String
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (mt (pairSecond p) ((c/kvStr s) s) ((c/kvInt s) s)))
    (none ""))

fn getInt kv: (List (Pair String c/KvVal)) key: String -> Int64
  (optionOr (stringToInt64 (getStr kv key)) -1)

fn ! getFloat kv: (List (Pair String c/KvVal)) key: String -> Float64
  (let [text (getStr kv key)
        parsed (stringToFloat64 text)]
    (do (assert (some? parsed) (str (getStr kv "id") ": fixture " key " parses as a float: " text))
        (optionOr parsed 0.0)))

fn getBool kv: (List (Pair String c/KvVal)) key: String -> Bool
  (= (getStr kv key) "true")

fn items s: String -> (List String)
  (map (fn [f] (getStr (c/parseKv f) "p")) (c/parseForms s))

fn place s: String real: String link: String -> String
  (stringReplace (stringReplace s "@REAL@" real) "@ROOT@" link)

fn unplace s: String real: String link: String -> String
  (stringReplace (stringReplace s real "@REAL@") link "@ROOT@")

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! writeOk path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! runOk argv: (List String) -> Bool
  (mt (procSpawnv argv (none) (none))
    ((ok sp) (= (procWaitPid sp.pid false) (ok (some 0))))
    ((err _) false))

fn ! buildTree real: String -> Bool
  (let [binDir (str real "/bin")
        steps (list
                (ok? (dirCreate real))
                (ok? (dirCreate binDir))
                (writeOk (str real "/short.txt") (stringJoin (map (fn [i] (str "line " (stringFromInt64 i) "\n")) (range 1 11)) ""))
                (writeOk (str real "/long.txt") (stringJoin (map (fn [i] (str "line " (stringFromInt64 i) "\n")) (range 1 81)) ""))
                (writeOk (str real "/empty.txt") "")
                (writeOk (str real "/sample.asl") "(module test/sample :x [foo bar])\n\nfn foo x: Int64 -> Int64\n  (+ x 1)\n\nfn bar s: String -> String\n  s\n")
                (writeOk (str real "/lines.txt") (stringJoin (map (fn [i] (str "alpha " (stringFromInt64 i) "\n")) (range 1 101)) ""))
                (writeOk (str real "/target.txt") "hello world\nsecond line\n")
                (writeOk (str binDir "/stubEcho") "#!/bin/sh\necho \"stub out: $@ root=$ASL_ROOT\"\necho \"stub note\" >&2\n")
                (writeOk (str binDir "/stubErr") "#!/bin/sh\necho \"stub err: $@\" >&2\nexit 2\n")
                (writeOk (str binDir "/stubSleep") "#!/bin/sh\nsleep 10\n")
                (runOk (list "chmod" "755" (str binDir "/stubEcho") (str binDir "/stubErr") (str binDir "/stubSleep"))))]
    (listAll? (fn [b] b) steps))

fn ! repoFor real: String link: String id: String binKind: String -> String
  (let [repo (str real "/" id)
        made (and (ok? (dirCreate repo)) (ok? (dirCreate (str repo "/bin"))))
        target (str repo "/bin/asl")
        placed (cond
                 ((stringStartsWith? binKind "link:")
                   (runOk (list "ln" "-s" (str real "/bin/" (c/sliceOf binKind 5 (stringLength binKind))) target)))
                 ((= binKind "plain") (writeOk target "#!/bin/sh\necho never\n"))
                 (else (= binKind "missing")))]
    (do (assert (and made placed) (str id ": repo root " binKind " set up"))
        (str link "/" id)))

fn ! replayBudgetCase form: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        hasAt (getBool kv "hasAt")
        atVal (if hasAt (some (getFloat kv "at")) (none))
        nowVal (getFloat kv "now")
        wantNone (getBool kv "wantNone")
        wantBudget (getFloat kv "wantBudget")
        got (o/budgetLeft atVal nowVal)]
    (if wantNone
      (do (assert (none? got) (str id ": budgetLeft is none")) true)
      (do (assert (some? got) (str id ": budgetLeft is some"))
          (assert (< (abs (- (optionOr got 0.0) wantBudget)) 0.0001) (str id ": budgetLeft value matches"))
          true)))

fn ! replayStepTimeoutCase form: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        rtimeout (getInt kv "runTimeout")
        hasAt (getBool kv "hasAt")
        atVal (if hasAt (some (getFloat kv "at")) (none))
        nowVal (getFloat kv "now")
        wantTimeout (getInt kv "wantTimeout")
        got (o/stepTimeout rtimeout atVal nowVal)]
    (do (assert (= got wantTimeout) (str id ": stepTimeout matches")) true))

fn ! darwin? -> Bool
  (mt (platformInfo) ((ok p) (= p.os "Darwin")) ((err _) false))

fn ! replayTransportCase form: String real: String root: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        envVal (getStr kv "transportEnv")
        sockPath (place (getStr kv "sockPath") real root)
        exists (getBool kv "exists")
        made (if exists (writeOk sockPath "not a socket\n") true)
        wantMode (getStr kv "wantMode")
        wantWhy (place (getStr kv "wantWhy") real root)
        wantField (place (getStr kv "wantField") real root)
        pairRes (o/chooseTransport envVal sockPath)
        gotMode (pairFirst pairRes)
        gotWhy (pairSecond pairRes)
        gotField (o/transportField gotMode gotWhy)]
    (do (assert made (str id ": socket path set up"))
        (assert (= gotMode wantMode) (str id ": mode matches"))
        (if exists
          (do (assert (stringStartsWith? gotWhy (str "no ping answer at " sockPath ": [Errno ")) (str id ": why says the ping at this path got no answer, with the errno"))
              (assert (stringEndsWith? gotWhy "] Socket operation on non-socket") (str id ": connecting to a file that is not a socket fails with ENOTSOCK"))
              (assert (or (!= id "pingRefused") (not (darwin?)) (= gotWhy wantWhy)) (str id ": on Darwin, where the fixture was recorded, why equals the original"))
              (assert (stringContains? wantWhy sockPath) (str id ": the original fell back on the same path"))
              (assert (= gotField (str ":transport :" wantMode " :transportWhy \"" (c/escapeAsn gotWhy) "\"")) (str id ": field matches the fallback")))
          (do (assert (= gotWhy wantWhy) (str id ": why matches"))
              (assert (= gotField wantField) (str id ": field matches"))))
        true))

fn ! replayNearestLinesCase form: String root: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        file (getStr kv "file")
        old (getStr kv "old")
        isNone (getBool kv "isNone")
        spanFirst (getInt kv "spanFirst")
        spanLast (getInt kv "spanLast")
        wantContent (getStr kv "wantContent")
        got (o/nearestLines root file old)]
    (if isNone
      (do (assert (none? got) (str id ": nearestLines is none")) true)
      (do (assert (some? got) (str id ": nearestLines is some"))
          (mt (optionOr got (pair (pair 0 0) ""))
            ((pair p cnt)
              (do (assert (= (pairFirst p) spanFirst) (str id ": spanFirst matches"))
                  (assert (= (pairSecond p) spanLast) (str id ": spanLast matches"))
                  (assert (= cnt wantContent) (str id ": content matches"))
                  true))))))

fn ! replayPlaceholderCase form: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        text (getStr kv "text")
        wantMatch (getBool kv "wantMatch")
        got (o/placeholderAssert? text)]
    (do (assert (= got wantMatch) (str id ": placeholder matches")) true))

fn ! replayRunBoundedCase form: String real: String root: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        rawArgv (items (getStr kv "argv"))
        hasTimeout (getBool kv "hasTimeout")
        timeoutSec (if hasTimeout (some (getInt kv "timeoutSec")) (none))
        hasError (getBool kv "hasError")
        wantCode (getInt kv "exitCode")
        wantOut (getStr kv "stdout")
        wantErr (getStr kv "stderr")
        wantErrText (getStr kv "errText")
        wantTimedOut (getBool kv "timedOut")
        argv (map (fn [a] (place a real root)) rawArgv)
        res (o/runBounded argv (some root) timeoutSec (none))]
    (if hasError
      (do (assert (err? res) (str id ": runBounded spawn error expected"))
          (mt res
            ((err m) (assert (= (unplace m real root) wantErrText) (str id ": spawn error text matches")))
            ((ok _) (assert (err? res) (str id ": spawn error text present"))))
          true)
      (do (assert (ok? res) (str id ": runBounded ok expected"))
          (let [b (resultOr res (o/Bounded :code (none) :out "" :errText "" :timedOut false))]
            (assert (= (optionOr b.code -1) wantCode) (str id ": exit code matches"))
            (assert (= (unplace b.out real root) wantOut) (str id ": stdout matches"))
            (assert (= (unplace b.errText real root) wantErr) (str id ": stderr matches"))
            (assert (= b.timedOut wantTimedOut) (str id ": timedOut matches"))
            true))))

fn ! replayRunAslCase form: String real: String root: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        repo (repoFor real root id (getStr kv "binKind"))
        rawMode (getStr kv "mode")
        mode (if (= rawMode "none") "" rawMode)
        aslForm (getStr kv "form")
        timeoutSec (getInt kv "timeoutSec")
        res (o/runAsl repo aslForm root timeoutSec (none) mode)]
    (do (assert (= (o/runExit res) (getInt kv "exitCode")) (str id ": runAsl exit matches"))
        (assert (= (unplace (o/runStdout res) real root) (getStr kv "stdout")) (str id ": runAsl stdout matches"))
        (assert (= (unplace (o/runStderr res) real root) (getStr kv "stderr")) (str id ": runAsl stderr matches got=" (o/runStderr res) " want=" (getStr kv "stderr")))
        (assert (= (o/runTimedOut res) (getBool kv "timedOut")) (str id ": runAsl timedOut matches"))
        (assert (= (o/runSeconds res) (getInt kv "seconds")) (str id ": runAsl seconds matches"))
        (assert (if (getBool kv "fellBack") (stringEndsWith? (o/runFellBack res) "] No such file or directory") (= (o/runFellBack res) "")) (str id ": runAsl fellBack names the failed connect to the absent engine socket"))
        true))

fn ! snapInto path: String file: String -> Bool
  (writeOk path (str (readOr path) "(:o :p " (c/serString file) ")"))

fn ! replayExecCase form: String real: String root: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        opForm (getStr kv "op")
        ownsList (items (getStr kv "owns"))
        rExit (getInt kv "runExit")
        rOut (getStr kv "runStdout")
        rErr (getStr kv "runStderr")
        cap (getInt kv "readCap")
        budgetStr (getStr kv "budget")
        budgetVal (if (= budgetStr "none") (none) (some (getFloat kv "budget")))
        expectedSent (getStr kv "sentForm")
        want (getStr kv "want")
        sentLog (str root "/sent.log")
        snapLog (str root "/snaps.log")
        cleared (and (writeOk sentLog "") (writeOk snapLog ""))
        fakeRun (fn [f r]
                  (if (writeOk sentLog f)
                    (if (stringContains? f ":intel :op outline")
                      (t/aslRun 0 "(:intel :op outline (:item :name \"foo\" :kind \"fn\" :start 3 :end 5))" "")
                      (t/aslRun rExit rOut rErr))
                    (t/aslRun 99 "" "sent.log write failed")))
        fakeSnap (fn [f] (snapInto snapLog f))
        fakeId (fn [] "testId123456")
        opKv (c/parseKv opForm)
        rec (o/execAslOpCustom! opKv ownsList root fakeId fakeSnap fakeRun cap budgetVal)
        gotSer (unplace (o/serReceipt rec) real root)]
    (do (assert cleared (str id ": logs cleared"))
        (assert (= gotSer want) (str id ": receipt equality"))
        (assert (= (items (readOr snapLog)) (items (getStr kv "snaps"))) (str id ": snapshot calls equality"))
        (if (!= expectedSent "")
          (assert (= (readOr sentLog) expectedSent) (str id ": sentForm equality"))
          (assert (= (readOr sentLog) "") (str id ": nothing sent")))
        true))

fn ! replayLiveCase form: String real: String root: String -> Bool
  (let [kv (c/parseKv form)
        id (getStr kv "id")
        repo (repoFor real root id (getStr kv "binKind"))
        snapLog (str root "/snaps.log")
        cleared (writeOk snapLog "")
        deadlineStr (getStr kv "deadlineIn")
        deadlineAt (if (= deadlineStr "none") (none) (some (+ (o/nowMono) (getFloat kv "deadlineIn"))))
        rec (o/execAslOp! (c/parseKv (getStr kv "op")) (items (getStr kv "owns")) root repo "subprocess" (none)
              (fn [] "liveId000001") (fn [f] (snapInto snapLog f)) 8000 (getInt kv "runTimeout") deadlineAt)
        gotSer (unplace (o/serReceipt rec) real root)]
    (do (assert cleared (str id ": snapshot log cleared"))
        (assert (= gotSer (getStr kv "want")) (str id ": live receipt equality"))
        (assert (= (items (readOr snapLog)) (items (getStr kv "snaps"))) (str id ": live snapshot calls equality"))
        true))

fn ! replayCase head: String f: String real: String root: String -> Bool
  (cond
    ((= head "budgetCase") (replayBudgetCase f))
    ((= head "stepTimeoutCase") (replayStepTimeoutCase f))
    ((= head "transportFieldCase") (replayTransportCase f real root))
    ((= head "nearestLinesCase") (replayNearestLinesCase f root))
    ((= head "placeholderCase") (replayPlaceholderCase f))
    ((= head "runBoundedCase") (replayRunBoundedCase f real root))
    ((= head "runAslCase") (replayRunAslCase f real root))
    ((= head "execCase") (replayExecCase f real root))
    ((= head "liveCase") (replayLiveCase f real root))
    (else false))

fn ! runAllCases forms: (List String) real: String root: String acc: Int64 -> Int64
  (if (listEmpty? forms)
    acc
    (let [f (c/firstOf forms)
          ran (replayCase (c/headOf f) f real root)]
      (runAllCases (c/restOf forms) real root (if ran (+ acc 1) acc))))

fn ! runTests -> Bool
  (let [fixText (resultOr (fileReadString "asl/agentLoop/tests/aslOpsFixtures.asn") "")
        forms (c/parseForms fixText)
        header (c/parseKv (c/firstOf forms))
        tmpBase (str "/tmp/aslOpsTest_" (stringFromInt64 (monotonicNs)))
        real (str tmpBase "/real")
        link (str tmpBase "/link")
        repoRoot (resultOr (realPath ".") "")
        based (ok? (dirCreate tmpBase))
        built (buildTree real)
        linked (runOk (list "ln" "-s" real link))
        setUp (do (assert (and based (and built linked)) "test tree set up") true)
        missingRepo (str real "/missing-repo")
        forcedEnv (some (list "ASL_SESSION=forced" (str "ASL_VFS_DIR=" real "/forced-vfs")))
        forcedIn (o/runAsl repoRoot "(:read :file \"absent\")" link 5 forcedEnv "inProcess")
        envForcedIn (o/runAsl missingRepo "(:read :file \"absent\")" link 5 (some (list "ASL_TRANSPORT=inProcess")) "")
        mixed (o/runAsl missingRepo "(:read :file \"absent\") (:test :file \"absent.asl\")" link 5 (none) "")
        customAuto (o/runAsl missingRepo "(:read :file \"absent\")" link 5 (some (list "PATH=/usr/bin")) "")
        defaultIntel (o/runAsl missingRepo "(:intel :op outline :file \"sample.asl\")" link 5 (none) "")
        defaultMemoryObserve (o/runAsl missingRepo "(:observe :dim memory)" link 5 (none) "")
        transportAssertions
          (do (assert (and (!= (o/runStdout forcedIn) "") (= (o/runStderr forcedIn) ""))
                "an explicit inProcess request can use its available toolchain with supplied overrides")
              (assert (and (!= (o/runStdout envForcedIn) "") (= (o/runStderr envForcedIn) ""))
                "ASL_TRANSPORT=inProcess stays in-process with a caller-supplied environment")
              (assert (and (= (o/runStdout mixed) "") (!= (o/runStderr mixed) ""))
                "safe-prefix payload with a later test form is kept on the killable subprocess path")
              (assert (and (= (o/runStdout customAuto) "") (!= (o/runStderr customAuto) ""))
                "custom child environment without staging keys is not run against host staging")
              (assert (and (= (o/runExit defaultIntel) 0) (stringContains? (o/runStdout defaultIntel) "(:intel")
                           (= (o/runStderr defaultIntel) ""))
                (str "default intel outline dispatches in-process through the existing runAsl entry point: exit="
                     (stringFromInt64 (o/runExit defaultIntel)) " stdout=" (o/runStdout defaultIntel) " stderr=" (o/runStderr defaultIntel)))
              (assert (and (= (o/runExit defaultMemoryObserve) 0) (stringContains? (o/runStdout defaultMemoryObserve) "(:observe")
                           (= (o/runStderr defaultMemoryObserve) ""))
                "default memory observe dispatches in-process through the existing runAsl entry point")
              true)
        n (runAllCases (c/restOf forms) real link 0)
        cleaned (runOk (list "rm" "-rf" tmpBase))]
    (do (assert transportAssertions "new transport behavior assertions completed")
        (assert (= n (getInt header "cases")) "executed every fixture case")
        (assert cleaned "test tree removed")
        true))
