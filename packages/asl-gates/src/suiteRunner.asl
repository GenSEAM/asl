(module asl-gates/suiteRunner
  :x [SuiteResult SnapRun Fault Job Done discover frozenCount isFrozenPath! selectDirectorySuites! getExcludedForm snapRun gainedPaths workerCount envInt! gate main makeSuiteResult esc trustForm gateCounts computeDigest normpath dirname relpath makeSnapshot! runJobs! runJobsBy! doneMs runOne! gitOut! gitRun! gitRoot! absPath slowSuiteTimeoutS suiteJob! makeTempDir! sweepStaleTemps! isFile! nonHermeticReason driverCorpus pyStrip pyLines isSuiteName isExcludedSegment helpers!]
  :i [(asl-gates/suiteTimes :a st)])

(schema SuiteResult
  (:f suite String)
  (:f cause String)
  (:f digest String)
  (:f failLine String)
  (:f asserts Int64)
  (:f refutes Int64)
  (:f declared Int64)
  (:f failed Int64))

fn makeSuiteResult suite: String cause: String digest: String failLine: String asserts: Int64 refutes: Int64 declared: Int64 failed: Int64 -> SuiteResult
  (SuiteResult :suite suite :cause cause :digest digest :failLine failLine :asserts asserts :refutes refutes :declared declared :failed failed)

(schema HostVerdict
  (:f cause String)
  (:f asserts Int64)
  (:f refutes Int64)
  (:f failLine String))

fn trustForm -> String
  "(:trust (:asl :evaluator \"asl/host/out/asl-host\" :status :strict :build \"asl/host/build.sh in the snapshot\" :enforces \"imports resolve, an unknown symbol fails the load, assert and refute take Bool only, runTests must return true, zero executed assertions is red\"))"

fn escLoop chars: (List String) acc: (List String) -> (List String)
  (if (listEmpty? chars)
    (listReverse acc)
    (let [(ch (optionOr (listHead chars) ""))
          (tail (optionOr (listTail chars) (list)))
          (code (charCode ch))]
      (if (and (>= code 32) (< code 127))
        (escLoop tail (cons ch acc))
        (escLoop tail (cons "?" acc)))))

fn esc text: String limit: Int64 -> String
  (let [(s1 (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\""))
        (s2 (stringReplace (stringReplace s1 "\r" "") "\n" "\\n"))
        (sanitized (stringJoin (escLoop (stringChars s2) (list)) ""))
        (len (stringLength sanitized))]
    (if (> len limit)
      (optionOr (stringSlice sanitized 0 limit) sanitized)
      sanitized))

fn normpath p: String -> String
  (let [(lead (cond
                ((and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) "//")
                ((stringStartsWith? p "/") "/")
                (else "")))
        (stack (fold (fn [(stk (List String)) (seg String)] -> (List String)
                       (cond
                         ((or (stringEmpty? seg) (= seg ".")) stk)
                         ((and (= seg "..") (not (listEmpty? stk)) (!= (optionOr (listHead stk) "") ".."))
                          (optionOr (listTail stk) (list)))
                         ((and (= seg "..") (not (stringEmpty? lead))) stk)
                         (else (cons seg stk))))
                     (list)
                     (stringSplit p "/")))
        (joined (str lead (stringJoin (listReverse stack) "/")))]
    (if (stringEmpty? joined) "." joined))

fn dirname p: String -> String
  (let [(parts (stringSplit p "/"))
        (n (listLength parts))]
    (if (<= n 1)
      ""
      (stringJoin (listTake parts (- n 1)) "/")))

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn commonLen a: (List String) b: (List String) n: Int64 -> Int64
  (mt (listHead a)
    ((none) n)
    ((some x)
     (mt (listHead b)
       ((none) n)
       ((some y) (if (= x y) (commonLen (optionOr (listTail a) (list)) (optionOr (listTail b) (list)) (+ n 1)) n)))))

fn relpath path: String start: String -> String
  (let [(a (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit (normpath path) "/")))
        (b (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit (normpath start) "/")))
        (common (commonLen a b 0))
        (ups (map (fn [(i Int64)] -> String "..") (range 0 (- (listLength b) common))))
        (parts (listAppend ups (listDrop a common)))]
    (if (listEmpty? parts) "." (stringJoin parts "/")))

fn isPyWhite b: Int64 -> Bool
  (or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32)))

fn stripFrom bs: Bytes i: Int64 j: Int64 -> (Pair Int64 Int64)
  (cond
    ((and (< i j) (isPyWhite (bytesGet bs i))) (stripFrom bs (+ i 1) j))
    ((and (< i j) (isPyWhite (bytesGet bs (- j 1)))) (stripFrom bs i (- j 1)))
    (else (pair i j)))

fn pyStrip s: String -> String
  (let [(bs (stringToBytes s))
        (r (stripFrom bs 0 (bytesLength bs)))]
    (optionOr (stringSlice s (pairFirst r) (pairSecond r)) ""))

fn isLineBreak b: Int64 -> Bool
  (or (= b 10) (= b 13) (= b 11) (= b 12) (= b 28) (= b 29) (= b 30))

fn linesLoop s: String bs: Bytes n: Int64 start: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (if (< start n) (cons (optionOr (stringSlice s start n) "") acc) acc)))
    ((isLineBreak (bytesGet bs i))
     (let [(line (optionOr (stringSlice s start i) ""))
           (next (if (and (= (bytesGet bs i) 13) (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 10)) (+ i 2) (+ i 1)))]
       (linesLoop s bs n next next (cons line acc))))
    (else (linesLoop s bs n start (+ i 1) acc)))

fn pyLines s: String -> (List String)
  (let [(bs (stringToBytes s))]
    (linesLoop s bs (bytesLength bs) 0 0 (list)))

fn lastLineOf out: String -> String
  (optionOr (listLast (pyLines (pyStrip out))) "")

fn isSuiteName p: String -> Bool
  (cond
    ((stringEndsWith? p "Test.asl") true)
    ((stringEndsWith? p "_test.asl") true)
    ((stringEndsWith? p "Test.sh") true)
    ((stringEndsWith? p "_test.sh") true)
    (else
      (let [(filename (baseName p))]
        (and (stringStartsWith? filename "Task") (stringEndsWith? filename ".asl")))))

fn isExcludedSegment p: String -> Bool
  (listAny? (fn [(part String)] -> Bool
              (or (stringStartsWith? part ".") (= part "fixtures") (= part "node_modules") (= part "invalid")))
            (stringSplit p "/"))

fn getDriverCorpora -> (List (Pair String String))
  (list (pair "tests/acceptance/r1Host/" "tests/acceptance/r1Host/run.sh"))

fn driverCorpus p: String -> (Option String)
  (mt (listHead (filter (fn [(d (Pair String String))] -> Bool (stringStartsWith? p (pairFirst d))) (getDriverCorpora)))
    ((some d) (some (pairFirst d)))
    ((none) (none)))

fn getDrivers -> (List String)
  (list
    "tests/acceptance/r1Host/run.sh"
    "tests/acceptance/vtbotDataPlane/runGates.sh"
    "tests/acceptance/vtbotDataTooling/runGates.sh"
    "tests/acceptance/memory/cloneBaseline.sh"
    "tests/acceptance/memory/evidenceTracked.sh")

fn unverifiedReason -> String
  "legacy snake_case suite, hermeticity unverified, prints no (:gate ... :asserts n :failed m) line"

fn daemonReason -> String
  (str (unverifiedReason) "; its text names a daemon, socket or kill")

fn liveReason -> String
  (str (unverifiedReason) "; its text names a gateway, browser or model CLI")

fn acceptanceTests names: (List String) reason: String -> (List (Pair String String))
  (map (fn [(n String)] -> (Pair String String) (pair (str "tests/acceptance/" n "_test.sh") reason)) names)

fn getNonHermeticPairs -> (List (Pair String String))
  (listSortBy (fn [(p (Pair String String))] -> String (pairFirst p))
    (listAppend
      (list (pair "tests/acceptance/daemonLifecycleTest.sh" "runs asl_daemon_socket_test.sh and omni_daemon_test.sh, which start daemons")
            (pair "tests/acceptance/vtbotDataTooling/httpDownloadTest.asl" "downloads from https://download.gatedata.org (network)"))
      (listAppend
        (acceptanceTests (list "asl_daemon_socket" "mesh_daemon" "mesh_declarative_config" "omni_daemon" "unified_agent_plane") (daemonReason))
        (listAppend
          (acceptanceTests (list "browser_target_registry" "cockpit_gateway_endpoint" "cockpit_session_tile" "crawler_automation_nexus"
                                 "crawler_multibrowser_e2e" "crawler_rpc_session" "gateway_consolidation" "gateway_hardening"
                                 "gateway_multibrowser_routing" "gateway_roles_and_codex" "gateway_routing_and_framing" "gateway_search"
                                 "gateway_subscription_cli" "gateway_sync" "in_browser_agent" "in_browser_extension_bridge" "relay_cli"
                                 "search_research_nexus")
                           (liveReason))
          (acceptanceTests (list "attractor_benchmark" "attractor_experiment_ledger" "audit_mesh" "cockpit_bento_arena" "cockpit_focus_authority"
                                 "cockpit_observatory_tiles" "cockpit_tokens_and_theme" "coupling_audit" "d121_decision" "host_computer_use_ax"
                                 "mesh_ast_mutations" "mesh_memory_compaction" "mesh_preflush_and_mutations" "mesh_profiles_config"
                                 "mesh_sharded_blackboard" "mesh_stale_cleanup" "mesh_transaction_concurrency" "mesh_witness_sandbox"
                                 "preflush_gate" "profile_sync" "terminal_canvas_diff" "terminal_observatory_widgets"
                                 "toolbelt_consult" "tui_cockpit_e2e" "tui_workspace_router"
                                 "universal_consilium" "unsafe_runtime_acceleration")
                           (unverifiedReason))))))

fn getNonHermeticMap -> (Map String String)
  (mapFromPairs (getNonHermeticPairs))

fn nonHermeticReason p: String -> (Option String)
  (mapGet (getNonHermeticMap) p)

fn isSpaceByte b: Int64 -> Bool
  (or (= b 32) (and (>= b 9) (<= b 13)))

fn skipSpaces data: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (isSpaceByte (bytesGet data j)))
    (skipSpaces data n (+ j 1))
    j)

fn litAt data: Bytes n: Int64 j: Int64 lit: String -> Bool
  (let [(lb (stringToBytes lit))
        (m (bytesLength lb))]
    (and (>= j 0) (<= (+ j m) n) (listAll? (fn [(k Int64)] -> Bool (= (bytesGet data (+ j k)) (bytesGet lb k))) (range 0 m))))

fn relEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (not (or (= (bytesGet bs j) 34) (isSpaceByte (bytesGet bs j)) (= (bytesGet bs j) 59) (= (bytesGet bs j) 41))))
    (relEnd bs n (+ j 1))
    j)

fn sourcedRel line: String -> (Option String)
  (let [(bs (stringToBytes line))
        (n (bytesLength bs))
        (i0 (skipSpaces bs n 0))
        (afterCmd (cond ((litAt bs n i0 "source") (+ i0 6)) ((litAt bs n i0 ".") (+ i0 1)) (else -1)))
        (i1 (if (< afterCmd 0) -1 (skipSpaces bs n afterCmd)))
        (i2 (if (or (< i1 0) (= i1 afterCmd)) -1 (if (litAt bs n i1 "\"") (+ i1 1) i1)))
        (i3 (if (and (>= i2 0) (litAt bs n i2 "$(dirname")) (+ i2 9) -1))
        (i4 (if (< i3 0) -1 (skipSpaces bs n i3)))
        (i5 (if (or (< i4 0) (= i4 i3)) -1 (if (litAt bs n i4 "\"") (+ i4 1) i4)))
        (i6 (cond ((< i5 0) -1) ((litAt bs n i5 "$0") (+ i5 2)) ((litAt bs n i5 "${BASH_SOURCE[0]}") (+ i5 17)) (else -1)))
        (i7 (if (< i6 0) -1 (if (litAt bs n i6 "\"") (+ i6 1) i6)))
        (i8 (if (and (>= i7 0) (litAt bs n i7 ")")) (+ i7 1) -1))
        (i9 (if (< i8 0) -1 (if (litAt bs n i8 "/") (+ i8 1) i8)))
        (end (if (< i9 0) -1 (relEnd bs n i9)))]
    (if (or (< end 0) (<= end i9)) (none) (stringSlice line i9 end)))

fn scanHelpersInFile! root: String path: String -> (List String)
  (mt (fileReadString (str root "/" path))
    ((err _) (list))
    ((ok content)
     (let [(dir (dirname path))
           (candidates (filter (fn [(l String)] -> Bool (stringContains? l "$(dirname"))
                               (if (stringContains? content "$(dirname") (stringSplit content "\n") (list))))]
       (fold (fn [(acc (List String)) (line String)] -> (List String)
               (mt (sourcedRel line)
                 ((none) acc)
                 ((some rel)
                  (let [(target (normpath (if (stringEmpty? dir) rel (str dir "/" rel))))]
                    (if (!= target path) (cons target acc) acc)))))
             (list)
             candidates))))

fn helpers! root: String tracked: (List String) -> (List String)
  (let [(found (fold (fn [(acc (List String)) (p String)] -> (List String)
                       (if (stringEndsWith? p ".sh") (listAppend acc (scanHelpersInFile! root p)) acc))
                     (list)
                     tracked))
        (valid (filter (fn [(p String)] -> Bool (listContains? tracked p)) found))]
    (listSort (mapKeys (mapFromPairs (map (fn [(p String)] -> (Pair String Bool) (pair p true)) valid)))))

fn checkGuard data: Bytes n: Int64 j0: Int64 word: String -> Int64
  (let [(j (skipSpaces data n j0))
        (m (stringLength word))]
    (if (and (> j j0) (< (+ j m) n) (litAt data n j word) (or (isSpaceByte (bytesGet data (+ j m))) (= (bytesGet data (+ j m)) 41)))
      1
      0))

fn countDeclaredLoop data: Bytes n: Int64 i: Int64 inStr: Bool declared: Int64 guards: Int64 -> Int64
  (if (>= i n)
    (- declared guards)
    (let [(b (bytesGet data i))]
      (cond
        (inStr
          (cond
            ((= b 92) (countDeclaredLoop data n (+ i 2) true declared guards))
            ((= b 34) (countDeclaredLoop data n (+ i 1) false declared guards))
            (else (countDeclaredLoop data n (+ i 1) true declared guards))))
        ((= b 34) (countDeclaredLoop data n (+ i 1) true declared guards))
        ((and (= b 40) (< (+ i 7) n) (litAt data n (+ i 1) "assert") (isSpaceByte (bytesGet data (+ i 7))))
         (countDeclaredLoop data n (+ i 7) false (+ declared 1) (+ guards (checkGuard data n (+ i 7) "false"))))
        ((and (= b 40) (< (+ i 7) n) (litAt data n (+ i 1) "refute") (isSpaceByte (bytesGet data (+ i 7))))
         (countDeclaredLoop data n (+ i 7) false (+ declared 1) (+ guards (checkGuard data n (+ i 7) "true"))))
        (else (countDeclaredLoop data n (+ i 1) false declared guards)))))

fn declaredAsserts! path: String -> Int64
  (mt (fileReadBytes path)
    ((ok data) (countDeclaredLoop data (bytesLength data) 0 false 0 0))
    ((err _) 0))

(schema SpawnedProc
  (:f pid Int64)
  (:f stdin Int64)
  (:f stdout Int64)
  (:f stderr Int64))

(schema Job
  (:f input String)
  (:f argv (List String))
  (:f cwd (Option String))
  (:f env (Option (List String)))
  (:f timeoutMs Int64))

(schema Done
  (:f code Int64)
  (:f out String)
  (:f errText String)
  (:f merged String)
  (:f startNs Int64)
  (:f endNs Int64))

(schema Slot
  (:f index Int64)
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f out String)
  (:f errText String)
  (:f merged String)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f code (Option Int64))
  (:f deadlineNs Int64)
  (:f timedOut Bool)
  (:f startNs Int64))

(schema Guard
  (:f p0 Int64)
  (:f g0 Int64)
  (:f nextNs Int64))

(schema Pool
  (:f pending (List (Pair Int64 Job)))
  (:f running (List Slot))
  (:f done (List (Pair Int64 Done)))
  (:f guard (Option Guard))
  (:f registry (Option String)))

fn terminated -> String
  "ERR_TERMINATED: the session that started the runner went away"

fn slotWith s: Slot out: String errText: String merged: String outOpen: Bool errOpen: Bool code: (Option Int64) timedOut: Bool -> Slot
  (with s :out out :errText errText :merged merged :outOpen outOpen :errOpen errOpen :code code :timedOut timedOut)

fn ! appendLine! path: String line: String -> (Result Unit String)
  (let [(old (mt (fileReadString path) ((ok s) (ok s)) ((err e) (if (stringStartsWith? e "notFound") (ok "") (err e)))))]
    (mt old
      ((err e) (err e))
      ((ok s) (fileWrite path (str s line "\n")))))

fn spawnError argv0: String e: String -> String
  (if (= e "notFound")
    (str "ERR_TOOL_ABSENT: " argv0 " not found")
    (str "spawn " argv0 ": " e))

fn ! writeAll! fd: Int64 text: String -> (Result Unit String)
  (if (stringEmpty? text)
    (ok ())
    (mt (fdWrite fd text)
      ((err e) (err (str "write stdin: " e)))
      ((ok k) (if (<= k 0) (err "write stdin: no progress") (writeAll! fd (optionOr (stringSlice text k (stringLength text)) ""))))))

fn resultErrOr r: (Result Unit String) fallback: String -> String
  (mt r ((ok _) fallback) ((err e) e))

fn ! abandonSlot! s: Slot -> Bool
  (let [(killed (if (none? s.code) (do (procKill (- 0 s.pid) "SIGKILL") (procWaitPid s.pid false)) (ok (none))))
        (o (if s.outOpen (fdClose s.outFd) (ok ())))
        (e (if s.errOpen (fdClose s.errFd) (ok ())))]
    (and (ok? killed) (ok? o) (ok? e)))

fn ! abandonAll! slots: (List Slot) -> Bool
  (fold (fn [(acc Bool) (s Slot)] -> Bool (and (abandonSlot! s) acc)) true slots)

fn ! startSlot! idx: Int64 job: Job registry: (Option String) -> (Result Slot String)
  (let [(argv0 (optionOr (listHead job.argv) ""))
        (t0 (monotonicNs))]
    (mt (procSpawnv job.argv job.cwd job.env)
      ((err e) (err (spawnError argv0 e)))
      ((ok sp)
       (let [(wrote (if (stringEmpty? job.input) (ok ()) (writeAll! sp.stdin job.input)))
             (closedFd (fdClose sp.stdin))
             (closed (if (err? wrote) wrote closedFd))
             (reg (mt registry ((some path) (appendLine! path (stringFromInt64 sp.pid))) ((none) (ok ()))))
             (slot (Slot :index idx :pid sp.pid :outFd sp.stdout :errFd sp.stderr :out "" :errText "" :merged ""
                         :outOpen true :errOpen true :code (none)
                         :deadlineNs (if (> job.timeoutMs 0) (+ (monotonicNs) (* job.timeoutMs 1000000)) 0) :timedOut false :startNs t0))]
         (cond
           ((err? closed) (do (abandonSlot! slot) (err (str "close stdin of " argv0 ": " (resultErrOr closed "")))))
           ((err? reg) (do (abandonSlot! slot) (err (str "registry: " (resultErrOr reg "")))))
           (else (ok slot)))))))

fn ! readSide! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((err e) (err (str "read fd " (stringFromInt64 fd) ": " e)))
    ((ok chunk)
     (if (> (stringLength chunk) 0)
       (ok (some chunk))
       (mt (fdClose fd)
         ((err e) (err (str "close fd " (stringFromInt64 fd) ": " e)))
         ((ok _) (ok (none)))))))

fn fdReady? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn exitOf exited: (List (Pair Int64 Int64)) pid: Int64 -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (p (Pair Int64 Int64))] -> (Option Int64) (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) exited)

fn ! absorb! s: Slot ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) -> (Result Slot String)
  (let [(outR (if (and s.outOpen (fdReady? ready s.outFd)) (readSide! s.outFd) (ok (some ""))))
        (errR (if (and s.errOpen (fdReady? ready s.errFd)) (readSide! s.errFd) (ok (some ""))))
        (code (if (some? s.code) s.code (exitOf exited s.pid)))]
    (mt outR
      ((err e) (err e))
      ((ok oc)
       (mt errR
         ((err e) (err e))
         ((ok ec)
          (let [(o (optionOr oc ""))
                (x (optionOr ec ""))]
            (ok (slotWith s (str s.out o) (str s.errText x) (str s.merged o x)
                          (and s.outOpen (some? oc)) (and s.errOpen (some? ec)) code s.timedOut))))))))

fn finished? s: Slot -> Bool
  (and (some? s.code) (not s.outOpen) (not s.errOpen))

fn ! expire! s: Slot now: Int64 -> (Result Slot String)
  (if (or s.timedOut (= s.deadlineNs 0) (< now s.deadlineNs) (finished? s))
    (ok s)
    (mt (procKill (- 0 s.pid) "SIGKILL")
      ((err e) (if (= e "noProcess")
                 (ok (slotWith s s.out s.errText s.merged s.outOpen s.errOpen s.code true))
                 (err (str "kill process group " (stringFromInt64 s.pid) ": " e))))
      ((ok _) (ok (slotWith s s.out s.errText s.merged s.outOpen s.errOpen s.code true)))))

fn ! expireAll! slots: (List Slot) now: Int64 acc: (List Slot) -> (Result (List Slot) String)
  (mt (listHead slots)
    ((none) (ok (listReverse acc)))
    ((some s)
     (mt (expire! s now)
       ((err e) (err e))
       ((ok s2) (expireAll! (optionOr (listTail slots) (list)) now (cons s2 acc))))))

fn ! absorbAll! slots: (List Slot) ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) acc: (List Slot) -> (Result (List Slot) String)
  (mt (listHead slots)
    ((none) (ok (listReverse acc)))
    ((some s)
     (mt (absorb! s ready exited)
       ((err e) (err e))
       ((ok s2) (absorbAll! (optionOr (listTail slots) (list)) ready exited (cons s2 acc))))))

fn toDone now: Int64 s: Slot -> (Pair Int64 Done)
  (pair s.index (Done :code (if s.timedOut 124 (optionOr s.code -1)) :out s.out :errText s.errText :merged s.merged
                          :startNs s.startNs :endNs now))

fn doneMs d: Done -> Int64
  (/ (- d.endNs d.startNs) 1000000)

fn watchFds slots: (List Slot) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (s Slot)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if s.outOpen (list (pair s.outFd 1)) (list)) (if s.errOpen (list (pair s.errFd 1)) (list)))))
        (list)
        slots)

fn livePids slots: (List Slot) -> (List Int64)
  (map (fn [(s Slot)] -> Int64 s.pid) (filter (fn [(s Slot)] -> Bool (none? s.code)) slots))

fn pollTimeoutMs slots: (List Slot) guard: (Option Guard) now: Int64 -> Int64
  (let [(limits (listAppend (map (fn [(s Slot)] -> Int64 s.deadlineNs)
                                 (filter (fn [(s Slot)] -> Bool (and (> s.deadlineNs 0) (not s.timedOut))) slots))
                            (mt guard ((some g) (list g.nextNs)) ((none) (list)))))]
    (if (listEmpty? limits)
      -1
      (max 0 (+ 1 (/ (- (fold min (optionOr (listHead limits) 0) limits) now) 1000000)))))

fn ! fill! k: Int64 st: Pool -> (Result Pool String)
  (mt (listHead st.pending)
    ((none) (ok st))
    ((some job)
     (if (>= (listLength st.running) k)
       (ok st)
       (mt (startSlot! (pairFirst job) (pairSecond job) st.registry)
         ((err e) (err e))
         ((ok slot) (fill! k (with st :pending (optionOr (listTail st.pending) (list)) :running (listAppend st.running (list slot)))))))))

fn ! ppidOf! pid: Int64 -> Int64
  (mt (runOne! (Job :input "" :argv (list "/bin/ps" "-o" "ppid=" "-p" (stringFromInt64 pid)) :cwd (none) :env (none) :timeoutMs 5000))
    ((err _) 0)
    ((ok d) (optionOr (stringToInt64 (pyStrip d.out)) 0)))

fn ! guardCheck! g: Guard now: Int64 -> (Result Guard String)
  (if (< now g.nextNs)
    (ok g)
    (let [(p (ppidOf! (procSelf)))
          (gone (or (!= p g.p0) (and (> g.g0 1) (!= (ppidOf! g.p0) g.g0))))]
      (if gone (err (terminated)) (ok (with g :nextNs (+ now 5000000000))))))

fn ! newGuard! -> Guard
  (let [(p0 (ppidOf! (procSelf)))]
    (Guard :p0 p0 :g0 (ppidOf! p0) :nextNs (+ (monotonicNs) 5000000000)))

fn ! pollOnce! st: Pool -> (Result Pool String)
  (let [(running st.running)
        (now (monotonicNs))]
    (mt (procPoll (watchFds running) (livePids running) (pollTimeoutMs running st.guard now))
      ((err e) (err (str "procPoll: " e)))
      ((ok ready)
       (mt (absorbAll! running (pairFirst ready) (pairSecond ready) (list))
         ((err e) (err e))
         ((ok slots)
          (let [(now2 (monotonicNs))
                (guardRes (mt st.guard ((some g) (resultMap (guardCheck! g now2) (fn [(x Guard)] -> (Option Guard) (some x)))) ((none) (ok (none)))))]
            (mt guardRes
              ((err e) (do (abandonAll! slots) (err e)))
              ((ok guard)
               (mt (expireAll! slots now2 (list))
                 ((err e) (do (abandonAll! slots) (err e)))
                 ((ok slots2)
                  (ok (with st :running (filter (fn [(s Slot)] -> Bool (not (finished? s))) slots2) :done (listAppend st.done (map (fn [(s Slot)] -> (Pair Int64 Done) (toDone now2 s)) (filter finished? slots2))) :guard guard))))))))))))

fn ! poolLoop! k: Int64 st: Pool -> (Result (List Done) String)
  (mt (fill! k st)
    ((err e) (do (abandonAll! st.running) (err e)))
    ((ok st1)
     (if (listEmpty? st1.running)
       (ok (map (fn [(p (Pair Int64 Done))] -> Done (pairSecond p)) (listSortBy (fn [(p (Pair Int64 Done))] -> Int64 (pairFirst p)) st1.done)))
       (mt (pollOnce! st1)
         ((err e) (err e))
         ((ok st2) (poolLoop! k st2))))))

fn permutation? order: (List Int64) n: Int64 -> Bool
  (and (= (listLength order) n)
       (= (listSortBy (fn [(i Int64)] -> Int64 i) order) (map (fn [(p (Pair Int64 Int64))] -> Int64 (pairFirst p)) (enumerate order))))

fn ! runJobsBy! jobs: (List Job) order: (List Int64) k: Int64 guard: (Option Guard) registry: (Option String) -> (Result (List Done) String)
  (cond
    ((< k 1) (err "runJobs: k must be at least 1"))
    ((not (permutation? order (listLength jobs))) (err "runJobs: start order is not a permutation of the job indices"))
    (else
     (let [(rank (mapFromPairs (map (fn [(p (Pair Int64 Int64))] -> (Pair Int64 Int64) (pair (pairSecond p) (pairFirst p))) (enumerate order))))
           (pending (listSortBy (fn [(p (Pair Int64 Job))] -> Int64 (optionOr (mapGet rank (pairFirst p)) (pairFirst p))) (enumerate jobs)))]
       (poolLoop! k (Pool :pending pending :running (list) :done (list) :guard guard :registry registry)))))

fn ! runJobs! jobs: (List Job) k: Int64 guard: (Option Guard) registry: (Option String) -> (Result (List Done) String)
  (runJobsBy! jobs (map (fn [(p (Pair Int64 Job))] -> Int64 (pairFirst p)) (enumerate jobs)) k guard registry)

fn ! runOne! job: Job -> (Result Done String)
  (mt (runJobs! (list job) 1 (none) (none))
    ((err e) (err e))
    ((ok ds) (mt (listHead ds) ((some d) (ok d)) ((none) (err "runOne: no result")))))

fn gitJob root: String args: (List String) -> Job
  (Job :input "" :argv (cons "/usr/bin/git" args) :cwd (if (stringEmpty? root) (none) (some root)) :env (none) :timeoutMs 0)

fn ! gitRun! root: String args: (List String) -> (Result Done String)
  (runOne! (gitJob root args))

fn ! gitOut! root: String args: (List String) -> (Result String String)
  (mt (gitRun! root args)
    ((err e) (err e))
    ((ok d) (if (= d.code 0) (ok d.out) (err (str "git " (stringJoin args " ") ": " (pyStrip d.errText))))))

fn ! gitRoot! -> (Result String String)
  (resultMap (gitOut! "" (list "rev-parse" "--show-toplevel")) pyStrip)

fn isFile! path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn isExecutable! path: String -> Bool
  (mt (fileStat path) ((ok st) (and st.isFile (!= (& st.mode 64) 0))) ((err _) false))

fn absPath root: String p: String -> String
  (if (stringStartsWith? p "/") p (str root "/" p))

fn zSplit text: String -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit text "\x00"))

fn rstripSlash s: String -> String
  (if (stringEndsWith? s "/") (rstripSlash (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")) s)

fn matchesPrefix path: String prefixes: (List String) -> Bool
  (or (listEmpty? prefixes)
      (listAny? (fn [(p String)] -> Bool (or (= path p) (stringStartsWith? path (str (rstripSlash p) "/")))) prefixes))

fn explicitlyNamed path: String prefixes: (List String) -> Bool
  (listAny? (fn [(p String)] -> Bool (= path p)) prefixes)

fn frozenLedgerPath root: String -> String
  (str root "/asl/grammar/frozen.asn")

fn frozenRowsOf text: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String))
        (if (not (stringContains? line "(:frozen"))
          acc
          (let [(parts (stringSplit line "\""))
                (path (optionOr (listGet parts 1) ""))
                (kind (if (stringContains? line ":kind package") "package" "suite"))]
            (if (stringEmpty? path) acc (listAppend acc (list (pair path kind)))))))
      (list)
      (stringSplit text "\n"))

fn ! loadFrozenRows! root: String -> (List (Pair String String))
  (mt (fileReadString (frozenLedgerPath root))
    ((err _) (list))
    ((ok text) (frozenRowsOf text)))

fn isFrozenAmong rows: (List (Pair String String)) path: String -> Bool
  (listAny? (fn [(r (Pair String String))] -> Bool
              (if (= (pairSecond r) "package")
                (or (= path (pairFirst r)) (stringStartsWith? path (str (rstripSlash (pairFirst r)) "/")))
                (= path (pairFirst r))))
            rows)

fn ! isFrozenPath! root: String path: String -> Bool
  (isFrozenAmong (loadFrozenRows! root) path)

fn ! pathUnderDirectory? path: String dir: String -> Bool
  (let [(clean (if (stringEndsWith? dir "/") (optionOr (stringSlice dir 0 (- (stringLength dir) 1)) dir) dir))]
    (stringStartsWith? path (str clean "/")))

fn ! frozenUnderDirectory? root: String path: String dirs: (List String) -> Bool
  (let [(rootReal (resultOr (realPath root) root))
        (pathReal (resultOr (realPath path) path))
        (prefix (str rootReal "/"))]
    (and (stringStartsWith? pathReal prefix)
         (and (listAny? (fn [(d String)] -> Bool (pathUnderDirectory? pathReal (resultOr (realPath d) d))) dirs)
              (isFrozenPath! root (optionOr (stringSlice pathReal (stringLength prefix) (stringLength pathReal)) "")))))

fn ! selectDirectorySuites! root: String paths: (List String) dirs: (List String) -> (Pair (List String) (List String))
  (let [(frozen (filter (fn [(p String)] -> Bool (frozenUnderDirectory? root p dirs)) paths))]
    (pair (filter (fn [(p String)] -> Bool (not (listContains? frozen p))) paths) frozen))

fn ! candidates root: String prefixes: (List String) -> (Result (List String) String)
  (mt (gitOut! root (list "ls-files" "-s" "-z"))
    ((err e) (err e))
    ((ok text)
     (let [(entries (map (fn [(l String)] -> (Pair String String)
                           (let [(tab (optionOr (stringIndexOf l "\t") (stringLength l)))]
                             (pair (optionOr (stringSlice l 0 tab) "") (optionOr (stringSlice l (+ tab 1) (stringLength l)) ""))))
                         (zSplit text)))
           (helperSet (mapFromPairs (map (fn [(p String)] -> (Pair String Bool) (pair p true)) (helpers! root (map pairSecond entries)))))
           (nh (getNonHermeticMap))
           (kept (filter (fn [(e (Pair String String))] -> Bool
                           (let [(path (pairSecond e))]
                             (and (not (stringStartsWith? (pairFirst e) "120000"))
                                  (isSuiteName path)
                                  (or (not (isExcludedSegment path))
                                      (explicitlyNamed path prefixes))
                                  (not (mapHas? nh path))
                                  (not (mapHas? helperSet path))
                                  (none? (driverCorpus path))
                                  (matchesPrefix path prefixes)
                                  (isFile! (str root "/" path)))))
                         entries))]
       (ok (listSort (map pairSecond kept))))))

fn ! discover root: String prefixes: (List String) -> (Result (List String) String)
  (mt (candidates root prefixes)
    ((err e) (err e))
    ((ok cs)
     (let [(rows (loadFrozenRows! root))]
       (ok (filter (fn [(p String)] -> Bool (or (explicitlyNamed p prefixes) (not (isFrozenAmong rows p)))) cs)))))

fn ! frozenCount root: String prefixes: (List String) -> (Result Int64 String)
  (mt (candidates root prefixes)
    ((err e) (err e))
    ((ok cs)
     (let [(rows (loadFrozenRows! root))]
       (ok (listLength (filter (fn [(p String)] -> Bool (and (not (explicitlyNamed p prefixes)) (isFrozenAmong rows p))) cs))))))

fn groupNonHermetic tracked: (List String) -> (List (Pair String (List String)))
  (fold (fn [(groups (List (Pair String (List String)))) (p (Pair String String))] -> (List (Pair String (List String)))
          (let [(path (pairFirst p))
                (reason (pairSecond p))]
            (cond
              ((not (listContains? tracked path)) groups)
              ((listAny? (fn [(g (Pair String (List String)))] -> Bool (= (pairFirst g) reason)) groups)
               (map (fn [(g (Pair String (List String)))] -> (Pair String (List String))
                      (if (= (pairFirst g) reason) (pair reason (listAppend (pairSecond g) (list path))) g))
                    groups))
              (else (listAppend groups (list (pair reason (list path))))))))
        (list)
        (getNonHermeticPairs))

fn ! getExcludedForm root: String -> (Result String String)
  (mt (gitOut! root (list "ls-files"))
    ((err e) (err e))
    ((ok text)
     (let [(trackedList (pyLines text))
           (drivers (filter (fn [(d String)] -> Bool (listContains? trackedList d)) (getDrivers)))
           (corpora (map (fn [(d (Pair String String))] -> (Pair (Pair String String) Int64)
                           (pair d (listLength (filter (fn [(p String)] -> Bool (and (stringStartsWith? p (pairFirst d)) (isSuiteName p) (not (isExcludedSegment p)))) trackedList))))
                         (listSortBy (fn [(d (Pair String String))] -> String (pairFirst d)) (getDriverCorpora))))
           (helperList (filter isSuiteName (helpers! root trackedList)))
           (groups (groupNonHermetic trackedList))
           (n (fn [(i Int64)] -> String (stringFromInt64 i)))]
       (ok (str "(:excluded (:class drivers :n " (n (listLength drivers)) " :paths \"" (esc (stringJoin drivers " ") 400) "\")"
                " (:class driverCorpus :n " (n (fold (fn [(a Int64) (c (Pair (Pair String String) Int64))] -> Int64 (+ a (pairSecond c))) 0 corpora))
                (stringJoin (map (fn [(c (Pair (Pair String String) Int64))] -> String
                                   (str " (:dir \"" (esc (pairFirst (pairFirst c)) 400) "\" :driver \"" (esc (pairSecond (pairFirst c)) 400) "\" :n " (n (pairSecond c)) ")"))
                                 corpora) "")
                ") (:class helpers :n " (n (listLength helperList)) " :paths \"" (esc (stringJoin helperList " ") 400) "\")"
                " (:class nonHermetic :n " (n (fold (fn [(a Int64) (g (Pair String (List String)))] -> Int64 (+ a (listLength (pairSecond g)))) 0 groups))
                (stringJoin (map (fn [(g (Pair String (List String)))] -> String
                                   (str " (:reason \"" (esc (pairFirst g) 400) "\" :n " (n (listLength (pairSecond g))) " :paths \"" (esc (stringJoin (pairSecond g) " ") 4000) "\")"))
                                 groups) "")
                ")) " (trustForm))))))

fn allIn s: String alphabet: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? (fn [(c String)] -> Bool (stringContains? alphabet c)) (stringChars s)))

fn allDigits s: String -> Bool
  (allIn s "0123456789")

fn isWordByte b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95))

fn digitsEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (>= (bytesGet bs j) 48) (<= (bytesGet bs j) 57)) (digitsEnd bs n (+ j 1)) j)

fn numberAfter line: String bs: Bytes n: Int64 key: String from: Int64 -> (Option (Pair Int64 Int64))
  (mt (stringIndexOf (optionOr (stringSlice line from n) "") key)
    ((none) (none))
    ((some rel)
     (let [(at (+ from rel))
           (j0 (+ at (stringLength key)))
           (j1 (skipSpaces bs n j0))
           (j2 (digitsEnd bs n j1))]
       (if (and (> j1 j0) (> j2 j1) (or (>= j2 n) (not (isWordByte (bytesGet bs j2)))))
         (some (pair (optionOr (stringToInt64 (optionOr (stringSlice line j1 j2) "")) 0) j2))
         (numberAfter line bs n key (+ at 1))))))

fn parseShellGateLine line: String -> (Option (Pair Int64 Int64))
  (let [(bs (stringToBytes line))
        (n (bytesLength bs))
        (i (skipSpaces bs n 0))]
    (if (not (and (litAt bs n i "(:gate") (or (>= (+ i 6) n) (not (isWordByte (bytesGet bs (+ i 6)))))))
      (none)
      (mt (numberAfter line bs n ":asserts" (+ i 6))
        ((none) (none))
        ((some a)
         (mt (numberAfter line bs n ":failed" (pairSecond a))
           ((none) (none))
           ((some f) (some (pair (pairFirst a) (pairFirst f)))))))))

fn computeDigest cause: String failLine: String -> String
  (if (= cause "OK")
    ""
    (optionOr (stringSlice (bytesSha256 (stringToBytes (str cause "\n" failLine))) 0 16) ""))

fn gateCounts cause: String declared: Int64 asserts: Int64 refutes: Int64 failedCount: Int64 -> (Pair Int64 Int64)
  (cond
    ((= cause "OK") (pair (+ asserts refutes) 0))
    ((= cause "ERR_DECLARED_GAP") (pair declared (- declared (+ asserts refutes))))
    (else
      (let [(failed (max 1 failedCount))]
        (pair (max (+ asserts refutes) failed) failed))))

fn stripSnap out: String snap: String real: String -> String
  (stringReplace (stringReplace out (str real "/") "") (str snap "/") "")

fn afterSuitePrefix line: String suite: String -> (Option String)
  (cond
    ((stringStartsWith? line (str suite ": ")) (stringSlice line (+ (stringLength suite) 2) (stringLength line)))
    ((stringStartsWith? line (str "./" suite ": ")) (stringSlice line (+ (stringLength suite) 4) (stringLength line)))
    (else (none)))

fn parseHostOkLine line: String suite: String -> (Option (Pair Int64 Int64))
  (mt (afterSuitePrefix line suite)
    ((none) (none))
    ((some rest)
     (let [(lit " assertion(s) executed")
           (idx (optionOr (stringIndexOf rest lit) -1))
           (head (optionOr (stringSlice rest 0 (max 0 idx)) ""))]
       (if (or (< idx 0) (not (allDigits head)))
         (none)
         (let [(after (optionOr (stringSlice rest (+ idx (stringLength lit)) (stringLength rest)) ""))
               (rlit " refutation(s) executed")
               (ridx (optionOr (stringIndexOf after rlit) -1))
               (rhead (if (and (stringStartsWith? after ", ") (>= ridx 2)) (optionOr (stringSlice after 2 ridx) "") ""))]
           (some (pair (optionOr (stringToInt64 head) 0)
                       (if (allDigits rhead) (optionOr (stringToInt64 rhead) 0) 0))))))))

fn parseHostFailLine line: String suite: String -> (Option (Pair String Int64))
  (if (not (stringStartsWith? line "FAIL "))
    (none)
    (mt (afterSuitePrefix (optionOr (stringSlice line 5 (stringLength line)) "") suite)
      ((none) (none))
      ((some rest)
       (let [(parts (stringSplit rest " (after "))
             (n (listLength parts))
             (last (optionOr (listLast parts) ""))
             (count (if (stringEndsWith? last " asserts)") (optionOr (stringSlice last 0 (- (stringLength last) 9)) "") ""))]
         (if (or (< n 2) (not (allDigits count)))
           (none)
           (some (pair (stringJoin (listTake parts (- n 1)) " (after ") (optionOr (stringToInt64 count) 0))))))))

fn codeCharsEnd s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_" (optionOr (stringSlice s i (+ i 1)) " ")))
    (codeCharsEnd s (+ i 1))
    i)

fn parseHostDiag line: String -> (Option (List String))
  (let [(sp (optionOr (stringIndexOf line " ") -1))
        (tok (optionOr (stringSlice line 0 (max 0 sp)) ""))]
    (if (or (< sp 1) (not (stringEndsWith? tok ":")))
      (none)
      (let [(segs (stringSplit (optionOr (stringSlice tok 0 (- (stringLength tok) 1)) "") ":"))
            (n (listLength segs))
            (path (stringJoin (listTake segs (- n 2)) ":"))
            (after (optionOr (stringSlice line (+ sp 1) (stringLength line)) ""))
            (codeEnd (codeCharsEnd after 4))]
        (if (or (< n 3)
                (stringEmpty? path)
                (not (allDigits (optionOr (listGet segs (- n 2)) "")))
                (not (allDigits (optionOr (listGet segs (- n 1)) "")))
                (not (stringStartsWith? after "ERR_"))
                (<= codeEnd 4))
          (none)
          (some (list path (optionOr (stringSlice after 0 codeEnd) "") (optionOr (stringSlice after codeEnd (stringLength after)) "")))))))

fn firstDiagOf diags: (List (List String)) cls: String -> (Option String)
  (mt (listHead (filter (fn [(d (List String))] -> Bool (or (stringEmpty? cls) (= (optionOr (listGet d 1) "") cls))) diags))
    ((none) (none))
    ((some d) (some (str (optionOr (listGet d 0) "") ": " (optionOr (listGet d 1) "") (optionOr (listGet d 2) "")))))

fn hostLoadVerdict before: (List String) asserts: Int64 failLine: String -> HostVerdict
  (let [(diags (fold (fn [(acc (List (List String))) (l String)] -> (List (List String))
                       (mt (parseHostDiag l) ((none) acc) ((some d) (listAppend acc (list d)))))
                     (list)
                     before))
        (imp (firstDiagOf diags "ERR_UNRESOLVED_IMPORT"))
        (unk (firstDiagOf diags "ERR_UNKNOWN_SYMBOL"))
        (any (firstDiagOf diags ""))]
    (cond
      ((some? imp) (HostVerdict :cause "ERR_UNRESOLVED_IMPORT" :asserts asserts :refutes 0 :failLine (optionOr imp "")))
      ((some? unk) (HostVerdict :cause "ERR_UNKNOWN_SYMBOL" :asserts asserts :refutes 0 :failLine (optionOr unk "")))
      ((some? any) (HostVerdict :cause "ERR_LOAD" :asserts asserts :refutes 0 :failLine (optionOr any "")))
      (else (HostVerdict :cause "ERR_LOAD" :asserts asserts :refutes 0 :failLine failLine))))

fn hostVerdict code: Int64 out: String suite: String -> HostVerdict
  (let [(lines (pyLines out))
        (lastOk (fold (fn [(acc (Option (Pair Int64 Int64))) (l String)] -> (Option (Pair Int64 Int64))
                        (mt (parseHostOkLine l suite) ((none) acc) ((some p) (some p))))
                      (none)
                      lines))
        (lastFail (fold (fn [(acc (Option (Pair Int64 String))) (e (Pair Int64 String))] -> (Option (Pair Int64 String))
                          (mt (parseHostFailLine (pairSecond e) suite) ((none) acc) ((some _) (some e))))
                        (none)
                        (enumerate lines)))]
    (cond
      ((= code 124) (HostVerdict :cause "ERR_TIMEOUT" :asserts 0 :refutes 0 :failLine "timeout"))
      ((and (= code 0) (some? lastOk) (none? lastFail))
       (mt lastOk
         ((some p) (HostVerdict :cause "OK" :asserts (pairFirst p) :refutes (pairSecond p) :failLine ""))
         ((none) (HostVerdict :cause "ERR_VACUOUS_SUITE" :asserts 0 :refutes 0 :failLine ""))))
      ((= code 0) (HostVerdict :cause "ERR_VACUOUS_SUITE" :asserts 0 :refutes 0 :failLine "exit 0 without an assertion(s) executed line"))
      ((none? lastFail) (HostVerdict :cause "ERR_RUNTIME" :asserts 0 :refutes 0 :failLine (str "exit " (stringFromInt64 code) ": " (lastLineOf out))))
      (else
       (mt lastFail
         ((none) (HostVerdict :cause "ERR_RUNTIME" :asserts 0 :refutes 0 :failLine ""))
         ((some e)
          (let [(at (pairFirst e))
                (failLine (pyStrip (pairSecond e)))
                (parsed (optionOr (parseHostFailLine (pairSecond e) suite) (pair "" 0)))
                (reason (pairFirst parsed))
                (asserts (pairSecond parsed))
                (loadIdx (optionOr (stringIndexOf reason " load error") -1))]
            (cond
              ((and (> loadIdx 0) (allDigits (optionOr (stringSlice reason 0 loadIdx) ""))) (hostLoadVerdict (listTake lines at) asserts failLine))
              ((stringStartsWith? reason "ERR_TEST_FAILED: zero assertions executed") (HostVerdict :cause "ERR_VACUOUS_SUITE" :asserts asserts :refutes 0 :failLine failLine))
              ((or (stringStartsWith? reason "ERR_ASSERT:") (stringStartsWith? reason "ERR_REFUTE:") (stringStartsWith? reason "ERR_TEST_FAILED:"))
               (HostVerdict :cause "ASSERTION_FAILURE" :asserts asserts :refutes 0 :failLine failLine))
              (else (HostVerdict :cause "ERR_RUNTIME" :asserts asserts :refutes 0 :failLine failLine)))))))))

fn red suite: String cause: String failLine: String asserts: Int64 failed: Int64 -> SuiteResult
  (SuiteResult :suite suite :cause cause :digest (computeDigest cause failLine) :failLine failLine :asserts asserts :refutes 0 :declared 0 :failed failed)

fn shellResult suite: String code: Int64 out: String -> SuiteResult
  (let [(gates (fold (fn [(acc (List (Pair String (Pair Int64 Int64)))) (l String)] -> (List (Pair String (Pair Int64 Int64)))
                       (mt (parseShellGateLine l) ((none) acc) ((some p) (cons (pair (pyStrip l) p) acc))))
                     (list)
                     (pyLines out)))
        (last (listHead gates))
        (gateText (mt last ((some g) (pairFirst g)) ((none) "")))
        (asserts (mt last ((some g) (pairFirst (pairSecond g))) ((none) 0)))
        (failed (mt last ((some g) (pairSecond (pairSecond g))) ((none) 0)))]
    (cond
      ((= code 124) (red suite "ERR_TIMEOUT" "timeout" asserts failed))
      ((!= code 0) (red suite "SHELL_FAILED" (str "exit " (stringFromInt64 code) ": " (if (stringEmpty? gateText) (lastLineOf out) gateText)) asserts failed))
      ((none? last) (red suite "ERR_VACUOUS_SUITE" "exit 0 with no (:gate ... :asserts n :failed m) line" 0 0))
      ((> failed 0) (red suite "ASSERTION_FAILURE" (str "exit 0 with failed assertions: " gateText) asserts failed))
      ((= asserts 0) (red suite "ERR_VACUOUS_SUITE" (str "exit 0 with :asserts 0: " gateText) 0 failed))
      (else (SuiteResult :suite suite :cause "OK" :digest "" :failLine "" :asserts asserts :refutes 0 :declared 0 :failed failed))))

fn aslResult! snap: String suite: String code: Int64 out: String -> SuiteResult
  (let [(v (hostVerdict code out suite))
        (cause v.cause)
        (asserts v.asserts)
        (refutes v.refutes)
        (declared (declaredAsserts! (str snap "/" suite)))
        (gap (- declared (+ asserts refutes)))]
    (cond
      ((and (= cause "OK") (> gap 0))
       (let [(failLine (str "gap=" (stringFromInt64 gap)))]
         (SuiteResult :suite suite :cause "ERR_DECLARED_GAP" :digest (computeDigest "ERR_DECLARED_GAP" failLine) :failLine failLine
                      :asserts asserts :refutes refutes :declared declared :failed 1)))
      ((= cause "OK") (SuiteResult :suite suite :cause "OK" :digest "" :failLine "" :asserts asserts :refutes refutes :declared declared :failed 0))
      (else (SuiteResult :suite suite :cause cause :digest (computeDigest cause v.failLine) :failLine v.failLine
                         :asserts asserts :refutes refutes :declared declared :failed 1))))

(schema SnapRun
  (:f results (List SuiteResult))
  (:f gained (List String))
  (:f wallMs Int64)
  (:f times (List st/SuiteTime)))

(schema Fault
  (:f kind String)
  (:f msg String))

(schema Lock
  (:f fd Int64)
  (:f registry String))

fn envInt! name: String fallback: Int64 -> (Result Int64 String)
  (mt (envGet name)
    ((none) (ok fallback))
    ((some v)
     (mt (stringToInt64 (pyStrip v))
       ((some n) (ok n))
       ((none) (err (str name " is not an integer: " v))))))

fn slowSuiteTimeoutS suite: String -> (Option Int64)
  (cond
    ((= suite "asl/packages/asl-parser/tests/liftLowerIdentityTest.asl") (some 900))
    ((or (= suite "tests/conformance/bootstrap/stage1BuildTest.asl") (= suite "tests/conformance/bootstrap/stage1LlvmTest.asl")) (some 1200))
    ((= suite "tests/conformance/cli/buildNativeAsl1Test.asl") (some 2400))
    ((= suite "tests/conformance/bootstrap/stage2FixpointTest.asl") (some 3600))
    ((= suite "tests/conformance/bootstrap/ddcFixpointTest.asl") (some 1800))
    ((= suite "tests/conformance/bootstrap/seedFixpointTest.asl") (some 1800))
    ((= suite "asl/packages/asl-cli/tests/binAslColdTest.asl") (some 900))
    ((= suite "asl/packages/asl-checker/tests/importSweepTest.asl") (some 600))
    ((= suite "asl/packages/asl-gates/tests/suiteRunnerTest.asl") (some 1200))
    ((= suite "asl/packages/asl-gates/tests/runnerParityTest.asl") (some 900))
    ((or (= suite "asl/packages/asl-gates/tests/gateRunnerTest.asl") (= suite "asl/packages/asl-ir/tests/lowerCorpusTest.asl")) (some 600))
    ((= suite "tests/acceptance/r1AgentLoop/coreParityTest.sh") (some 1200))
    (else (none)))

fn ! firstLineInt! argv: (List String) -> Int64
  (mt (runOne! (Job :input "" :argv argv :cwd (none) :env (none) :timeoutMs 5000))
    ((err _) 0)
    ((ok d) (if (= d.code 0) (optionOr (stringToInt64 (pyStrip d.out)) 0) 0)))

fn ! physicalCores! -> Int64
  (let [(n (firstLineInt! (list "/usr/sbin/sysctl" "-n" "hw.physicalcpu")))]
    (if (> n 0)
      n
      (let [(online (firstLineInt! (list "getconf" "_NPROCESSORS_ONLN")))]
        (max 1 (/ (if (> online 0) online 2) 2)))))

fn positiveCount v: (Option String) -> (Option Int64)
  (mt v
    ((none) (none))
    ((some s) (if (allDigits s) (let [(n (optionOr (stringToInt64 s) 0))] (if (> n 0) (some n) (none))) (none))))

fn ! workerCount jobs: (Option String) -> Int64
  (let [(cap (physicalCores!))
        (asked (fold (fn [(acc (Option Int64)) (v (Option String))] -> (Option Int64) (if (some? acc) acc (positiveCount v)))
                     (none)
                     (list (if (some? jobs) jobs (envGet "ASL_JOBS")) (envGet "JOBS"))))]
    (mt asked
      ((some n) (min n cap))
      ((none) (max 1 (/ cap 2)))))

fn envKey kv: String -> String
  (optionOr (listHead (stringSplit kv "=")) "")

fn sessionEnvKeys -> (List String)
  (list "ASL_ROOT" "ASL_LAUNCHED" "ASL_UNIT" "ASL_AGENT" "ASL_LEASE_PID" "ASL_CLI_ROOT" "ASL_PRELUDE")

fn withEnv! extra: (List String) -> (List String)
  (let [(keys (listAppend (sessionEnvKeys) (map envKey extra)))]
    (listAppend (filter (fn [(kv String)] -> Bool (not (listContains? keys (envKey kv)))) (envList)) extra))

fn nestedTimes snap: String -> String
  (str "ASL_GATE_TIMES=" snap "/.git/aslGateTimes.asn")

fn suiteJob! snap: String suite: String baseS: Int64 -> Job
  (let [(path (str snap "/" suite))]
    (if (stringEndsWith? suite ".sh")
      (Job :input "" :argv (if (isExecutable! path) (list path) (list "/bin/sh" path)) :cwd (some snap)
           :env (some (withEnv! (list (str "ASL_TRANSCRIPT_DIR=" snap "/.noTranscripts") "ASL_IN_RUNNER=1" (nestedTimes snap)))) :timeoutMs (* (optionOr (slowSuiteTimeoutS suite) baseS) 1000))
      (Job :input "" :argv (list (str snap "/asl/host/out/asl-host") "test" suite) :cwd (some snap)
           :env (some (withEnv! (list "ASL_IN_RUNNER=1" (nestedTimes snap)))) :timeoutMs (* (optionOr (slowSuiteTimeoutS suite) baseS) 1000))))

fn toResult! snap: String real: String suite: String d: Done -> SuiteResult
  (let [(out (stripSnap d.merged snap real))]
    (if (stringEndsWith? suite ".sh")
      (shellResult suite d.code out)
      (aslResult! snap suite d.code out)))

fn tail1500 s: String -> String
  (let [(n (stringLength s))]
    (if (> n 1500) (optionOr (stringSlice s (- n 1500) n) s) s))

fn ! buildHost! snap: String real: String baseS: Int64 guard: (Option Guard) registry: (Option String) -> (Result Unit String)
  (mt (envInt! "ASL_HOST_BUILD_TIMEOUT_S" 1800)
    ((err e) (err e))
    ((ok hostBuildS)
     (mt (runJobs! (list (Job :input "" :argv (list "/bin/bash" "asl/host/build.sh") :cwd (some snap) :env (none) :timeoutMs (* (max baseS hostBuildS) 1000))) 1 guard registry)
       ((err e) (err e))
       ((ok ds)
        (let [(d (optionOr (listHead ds) (Done :code -1 :out "" :errText "" :merged "" :startNs 0 :endNs 0)))]
          (if (and (= d.code 0) (isExecutable! (str snap "/asl/host/out/asl-host")))
            (ok ())
            (err (str "host build failed: exit " (stringFromInt64 d.code) ": " (tail1500 (pyStrip (stripSnap d.merged snap real)))))))))))

fn unquote s: String -> String
  (let [(a (if (stringStartsWith? s "\"") (unquote (optionOr (stringSlice s 1 (stringLength s)) "")) s))]
    (if (stringEndsWith? a "\"") (unquote (optionOr (stringSlice a 0 (- (stringLength a) 1)) "")) a))

fn ! getDirt! snap: String -> (Result (Map String String) String)
  (mt (gitOut! snap (list "status" "--porcelain" "-uall"))
    ((err e) (err e))
    ((ok text)
     (ok (fold (fn [(acc (Map String String)) (l String)] -> (Map String String)
                 (if (stringEmpty? l)
                   acc
                   (let [(rel (unquote (optionOr (listLast (stringSplit (optionOr (stringSlice l 3 (stringLength l)) "") " -> ")) "")))
                         (full (str snap "/" rel))
                         (hash (if (isFile! full) (mt (fileReadBytes full) ((ok b) (bytesSha256 b)) ((err _) "")) ""))]
                     (mapSet acc l hash))))
               (mapEmpty)
               (pyLines text)))))

fn checkGained before: (Map String String) after: (Map String String) -> (List String)
  (listSort (filter (fn [(k String)] -> Bool (or (not (mapHas? before k)) (!= (optionOr (mapGet after k) "") (optionOr (mapGet before k) ""))))
                    (mapKeys after)))

fn tempBase! -> String
  (let [(t (optionOr (envGet "TMPDIR") "/tmp"))]
    (if (stringEmpty? t) "/tmp" (rstripSlash t)))

fn ! makeTempDir! prefix: String -> (Result String String)
  (let [(path (str (tempBase!) "/" prefix "." (stringFromInt64 (procSelf)) "." (stringFromInt64 (mod (nowNs) 1000000000000))))]
    (if (fileExists? path)
      (makeTempDir! prefix)
      (resultMap (dirCreate path) (fn [(u Unit)] -> String path))))

fn ! pidAlive! pid: Int64 -> Bool
  (mt (procAlive? pid)
    ((ok alive) alive)
    ((err _) true))

fn stalePid name: String -> (Option Int64)
  (let [(prefix (cond ((stringStartsWith? name "aslRunnerSnap.") "aslRunnerSnap.") ((stringStartsWith? name "aslKnownRedCapture.") "aslKnownRedCapture.") (else "")))
        (rest (optionOr (stringSlice name (stringLength prefix) (stringLength name)) ""))
        (dot (optionOr (stringIndexOf rest ".") -1))
        (digits (optionOr (stringSlice rest 0 (max 0 dot)) ""))]
    (if (and (not (stringEmpty? prefix)) (> dot 0) (allDigits digits)) (stringToInt64 digits) (none)))

fn ! sweepStaleTemps! -> Unit
  (let [(base (tempBase!))]
    (mt (dirList base)
      ((err _) ())
      ((ok names)
       (fold (fn [(u Unit) (name String)] -> Unit
               (mt (stalePid name)
                 ((none) u)
                 ((some pid) (if (or (= pid (procSelf)) (pidAlive! pid)) u (do (pathRemove (str base "/" name)) u)))))
             ()
             names))))

fn ! gitPathOf! root: String name: String -> (Result String String)
  (resultMap (gitOut! root (list "rev-parse" "--git-path" name)) (fn [(p String)] -> String (absPath root (pyStrip p))))

fn ! copyIfPresent! src: String dst: String -> (Result Unit String)
  (if (not (isFile! src))
    (ok ())
    (mt (fileReadBytes src)
      ((err e) (err e))
      ((ok data) (mt (dirCreate (dirname dst)) ((err e) (err e)) ((ok _) (fileWrite dst data))))))

fn ! steps! fs: (List (fn [] -> (Result Unit String))) -> (Result Unit String)
  (mt (listHead fs)
    ((none) (ok ()))
    ((some f) (mt (f) ((err e) (err e)) ((ok _) (steps! (optionOr (listTail fs) (list)))))))

fn ! gitDo! root: String args: (List String) -> (Result Unit String)
  (resultMap (gitOut! root args) (fn [(s String)] -> Unit ()))

fn ! indexFromRoot! root: String snap: String gitDir: String -> (Result Unit String)
  (mt (gitOut! root (list "ls-files" "-s" "-z"))
    ((err e) (err e))
    ((ok info)
     (mt (runOne! (Job :input info :argv (list "/usr/bin/git" (str "--git-dir=" gitDir) "update-index" "-z" "--index-info") :cwd (some snap) :env (none) :timeoutMs 0))
       ((err e) (err e))
       ((ok d) (if (= d.code 0) (ok ()) (err (str "git update-index --index-info: " (pyStrip d.errText))))))))

fn ! fillSnapshot! root: String snap: String -> (Result Unit String)
  (let [(gitDir (str snap "/.git"))]
    (steps! (list (fn [] -> (Result Unit String) (gitDo! root (list "clone" "-q" "--shared" "--no-checkout" root snap)))
                  (fn [] -> (Result Unit String) (resultMap (gitRun! snap (list "remote" "remove" "origin")) (fn [(d Done)] -> Unit ())))
                  (fn [] -> (Result Unit String) (indexFromRoot! root snap gitDir))
                  (fn [] -> (Result Unit String) (mt (gitPathOf! root "info/exclude") ((err e) (err e)) ((ok p) (copyIfPresent! p (str gitDir "/info/exclude")))))
                  (fn [] -> (Result Unit String) (gitDo! root (list (str "--git-dir=" gitDir) (str "--work-tree=" root) "add" "-A")))
                  (fn [] -> (Result Unit String)
                    (mt (gitOut! snap (list "write-tree"))
                      ((err e) (err e))
                      ((ok tree) (gitDo! snap (list "read-tree" (pyStrip tree))))))
                  (fn [] -> (Result Unit String) (gitDo! snap (list "checkout-index" "-a" "-f")))
                  (fn [] -> (Result Unit String) (gitDo! snap (list "reset" "-q")))
                  (fn [] -> (Result Unit String) (dirCreate (str snap "/tmp"))))))

fn ! makeSnapshot! root: String -> (Result String String)
  (do
    (sweepStaleTemps!)
    (mt (makeTempDir! "aslRunnerSnap")
      ((err e) (err e))
      ((ok snap)
       (mt (fillSnapshot! root snap)
         ((err e) (do (pathRemove snap) (err e)))
         ((ok _) (ok snap))))))

fn ! lockPaths! root: String -> (Result (Pair String String) String)
  (mt (gitOut! root (list "rev-parse" "--git-dir"))
    ((err e) (err e))
    ((ok d)
     (let [(gitDir (absPath root (pyStrip d)))]
       (ok (pair (str gitDir "/aslRunner.lock") (str gitDir "/aslRunner.pgids"))))))

fn ! reapOrphans! registry: String -> (Result Unit String)
  (mt (fileReadString registry)
    ((err _) (ok ()))
    ((ok text)
     (do
       (fold (fn [(u Unit) (tok String)] -> Unit
               (if (not (allDigits tok))
                 u
                 (let [(pgid (optionOr (stringToInt64 tok) 0))]
                   (mt (runOne! (Job :input "" :argv (list "/bin/ps" "-o" "command=" "-p" tok) :cwd (none) :env (none) :timeoutMs 5000))
                     ((err _) u)
                     ((ok d) (if (and (> pgid 1) (stringContains? d.out "aslRunnerSnap.")) (do (procKill (- 0 pgid) "SIGKILL") u) u))))))
             ()
             (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit (stringReplace (stringReplace text "\n" " ") "\t" " ") " ")))
       (fileWrite registry ""))))

fn ! tryLock! path: String untilNs: Int64 -> (Result Int64 Fault)
  (mt (fileLock path true)
    ((ok fd) (ok fd))
    ((err e)
     (cond
       ((!= e "busy") (err (Fault :kind "runner" :msg (str "lock " path ": " e))))
       ((< (monotonicNs) untilNs) (do (sleepMs 500) (tryLock! path untilNs)))
       (else
        (let [(text (mt (fileReadString path) ((ok s) s) ((err _) "")))
              (holder (pyStrip (optionOr (stringSlice text 0 (min 32 (stringLength text))) "")))]
          (err (Fault :kind "busy" :msg (str "a runner already holds " path ", holder pid " (if (stringEmpty? holder) "unknown" holder)))))))))

fn ! acquireLock! root: String waitS: Int64 -> (Result Lock Fault)
  (mt (lockPaths! root)
    ((err e) (err (Fault :kind "runner" :msg e)))
    ((ok paths)
     (mt (tryLock! (pairFirst paths) (+ (monotonicNs) (* waitS 1000000000)))
       ((err f) (err f))
       ((ok fd)
        (let [(reaped (reapOrphans! (pairSecond paths)))
              (mine (if (ok? reaped) (fileWrite (pairFirst paths) (stringFromInt64 (procSelf))) reaped))]
          (mt mine
            ((err e) (do (fdClose fd) (err (Fault :kind "runner" :msg e))))
            ((ok _) (ok (Lock :fd fd :registry (pairSecond paths))))))))))

fn ! releaseLock! l: Lock -> (Result Unit String)
  (let [(cleared (fileWrite l.registry ""))
        (closed (fdClose l.fd))]
    (if (ok? cleared) closed cleared))

fn fault e: String -> Fault
  (Fault :kind (if (= e (terminated)) "terminated" "runner") :msg e)

fn suiteTimesOf suites: (List String) dones: (List Done) -> (List st/SuiteTime)
  (map (fn [(p (Pair String Done))] -> st/SuiteTime (st/SuiteTime :suite (pairFirst p) :ms (doneMs (pairSecond p)))) (zip suites dones))

fn ! suitePhase! snap: String real: String baseS: Int64 suites: (List String) workers: Int64 guard: Guard registry: String -> (Result SnapRun String)
  (mt (st/timesPath!)
    ((err e) (err e))
    ((ok timesPath)
     (mt (st/readTimes! timesPath)
       ((err e) (err e))
       ((ok known)
        (mt (if (listAny? (fn [(s String)] -> Bool (stringEndsWith? s ".asl")) suites) (buildHost! snap real baseS (some guard) (some registry)) (ok ()))
          ((err e) (err e))
          ((ok _)
           (mt (getDirt! snap)
             ((err e) (err e))
             ((ok before)
              (let [(t0 (monotonicNs))]
                (mt (runJobsBy! (map (fn [(s String)] -> Job (suiteJob! snap s baseS)) suites) (st/startOrder suites known) workers (some guard) (some registry))
                  ((err e) (err e))
                  ((ok dones)
                   (let [(wallMs (/ (- (monotonicNs) t0) 1000000))
                         (times (suiteTimesOf suites dones))]
                     (mt (st/writeTimes! timesPath times)
                       ((err e) (err e))
                       ((ok _)
                        (mt (getDirt! snap)
                          ((err e) (err e))
                          ((ok after)
                           (ok (SnapRun :results (map (fn [(p (Pair String Done))] -> SuiteResult (toResult! snap real (pairFirst p) (pairSecond p))) (zip suites dones))
                                        :gained (checkGained before after) :wallMs wallMs :times times))))))))))))))))))

fn ! snapRun root: String suites: (List String) workers: Int64 lockWaitS: Int64 -> (Result SnapRun Fault)
  (mt (envInt! "ASL_SUITE_TIMEOUT_S" 300)
    ((err e) (err (fault e)))
    ((ok baseS)
     (mt (acquireLock! root lockWaitS)
       ((err f) (err f))
       ((ok lock)
        (let [(guard (newGuard!))
              (res (mt (makeSnapshot! root)
                     ((err e) (err e))
                     ((ok snap)
                      (let [(real (resultOr (realPath snap) snap))
                            (ran (suitePhase! snap real baseS suites workers guard lock.registry))
                            (removed (pathRemove snap))]
                        (mt ran
                          ((err e) (err e))
                          ((ok r) (mt removed ((ok _) (ok r)) ((err e) (err (str "snapshot cleanup: " e))))))))))
              (released (releaseLock! lock))]
          (mt res
            ((err e) (err (fault e)))
            ((ok r) (mt released ((ok _) (ok r)) ((err e) (err (fault (str "lock release: " e))))))))))))

fn gainedPaths gained: (List String) -> String
  (stringJoin (map (fn [(g String)] -> String (optionOr (stringSlice g 3 (stringLength g)) "")) (listTake gained 10)) ", ")

fn runnerFailure suite: String cause: String why: String -> SuiteResult
  (SuiteResult :suite suite :cause cause :digest "" :failLine why :asserts 0 :refutes 0 :declared 0 :failed 0)

fn notSuiteWhy suite: String -> String
  (mt (nonHermeticReason suite)
    ((some r) r)
    ((none)
     (mt (driverCorpus suite)
       ((some d) (str "driver corpus of " (optionOr (mapGet (mapFromPairs (getDriverCorpora)) d) "")))
       ((none) "not a tracked suite under the discovery rule (a tracked, non-helper *Test.asl, *_test.asl, *Test.sh, *_test.sh or Task*.asl)"))))

fn ! gateResult! root: String suite: String -> (Result SuiteResult Fault)
  (mt (discover root (list suite))
    ((err e) (ok (runnerFailure suite "ERR_RUNNER" e)))
    ((ok found)
     (if (not (listContains? found suite))
       (ok (runnerFailure suite "ERR_NOT_A_SUITE" (notSuiteWhy suite)))
       (mt (envInt! "ASL_GATE_LOCK_WAIT_S" 900)
         ((err e) (ok (runnerFailure suite "ERR_RUNNER" e)))
         ((ok waitS)
          (mt (snapRun root (list suite) 1 waitS)
            ((err f) (if (= f.kind "terminated") (err f) (ok (runnerFailure suite (if (= f.kind "busy") "ERR_BUSY" "ERR_RUNNER") f.msg))))
            ((ok run)
             (mt (listHead run.results)
               ((none) (ok (runnerFailure suite "ERR_RUNNER" "no result")))
               ((some r)
                (ok (if (listEmpty? run.gained)
                      r
                      (SuiteResult :suite r.suite :cause "ERR_TREE_DIRTIED" :digest r.digest :failLine (str "suite wrote " (gainedPaths run.gained))
                                   :asserts r.asserts :refutes r.refutes :declared r.declared :failed r.failed))))))))))))

fn ! gateSuitePath! root: String arg: String -> String
  (if (not (stringStartsWith? arg "/"))
    (normpath arg)
    (let [(dir (dirname (normpath arg)))
          (realDir (resultOr (realPath (if (stringEmpty? dir) "/" dir)) dir))
          (realRoot (resultOr (realPath root) root))]
      (normpath (relpath (str realDir "/" (baseName arg)) realRoot))))

fn ! gate root: String arg: String -> Int64
  (let [(suite (gateSuitePath! root arg))]
    (mt (gateResult! root suite)
      ((err _) 143)
      ((ok r)
       (let [(counts (gateCounts r.cause r.declared r.asserts r.refutes r.failed))]
         (do
           (println (str "(:gateCause :suite \"" (esc suite 400) "\" :cause " r.cause " :digest \"" r.digest "\" :ev \"" (esc r.failLine 400) "\""
                         (if (stringEndsWith? suite ".asl") (str " " (trustForm)) "") ")"))
           (println (str "(:gate :name \"" (esc suite 400) "\" :asserts " (stringFromInt64 (pairFirst counts)) " :failed " (stringFromInt64 (pairSecond counts)) ")"))
           (if (= r.cause "OK") 0 1))))))

fn printLines! lines: (List String) -> Unit
  (fold (fn [(u Unit) (l String)] -> Unit (println l)) () lines)

fn ! main args: (List String) -> (Result Int64 String)
  (mt (gitRoot!)
    ((err e) (do (println (str "(:runner :status :failed :err ERR_RUNNER :ev \"" (esc e 400) "\")")) (ok 2)))
    ((ok root)
     (cond
       ((= args (list "discover"))
        (mt (discover root (list))
          ((err e) (do (println (str "(:runner :status :failed :err ERR_RUNNER :ev \"" (esc e 400) "\")")) (ok 2)))
          ((ok suites)
           (mt (getExcludedForm root)
             ((err e) (do (println (str "(:runner :status :failed :err ERR_RUNNER :ev \"" (esc e 400) "\")")) (ok 2)))
             ((ok excluded)
              (let [(frozen (resultOr (frozenCount root (list)) 0))]
                (do (printLines! suites) (println excluded) (println (str "(:frozen " (stringFromInt64 frozen) ")")) (ok 0))))))))
       ((and (= (listLength args) 2) (= (optionOr (listHead args) "") "gate") (not (stringStartsWith? (optionOr (listGet args 1) "") "-")))
        (ok (gate root (optionOr (listGet args 1) ""))))
       (else
        (do
          (println "(:runner :status :failed :err ERR_USAGE :ev \"usage: suiteRunner discover | gate SUITE; asl-gates/runnerMain is the runner\")")
          (ok 64))))))
