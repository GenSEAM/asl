(module aslAgent/tests/turnTimeTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk) (asl-tools/fleet/run :a fr)])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! resolveHost hOpt: (Option String) defaultRel: String -> (Option String)
  (match hOpt
    ((some h) (if (fileExists? h)
                (some (resultOr (realPath h) h))
                (do (println (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (assert false (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (none))))
    ((none) (let [p (resultOr (realPath defaultRel) defaultRel)]
              (if (fileExists? p)
                (some p)
                (do (println (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (assert false (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (none))))))

; (:m :ref SPAWNSAFETY-RED :do "every child of this test starts through fleet/run: runGuarded with a timeout, a descendant limit and childEnv, so a verdict kills the whole tree; stdout and stderr stay separate as with processRun")
fn ! sh cmd: String -> fr/ProcOut
  (fr/runGuarded (list "sh" "-c" cmd) (resultOr (realPath ".") ".") (fr/childEnv (list)) (fr/limits 2400 128))

fn ! host -> (Option String)
  (resolveHost (envGet "ASL_HOST") "bin/asl")

fn ! tempDir -> String
  (stringTrim (sh "mktemp -d /tmp/asl-live-loop-XXXXXX").stdout)

fn ! write path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! initCommitRepo root: String initial: String -> Bool
  (and (write (str root "/subject.txt") initial)
    (and (gk/initGitRepo! root "turnTime" "turn-time@example.invalid")
      (write (str root "/unrelated.txt") "outside\n")))

fn fieldAfter text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [start (+ at (stringLength key))
            rest (c/sliceOf text start (stringLength text))]
        (match (stringIndexOf rest "\"") ((some e) (c/sliceOf rest 0 e)) ((none) "")))))

fn ! runMain root: String task: String backend: String extra: String -> fr/ProcOut
  (match (host)
    ((none) (sh "exit 127"))
    ((some h)
     (let [form (str "(:agent :task \"" task "\" :backend \"script/" backend "\" :root \"" root "\" " extra ")")
           prefix (str "ASL_HOST=" (shellQuote h) " ASL_ROOT_DIR=" (shellQuote (resultOr (realPath ".") ".")) " ")
           driver (resultOr (realPath "asl/packages/asl-agent/tests/mainDriver.asl") "asl/packages/asl-agent/tests/mainDriver.asl")
           args (str (shellQuote h) " run " (shellQuote driver) " " (shellQuote form))
           niceProbe (sh "nice -n 15 true 2>&1")
           niceOk (and (= niceProbe.exitCode 0)
                       (not (stringContains? (str niceProbe.stdout niceProbe.stderr) "Operation not permitted")))]
       (sh (str prefix (if niceOk (str "nice -n 15 " args) args))))))


fn ! stageFixture root: String name: String -> Bool
  (let [fixture (str "asl/packages/asl-agent/tests/fixtures/liveLoop/" name ".asn")
        target (str root "/tests/fixtures/agentLoop/mvp/" name ".asn")]
    (match (fileReadString fixture)
      ((err _) false)
      ((ok text) (write target text))))

fn intAfter line: String key: String -> Int64
  (match (stringIndexOf line key)
    ((none) -1)
    ((some at)
      (let [rest (c/sliceOf line (+ at (stringLength key)) (stringLength line))
            end (optionOr (stringIndexOf rest " ") (optionOr (stringIndexOf rest ")") (stringLength rest)))]
        (optionOr (stringToInt64 (c/sliceOf rest 0 end)) -1))))

fn rowsOf journal: String -> (List String)
  (filter (fn [l] (stringStartsWith? l "(:turnTime ")) (stringLines journal))

fn rowSound line: String -> Bool
  (let [m (intAfter line ":modelMs ")
        g (intAfter line ":gateMs ")
        t (intAfter line ":toolMs ")
        x (intAfter line ":totalMs ")]
    (and (>= m 0) (and (>= g 0) (and (>= t 0) (>= x (+ m g))))))

fn ! runTests -> Bool
  (match (host)
    ((none) false)
    ((some _)
      (let [root (tempDir)
            dirs (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
            fixture (stageFixture root "edit")
            cfg (write (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n")
            ready (and dirs (and fixture (and cfg (initCommitRepo root "before\n"))))
            ran (runMain root "write then gate" "edit" ":mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\")")
            session (fieldAfter ran.stdout ":session \"")
            journal (readOr (str root "/.asl/run/agentLoop/" session ".journal"))
            rows (rowsOf journal)
            replies (listLength (filter (fn [l] (stringContains? l " :reply ")) (stringLines journal)))
            cleaned (ok? (pathRemove root))]
        (assert ready "the fixture repo is ready")
        (assert (stringContains? journal "(:result :status :ok") "the fake-model run ends ok")
        (assert (and (>= replies 2) (= (listLength rows) replies)) "one (:turnTime ...) row per turn")
        (assert (listAll? rowSound rows) "every turnTime row has nonnegative fields and totalMs >= modelMs + gateMs")
        (assert (and (stringContains? journal "(:turnTime :turn 1 :modelMs ") (stringContains? journal "(:turnTime :turn 2 :modelMs ")) "rows are numbered by turn")
        (assert cleaned "temporary root removed")
        true)))
