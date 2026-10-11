(module asl-cli/sweep
  :x [main Done workspace! timeoutWanted! jobsWanted! plan! report! frozenCountFor! changedPlan! changedReport! changedDry! lastLine]
  :i [(asl/packages/asl-gates/src/suiteRunner :a runner) (asl/packages/asl-gates/src/dyck :a dyck) (tools/testImpact :a impact)])

(schema Job
  (:f index Int64)
  (:f path String)
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f out String)
  (:f errText String)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f code (Option Int64))
  (:f deadlineNs Int64))

(schema Done
  (:f index Int64)
  (:f path String)
  (:f code Int64)
  (:f last String)
  (:f out String))

(schema Pool
  (:f pending (List (Pair Int64 String)))
  (:f running (List Job))
  (:f done (List Done)))

fn esc text: String -> String
  (stringReplace (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn say! text: String -> Bool
  (do (println text) true)

fn negative? path: String -> Bool
  (or (stringStartsWith? path "asl/grammar/corpus/")
      (listAny? (fn [(seg String)] -> Bool (or (= seg "invalid") (or (= seg "fixtures") (= seg "node_modules")))) (stringSplit path "/")))

fn ! capture! argv: (List String) cwd: (Option String) -> (Result (Pair Int64 String) String)
  (mt (procSpawnv argv cwd (none))
    ((err e) (err (str (optionOr (listHead argv) "") ": " e)))
    ((ok sp)
      (let [(closed (fdClose sp.stdin))
            (j (Job :index 0 :path "" :pid sp.pid :outFd sp.stdout :errFd sp.stderr :out "" :errText "" :outOpen true :errOpen true :code (none) :deadlineNs (+ (monotonicNs) 600000000000)))]
        (mt (drain! j)
          ((err e) (err e))
          ((ok d) (if (ok? closed) (ok (pair (optionOr d.code 1) d.out)) (err "close stdin failed")))))))

fn ! drain! j: Job -> (Result Job String)
  (if (finished? j)
    (ok j)
    (mt (procPoll (watchFds (list j)) (livePids (list j)) -1)
      ((err e) (err (str "procPoll: " e)))
      ((ok ready) (mt (absorb! j (pairFirst ready) (pairSecond ready)) ((err e) (err e)) ((ok j2) (drain! j2))))))

fn ! workspace! -> (Result String String)
  (let [(env (optionOr (envGet "ASL_ROOT") ""))]
    (if (not (stringEmpty? env))
      (ok (resultOr (realPath env) env))
      (mt (capture! (list "git" "rev-parse" "--show-toplevel") (none))
        ((ok r) (ok (if (and (= (pairFirst r) 0) (not (stringEmpty? (stringTrim (pairSecond r))))) (stringTrim (pairSecond r)) (resultOr (realPath ".") "."))))
        ((err e) (err e)))))

fn trackedEntry! ws: String entry: String -> (Option String)
  (mt (stringIndexOf entry "\t")
    ((none) (none))
    ((some i)
      (let [(meta (optionOr (stringSlice entry 0 i) ""))
            (path (optionOr (stringSlice entry (+ i 1) (stringLength entry)) ""))]
        (if (or (stringStartsWith? meta "120000") (or (negative? path) (or (stringStartsWith? path "tests/acceptance/r1Host/") (not (isFile? (str ws "/" path))))))
          (none)
          (some path)))))

fn ! isFile? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! tracked! ws: String patterns: (List String) -> (Result (List String) String)
  (mt (procSpawnv (listAppend (list "git" "ls-files" "-s" "-z" "--") patterns) (some ws) (none))
    ((err e) (err (str "git: " e)))
    ((ok sp)
      (let [(closed (fdClose sp.stdin))
            (j (Job :index 0 :path "" :pid sp.pid :outFd sp.stdout :errFd sp.stderr :out "" :errText "" :outOpen true :errOpen true :code (none) :deadlineNs (+ (monotonicNs) 600000000000)))]
        (mt (drain! j)
          ((err e) (err e))
          ((ok d)
            (if (!= (optionOr d.code 1) 0)
              (err (esc (stringTrim d.errText)))
              (ok (fold (fn [(acc (List String)) (entry String)] -> (List String) (mt (trackedEntry! ws entry) ((some p) (listAppend acc (list p))) ((none) acc)))
                        (list)
                        (filter (fn [(e String)] -> Bool (not (stringEmpty? e))) (stringSplit d.out "\u{0}"))))))))))

fn watchFds jobs: (List Job) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (j Job)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if j.outOpen (list (pair j.outFd 1)) (list)) (if j.errOpen (list (pair j.errFd 1)) (list)))))
        (list) jobs)

fn livePids jobs: (List Job) -> (List Int64)
  (map (fn [(j Job)] -> Int64 j.pid) (filter (fn [(j Job)] -> Bool (none? j.code)) jobs))

fn readyFd? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn exitOf exited: (List (Pair Int64 Int64)) pid: Int64 -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (p (Pair Int64 Int64))] -> (Option Int64) (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) exited)

fn ! readSide! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((err e) (err (str "read fd " (stringFromInt64 fd) ": " e)))
    ((ok chunk)
      (if (> (stringLength chunk) 0)
        (ok (some chunk))
        (mt (fdClose fd) ((err e) (err (str "close fd " (stringFromInt64 fd) ": " e))) ((ok _) (ok (none)))))))

fn ! absorb! j: Job readyFds: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) -> (Result Job String)
  (let [(outR (if (and j.outOpen (readyFd? readyFds j.outFd)) (readSide! j.outFd) (ok (some ""))))
        (errR (if (and j.errOpen (readyFd? readyFds j.errFd)) (readSide! j.errFd) (ok (some ""))))
        (code (if (some? j.code) j.code (exitOf exited j.pid)))]
    (mt outR
      ((err e) (err e))
      ((ok o)
        (mt errR
          ((err e) (err e))
          ((ok x)
            (ok (with j :out (str j.out (optionOr o "")) :errText (str j.errText (optionOr x "")) :outOpen (and j.outOpen (some? o)) :errOpen (and j.errOpen (some? x)) :code code)))))))

fn finished? j: Job -> Bool
  (and (some? j.code) (and (not j.outOpen) (not j.errOpen)))

fn lastLine text: String -> String
  (let [(lines (stringSplit (stringTrim (stringReplace text "\r\n" "\n")) "\n"))]
    (optionOr (listLast lines) ""))

fn toDone j: Job -> Done
  (Done :index j.index :path j.path :code (optionOr j.code 1) :last (lastLine (str j.out "\n" j.errText)) :out j.out)

fn ! killJob! j: Job timeoutS: Int64 -> Done
  (let [(killed (if (none? j.code) (procKill (- 0 j.pid) "SIGKILL") (ok ())))
        (reaped (if (none? j.code) (procWaitPid j.pid false) (ok (none))))
        (o (if j.outOpen (fdClose j.outFd) (ok ())))
        (e (if j.errOpen (fdClose j.errFd) (ok ())))]
    (Done :index j.index :path j.path :code 124
          :last (if (and (ok? killed) (and (ok? reaped) (and (ok? o) (ok? e)))) (str "timed out after " (stringFromInt64 timeoutS) "s") (str "timed out after " (stringFromInt64 timeoutS) "s; kill or reap failed"))
          :out ""))

fn ! start! host: String verb: String ws: String timeoutS: Int64 job: (Pair Int64 String) -> (Result Job Done)
  (mt (procSpawnv (list host verb (pairSecond job)) (some ws) (none))
    ((err e) (err (Done :index (pairFirst job) :path (pairSecond job) :code 127 :last (str "cannot run " host ": " e) :out "")))
    ((ok sp)
      (mt (fdClose sp.stdin)
        ((err e) (do (procKill (- 0 sp.pid) "SIGKILL") (procWaitPid sp.pid false) (fdClose sp.stdout) (fdClose sp.stderr)
                     (err (Done :index (pairFirst job) :path (pairSecond job) :code 127 :last (str "close stdin: " e) :out ""))))
        ((ok _) (ok (Job :index (pairFirst job) :path (pairSecond job) :pid sp.pid :outFd sp.stdout :errFd sp.stderr :out "" :errText ""
                         :outOpen true :errOpen true :code (none) :deadlineNs (+ (monotonicNs) (* timeoutS 1000000000))))))))

fn ! fill! host: String verb: String ws: String timeoutS: Int64 k: Int64 p: Pool -> Pool
  (mt (listHead p.pending)
    ((none) p)
    ((some job)
      (if (>= (listLength p.running) k)
        p
        (let [(rest (optionOr (listTail p.pending) (list)))]
          (mt (start! host verb ws timeoutS job)
            ((ok j) (fill! host verb ws timeoutS k (with p :pending rest :running (listAppend p.running (list j)))))
            ((err d) (fill! host verb ws timeoutS k (with p :pending rest :done (cons d p.done)))))))))

fn ! absorbAll! jobs: (List Job) readyFds: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) acc: (List Job) -> (Result (List Job) String)
  (mt (listHead jobs)
    ((none) (ok acc))
    ((some j) (mt (absorb! j readyFds exited) ((err e) (err e)) ((ok j2) (absorbAll! (optionOr (listTail jobs) (list)) readyFds exited (listAppend acc (list j2)))))))

fn earliest! jobs: (List Job) -> Int64
  (fold (fn [(acc Int64) (j Job)] -> Int64 (min acc j.deadlineNs)) (+ (monotonicNs) 3600000000000) jobs)

fn ! poolLoop! host: String verb: String ws: String timeoutS: Int64 k: Int64 p: Pool -> (Result (List Done) String)
  (let [(p1 (fill! host verb ws timeoutS k p)) (running p1.running)]
    (if (listEmpty? running)
      (ok p1.done)
      (let [(waitMs (max 0 (/ (- (earliest! running) (monotonicNs)) 1000000)))]
        (mt (procPoll (watchFds running) (livePids running) waitMs)
          ((err e) (err (str "procPoll: " e)))
          ((ok ready)
            (mt (absorbAll! running (pairFirst ready) (pairSecond ready) (list))
              ((err e) (err e))
              ((ok jobs)
                (let [(now (monotonicNs))
                      (expired (filter (fn [(j Job)] -> Bool (and (not (finished? j)) (>= now j.deadlineNs))) jobs))
                      (complete (filter finished? jobs))
                      (live (filter (fn [(j Job)] -> Bool (and (not (finished? j)) (< now j.deadlineNs))) jobs))
                      (collected (listAppend (map toDone complete) (map (fn [(j Job)] -> Done (killJob! j timeoutS)) expired)))]
                  (poolLoop! host verb ws timeoutS k (Pool :pending p1.pending :running live :done (listAppend p1.done collected)))))))))))

fn digitRunStart b: Bytes i: Int64 -> Int64
  (if (and (> i 0) (and (>= (bytesGet b (- i 1)) 48) (<= (bytesGet b (- i 1)) 57))) (digitRunStart b (- i 1)) i)

fn firstCount text: String marker: String -> Int64
  (mt (stringIndexOf text marker)
    ((none) 0)
    ((some i)
      (let [(start (digitRunStart (stringToBytes text) i))]
        (if (< start i)
          (optionOr (stringToInt64 (optionOr (stringSlice text start i) "")) 0)
          (firstCount (optionOr (stringSlice text (+ i (stringLength marker)) (stringLength text)) "") marker)))))

fn truncateChars text: String n: Int64 -> String
  (let [(chars (stringChars text))]
    (if (<= (listLength chars) n) text (stringJoin (listTake chars n) "")))

fn ! cpuCount! -> (Result Int64 String)
  (mt (capture! (list "getconf" "_NPROCESSORS_ONLN") (none))
    ((ok r) (mt (stringToInt64 (stringTrim (pairSecond r))) ((some n) (ok n)) ((none) (err "getconf _NPROCESSORS_ONLN printed no count"))))
    ((err e) (err (str "cpu count: " e))))

fn ! jobsWanted! -> (Result Int64 String)
  (let [(v (optionOr (envGet "ASL_JOBS") ""))]
    (if (stringEmpty? v)
      (cpuCount!)
      (mt (stringToInt64 (stringTrim v)) ((some n) (ok n)) ((none) (err (str "ASL_JOBS is not an integer: " v))))))

fn ! timeoutWanted! -> (Result Int64 String)
  (let [(v (optionOr (envGet "ASL_SWEEP_TIMEOUT_S") "300"))]
    (mt (stringToInt64 (stringTrim v)) ((some n) (ok n)) ((none) (err (str "ASL_SWEEP_TIMEOUT_S is not an integer: " v)))))

fn ! unbalancedOf! ws: String paths: (List String) -> (Result (List (Pair String (Pair Int64 String))) String)
  (fold (fn [(acc (Result (List (Pair String (Pair Int64 String))) String)) (p String)] -> (Result (List (Pair String (Pair Int64 String))) String)
          (mt acc
            ((err e) (err e))
            ((ok found)
              (mt (fileReadBytes (str ws "/" p))
                ((err e) (err (str p ": " e)))
                ((ok b) (mt (dyck/check b (not (stringEndsWith? p ".asl"))) ((none) (ok found)) ((some r) (ok (listAppend found (list (pair p r)))))))))))
        (ok (list))
        paths)

fn ! plan! verb: String ws: String -> (Result (Pair (List String) (List (Pair String (Pair Int64 String)))) String)
  (if (= verb "test")
    (mt (runner/discover ws (list))
      ((err e) (err e))
      ((ok disc) (ok (pair (filter (fn [(p String)] -> Bool (stringEndsWith? p ".asl")) disc) (list)))))
    (mt (tracked! ws (list "*.asl" "*.asn"))
      ((err e) (err e))
      ((ok all)
        (mt (unbalancedOf! ws all)
          ((err e) (err e))
          ((ok bad)
            (mt (tracked! ws (list "*.asl"))
              ((err e) (err e))
              ((ok asl) (ok (pair (filter (fn [(p String)] -> Bool (not (listAny? (fn [(u (Pair String (Pair Int64 String)))] -> Bool (= (pairFirst u) p)) bad))) asl) bad)))))))))

fn ! frozenCountFor! verb: String ws: String -> Int64
  (if (= verb "test") (resultOr (runner/frozenCount ws (list)) 0) 0)

fn ! report! verb: String runnerName: String files: (List String) bad: (List (Pair String (Pair Int64 String))) done: (List Done) frozen: Int64 -> Int64
  (let [(shown (map (fn [(u (Pair String (Pair Int64 String)))] -> Bool
                      (say! (str "(:fail :file \"" (esc (pairFirst u)) "\" :error ERR_UNBALANCED :byte " (stringFromInt64 (pairFirst (pairSecond u))) " :ev \"" (esc (pairSecond (pairSecond u))) "\")")))
                    bad))
        (ordered (listSortBy (fn [(d Done)] -> Int64 d.index) done))
        (passed (filter (fn [(d Done)] -> Bool (= d.code 0)) ordered))
        (failedRuns (filter (fn [(d Done)] -> Bool (!= d.code 0)) ordered))
        (printed (map (fn [(d Done)] -> Bool (say! (str "(:fail :file \"" (esc d.path) "\" :exit " (stringFromInt64 d.code) " :ev \"" (esc (truncateChars d.last 300)) "\")"))) failedRuns))
        (asserts (fold (fn [(acc Int64) (d Done)] -> Int64 (+ acc (firstCount d.out " assertion(s) executed"))) 0 passed))
        (refutes (fold (fn [(acc Int64) (d Done)] -> Int64 (+ acc (firstCount d.out " refutation(s) executed"))) 0 passed))
        (failed (+ (listLength failedRuns) (listLength bad)))
        (green (and (= failed 0) (> (listLength passed) 0)))
        (counts (if (= verb "test")
                  (str " :executedAsserts " (stringFromInt64 asserts) " :executedRefutes " (stringFromInt64 refutes))
                  (str " :unbalanced " (stringFromInt64 (listLength bad)))))]
    (do (say! (str "(:sweep :verb " verb " :runner \"" runnerName "\" :status " (if green ":passed" ":failed") " :files " (stringFromInt64 (+ (listLength files) (listLength bad)))
                  " :passed " (stringFromInt64 (listLength passed)) " :failed " (stringFromInt64 failed) counts " :frozen " (stringFromInt64 frozen) ")"))
        (if green 0 1)))

fn ! sweep! verb: String host: String -> (Result Int64 String)
  (mt (workspace!)
    ((err e) (err e))
    ((ok ws)
      (mt (timeoutWanted!)
        ((err e) (err e))
        ((ok timeoutS)
          (mt (jobsWanted!)
            ((err e) (err e))
            ((ok jobs)
              (mt (plan! verb ws)
                ((err e) (err e))
                ((ok plan)
                  (let [(frozen (frozenCountFor! verb ws))]
                    (mt (poolLoop! host verb ws timeoutS (max 1 jobs) (Pool :pending (enumerate (pairFirst plan)) :running (list) :done (list)))
                      ((err e) (err e))
                      ((ok done) (ok (report! verb "asl-host" (pairFirst plan) (pairSecond plan) done frozen)))))))))))))

fn ! changedPlan! base: String -> (Result (Pair (List String) (Pair (List String) Int64)) String)
  (mt (workspace!)
    ((err e) (err e))
    ((ok ws)
      (mt (impact/changedFromGit base)
        ((err e) (err (str "ERR_BASE_OR_DIFF: " e)))
        ((ok changed)
          (mt (tracked! ws (list "*.asl"))
            ((err e) (err (str "ERR_DISCOVER: " e)))
            ((ok allAsl)
              (mt (impact/selectFiles allAsl changed)
                ((err e) (err (str "ERR_SELECTION: " e)))
                ((ok selected)
                 (let [(kept (filter (fn [(p String)] -> Bool (not (runner/isFrozenPath! ws p))) selected))
                       (frozen (- (listLength selected) (listLength kept)))]
                   (ok (pair changed (pair kept frozen))))))))))))

fn ! changedReport! base: String changed: (List String) selected: (List String) done: (List Done) frozen: Int64 -> Int64
  (let [(ordered (listSortBy (fn [(d Done)] -> Int64 d.index) done))
        (passed (filter (fn [(d Done)] -> Bool (= d.code 0)) ordered))
        (failedRuns (filter (fn [(d Done)] -> Bool (!= d.code 0)) ordered))
        (printed (map (fn [(d Done)] -> Bool
                        (say! (str (if (= d.code 0) "(:pass :file \"" "(:fail :file \"")
                                     (esc d.path) "\" :exit " (stringFromInt64 d.code) " :ev \""
                                     (esc (truncateChars d.last 300)) "\")"))) ordered))]
    (do (say! (str "(:changed :base \"" (esc base) "\" :files " (stringFromInt64 (listLength changed))
                   " :selected " (stringFromInt64 (listLength selected)) " :passed " (stringFromInt64 (listLength passed))
                   " :failed " (stringFromInt64 (listLength failedRuns)) " :frozen " (stringFromInt64 frozen) ")"))
        (if (listEmpty? failedRuns) 0 1)))

fn ! changedDry! base: String changed: (List String) selected: (List String) frozen: Int64 -> Int64
  (let [(shown (map (fn [(path String)] -> Bool (say! (str "(:selected :file \"" (esc path) "\")"))) selected))]
    (do (say! (str "(:changed :base \"" (esc base) "\" :files " (stringFromInt64 (listLength changed)) " :selected " (stringFromInt64 (listLength selected)) " :passed 0 :failed 0 :frozen " (stringFromInt64 frozen) ")")) 0))

fn ! changedSweep! host: String base: String dryRun: Bool -> (Result Int64 String)
  (mt (changedPlan! base)
    ((err e) (err e))
    ((ok plan)
     (let [(changed (pairFirst plan))
           (selected (pairFirst (pairSecond plan)))
           (frozen (pairSecond (pairSecond plan)))]
      (if dryRun
        (ok (changedDry! base changed selected frozen))
        (mt (workspace!)
          ((err e) (err e))
          ((ok ws)
            (mt (timeoutWanted!)
              ((err e) (err (str "ERR_TIMEOUT: " e)))
              ((ok timeoutS)
                (mt (poolLoop! host "test" ws timeoutS 2 (Pool :pending (enumerate selected) :running (list) :done (list)))
                  ((err e) (err (str "ERR_RUNNER: " e)))
                  ((ok done) (ok (changedReport! base changed selected done frozen))))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(verb (optionOr (listHead args) ""))]
    (if (= verb "changed")
      (if (or (< (listLength args) 3) (> (listLength args) 4))
        (do (say! "(:changed :status :failed :error ERR_USAGE :message \"sweep changed HOST BASE [--dry-run]\")") (ok 2))
        (let [(dryRun (listContains? args "--dry-run"))]
          (if (and (> (listLength args) 3) (not dryRun))
            (do (say! "(:changed :status :failed :error ERR_USAGE :message \"sweep changed HOST BASE [--dry-run]\")") (ok 2))
            (mt (changedSweep! (optionOr (listGet args 1) "") (optionOr (listGet args 2) "main") dryRun)
              ((ok code) (ok code))
              ((err e) (do (eprintln (str "(:changed :status :failed :error ERR_SELECTION :message \"" (esc e) "\")")) (ok 2)))))))
      (if (or (!= (listLength args) 2) (not (or (= verb "test") (= verb "check"))))
      (do (say! "(:sweep :status :failed :error ERR_USAGE :message \"hostSweep.py test|check HOST\")") (ok 2))
      (mt (sweep! verb (optionOr (listGet args 1) ""))
        ((ok code) (ok code))
        ((err e) (do (eprintln (str "(:sweep :status :failed :error ERR_NOT_A_WORKSPACE :message \"" e "\")")) (ok 1)))))))
