(module asl-engine/server
  :x [ServerState serve! engineLog!]
  :i [(asl-engine/engine :a eng)
      (asl-engine/watchdog :a wd)
      (asl-engine/guard :a grd)
      (asl-engine/lease :a lse)
      (asl-engine/supervisor :a sp)
      (asl-engine/wire :a w)
      (asl-engine/build :a bld)
      (asl-engine/transport :a tp)
      (asl-json/json :a j)])

(schema ServerState
  (:f rt eng/EngineRuntime)
  (:f listener Int64)
  (:f pending (List AsyncJob))
  (:f bindMtimeNs Int64)
  (:f idleMs Int64)
  (:f updatePeriodMs Int64)
  (:f updateIdleMs Int64)
  (:f lastActiveMs Int64)
  (:f lastWorkMs Int64)
  (:f nextUpdateMs Int64)
  (:f rejected String))

(schema AsyncJob
  (:f kind String)
  (:f clientFd Int64)
  (:f logFile String)
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f out String)
  (:f errText String)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f code (Option Int64))
  (:f deadlineMs Int64)
  (:f response String))

fn nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn wallSec! -> Int64
  (/ (nowNs) 1000000000)

fn withRt st: ServerState rt: eng/EngineRuntime -> ServerState
  (with st :rt rt)

fn touched st: ServerState rt: eng/EngineRuntime atMs: Int64 work: Bool -> ServerState
  (with st :rt rt :lastActiveMs atMs :lastWorkMs (if work atMs st.lastWorkMs))

fn rescheduled st: ServerState atMs: Int64 -> ServerState
  (with st :nextUpdateMs atMs)

fn withRejected st: ServerState version: String -> ServerState
  (with st :rejected version)

fn ! engineLog! cfg: eng/EngineConfig line: String -> Bool
  (ok? (fileAppend cfg.logFile (str "[Engine] " line "\n")))

fn mtimeOf! path: String -> Int64
  (mt (fileStat path) ((ok s) s.mtimeNs) ((err _) -1))

fn ! isDir? path: String -> Bool
  (mt (fileStat path) ((ok s) s.isDir) ((err _) false))

fn lifetimeBreak! st: ServerState -> String
  (let [(cfg st.rt.config)
        (sockMtime (mtimeOf! cfg.socketPath))]
    (cond
      ((< sockMtime 0) "socket unlinked")
      ((!= sockMtime st.bindMtimeNs) "socket replaced by another bind")
      ((not (isDir? cfg.rootDir)) "root directory missing")
      (else "")))

fn ! removeIfOurs! st: ServerState -> Bool
  (let [(cfg st.rt.config)
        (sockGone (if (= (mtimeOf! cfg.socketPath) st.bindMtimeNs) (ok? (pathRemove cfg.socketPath)) true))
        (pidText (stringTrim (resultOr (fileReadString cfg.pidFile) "")))
        (pidGone (if (= pidText (stringFromInt64 (procSelf))) (ok? (pathRemove cfg.pidFile)) true))]
    (and sockGone pidGone))

fn ! cancelJobs! jobs: (List AsyncJob) -> Bool
  (mt (listHead jobs)
    ((none) true)
    ((some j)
      (let [(killed (if (and (= j.kind "forms") (none? j.code))
                      (do (procKill (- 0 j.pid) "SIGKILL") (procWaitPid j.pid false))
                      (ok (none))))
            (outClosed (if (and (= j.kind "forms") j.outOpen) (fdClose j.outFd) (ok ())))
            (errClosed (if (and (= j.kind "forms") j.errOpen) (fdClose j.errFd) (ok ())))
            (clientClosed (fdClose j.clientFd))
            (okThis (and (ok? killed) (and (ok? outClosed) (and (ok? errClosed) (ok? clientClosed)))))
            (_ (if okThis true (fileAppend j.logFile "[Engine] async job cleanup failed\n")))
            (okRest (cancelJobs! (optionOr (listTail jobs) (list))))]
        (and okThis okRest))))

fn ! shutdown! st: ServerState reason: String -> String
  (let [(cfg st.rt.config)
        (jobsClosed (cancelJobs! st.pending))
        (_ (if jobsClosed true (engineLog! cfg "async job cleanup failed during shutdown")))
        (_ (if (sp/killAllSessions! st.rt.supervisor) true (engineLog! cfg "session kill or reap failed during shutdown")))
        (_ (if (ok? (fdClose st.listener)) true (engineLog! cfg "listener close failed during shutdown")))
        (_ (if (removeIfOurs! st) true (engineLog! cfg "socket or pid file removal failed during shutdown")))
        (_ (if (ok? (lse/releaseLease! st.rt.lease)) true (engineLog! cfg "lease release failed during shutdown")))
        (_ (engineLog! cfg (str "exit: " reason)))]
    reason)

fn ! reaped st: ServerState -> ServerState
  (let [(rt st.rt)]
    (withRt st (eng/withSupervisor rt (sp/reapSessions! rt.supervisor (wallSec!)))))

fn ! drainThenExit! st: ServerState reason: String -> String
  (let [(r (reaped st))]
    (if (> (sp/runningCount r.rt.supervisor) 0)
      (do (sleepMs 250) (drainThenExit! r reason))
      (shutdown! r reason)))

fn stateFile cfg: eng/EngineConfig -> String
  (str cfg.pidFile ".finished")

fn setEnvRow rows: (List String) key: String val: String -> (List String)
  (cons (str key "=" val) (filter (fn [(r String)] -> Bool (not (stringStartsWith? r (str key "=")))) rows))

fn ! selfUpdate! st: ServerState disk: String -> String
  (let [(rt st.rt)
        (cfg rt.config)
        (b rt.build)
        (saved (fileWrite (stateFile cfg) (sp/finishedLines rt.supervisor)))
        (_ (engineLog! cfg (str "self-update " b.version " -> " disk)))
        (_ (fdClose st.listener))
        (_ (removeIfOurs! st))
        (_ (lse/releaseLease! rt.lease))
        (env0 (envList))
        (env1 (setEnvRow env0 "ASL_ENGINE_UPDATES" (stringFromInt64 (+ b.updates 1))))
        (env2 (setEnvRow env1 "ASL_ENGINE_UPDATED_FROM" b.version))
        (env3 (setEnvRow env2 "ASL_ENGINE_ENTRY" b.entry))
        (env4 (setEnvRow env3 "ASL_HOST" b.host))
        (argv (list b.host "run" b.entry "run" "--root" cfg.rootDir "--scope" cfg.scope))]
    (if (err? saved)
      (do (engineLog! cfg "self-update could not save finished sessions") (str "self-update failed: state file " (stateFile cfg)))
      (mt (procExecv argv (some env4))
        ((ok _) "self-update exec returned")
        ((err e) (do (engineLog! cfg (str "self-update exec failed: " e)) (str "self-update failed: " e))))))

fn leftOf! deadlineMs: Int64 -> Int64
  (max 0 (- deadlineMs (nowMs!)))

fn ! pump! outFd: Int64 errFd: Int64 outOpen: Bool errOpen: Bool out: String errText: String deadlineMs: Int64 -> (Pair Bool (Pair String String))
  (if (not (or outOpen errOpen))
    (pair true (pair out errText))
    (if (= (leftOf! deadlineMs) 0)
      (pair false (pair out errText))
      (mt (fdPoll (listAppend (if outOpen (list (pair outFd 1)) (list)) (if errOpen (list (pair errFd 1)) (list))) (min 1000 (leftOf! deadlineMs)))
        ((err _) (pair false (pair out errText)))
        ((ok _)
          (let [(o (if outOpen (fdRead outFd 65536) (ok "")))
                (e (if errOpen (fdRead errFd 65536) (ok "")))
                (oChunk (resultOr o ""))
                (eChunk (resultOr e ""))
                (oOpen (and outOpen (ok? o) (not (stringEmpty? oChunk))))
                (eOpen (and errOpen (ok? e) (not (stringEmpty? eChunk))))
                (_ (if (and outOpen (not oOpen)) (fdClose outFd) (ok ())))
                (_ (if (and errOpen (not eOpen)) (fdClose errFd) (ok ())))]
            (pump! outFd errFd oOpen eOpen (stringConcat out oChunk) (stringConcat errText eChunk) deadlineMs))))))

fn formsAnswer code: Int64 out: String errText: String -> String
  (j/jsonEmit (j/jobj (list (pair "exit" (j/jint code)) (pair "stdout" (j/jstr out)) (pair "stderr" (j/jstr errText)))))

fn jsonText v: j/Json -> String
  (mt v ((j/jstr s) s) (_ (j/jsonEmit v)))

fn formsArgs v: (Option j/Json) -> (Result (List String) String)
  (mt (optionOr v (j/jnull))
    ((j/jarr xs) (ok (map jsonText xs)))
    (_ (err "forms must be a JSON array")))

fn envRows v: (Option j/Json) -> (List String)
  (mt (optionOr v (j/jnull))
    ((j/jobj kvs) (map (fn [(p (Pair String j/Json))] -> String (str (pairFirst p) "=" (jsonText (pairSecond p)))) kvs))
    (_ (list)))

fn ! sourcesCheck! b: bld/EngineBuild -> (Pair Bool String)
  (mt (procSpawnv (list b.host "check" b.entry) (some b.toolRoot) (none))
    ((err e) (pair false (str "check spawn failed: " (tp/socketErrorText! e))))
    ((ok child)
      (let [(_ (fdClose child.stdin))
            (pumped (pump! child.stdout child.stderr true true "" "" (+ (nowMs!) 300000)))
            (_ (if (pairFirst pumped) (ok ()) (procKill (- 0 child.pid) "SIGKILL")))
            (code (optionOr (resultOr (procWaitPid child.pid false) (none)) 1))
            (outs (pairSecond pumped))]
        (pair (and (pairFirst pumped) (= code 0)) (stringTrim (str (pairFirst outs) (pairSecond outs)))))))

fn workRequest? line: String -> Bool
  (not (or (stringStartsWith? line "(:engine") (stringStartsWith? line "(:ping")))

fn stopAnswer? response: String -> Bool
  (stringStartsWith? response "(:receipt :status :ok :engine :stopping")

fn withPending st: ServerState pending: (List AsyncJob) -> ServerState
  (with st :pending pending)

fn ! startFormsJob! build: bld/EngineBuild request: String clientFd: Int64 logFile: String -> (Pair (Option AsyncJob) String)
  (mt (j/jsonParse request)
    ((err e) (pair (none) (formsAnswer 2 "" (str "ERR_FORMS_REQUEST: " e))))
    ((ok req)
      (let [(forms (formsArgs (j/jsonGet req "forms")))
            (root (mt (optionOr (j/jsonGet req "root") (j/jnull)) ((j/jstr s) s) (_ "")))
            (aslBin (str build.toolRoot "/bin/asl"))]
        (cond
          ((err? forms) (pair (none) (formsAnswer 2 "" (str "ERR_FORMS_REQUEST: " (mt forms ((err e) e) ((ok _) ""))))))
          ((or (not (stringStartsWith? root "/")) (not (isDir? root)))
            (pair (none) (formsAnswer 2 "" (str "ERR_FORMS_ROOT: " root))))
          ((or (stringEmpty? build.toolRoot) (not (ok? (fileStat aslBin))))
            (pair (none) (formsAnswer 2 "" (str "ERR_FORMS_ABSENT: no " aslBin))))
          (else
            (let [(env0 (envRows (j/jsonGet req "env")))
                  (env1 (setEnvRow env0 "ASL_ROOT" root))
                  (env2 (setEnvRow env1 "ROOT_DIR" build.toolRoot))
                  (env3 (setEnvRow env2 "SCRIPT_DIR" (str build.toolRoot "/bin")))]
              (mt (procSpawnv (cons aslBin (resultOr forms (list))) (some root) (some env3))
                ((err e) (pair (none) (formsAnswer 2 "" (str "ERR_FORMS_SPAWN: " (tp/socketErrorText! e)))))
                ((ok child)
                  (do (fdClose child.stdin)
                      (pair (some (AsyncJob :kind "forms" :clientFd clientFd :logFile logFile :pid child.pid :outFd child.stdout :errFd child.stderr :out "" :errText "" :outOpen true :errOpen true :code (none) :deadlineMs (+ (nowMs!) 3600000) :response "")) ""))))))))))

fn delayMsOf text: String -> (Option Int64)
  (mt (stringToFloat64 text)
    ((none) (none))
    ((some sec)
      (if (or (< sec 0.0) (> sec 3600.0))
        (none)
        (float64ToInt64 (* sec 1000.0)))))

fn delayedRequest line: String -> (Option (Pair Int64 String))
  (let [(parsed (w/parseSimpleSExpr line))
        (op (pairFirst parsed))
        (args (pairSecond parsed))]
    (cond
      ((= op "ping")
        (mt (w/getArg args "sleep")
          ((none) (none))
          ((some text) (mt (delayMsOf text) ((none) (none)) ((some ms) (some (pair ms "")))))))
      ((or (= op "sleep") (= op "wait"))
        (let [(secStr (w/getArgOr args "sec" (w/getArgOr args "seconds" "3")))]
          (mt (delayMsOf secStr) ((none) (none)) ((some ms) (some (pair ms (w/formatSleepReceipt secStr)))))))
      (else (none))))

fn ! handleForms! st: ServerState line: String clientFd: Int64 -> (Pair ServerState String)
  (let [(started (startFormsJob! st.rt.build line clientFd st.rt.config.logFile))
        (startMs (nowMs!))]
    (mt (pairFirst started)
      ((some job) (pair (withPending (touched st st.rt startMs true) (listAppend st.pending (list job))) ""))
      ((none)
        (let [(response (pairSecond started))
              (_ (tp/writeAllFd! clientFd (str response "\n")))
              (_ (fdClose clientFd))]
          (pair st response)))))

fn ! handlePing! st: ServerState line: String clientFd: Int64 -> (Pair ServerState String)
  (mt (delayedRequest line)
    ((some delayed)
      (let [(startMs (nowMs!))
            (delayMs (pairFirst delayed))
            (reply (if (stringEmpty? (pairSecond delayed)) (eng/dispatchRequest! st.rt "(:ping)" (wallSec!)) (pair st.rt (pairSecond delayed))))
            (job (AsyncJob :kind (if (workRequest? line) "wait" "sleep") :clientFd clientFd :logFile st.rt.config.logFile :pid -1 :outFd -1 :errFd -1 :out "" :errText "" :outOpen false :errOpen false :code (none) :deadlineMs (+ startMs delayMs) :response (pairSecond reply)))
            (next (touched st (pairFirst reply) startMs (workRequest? line)))]
        (pair (withPending next (listAppend st.pending (list job))) "")))
    ((none)
      (let [(startMs (nowMs!))
            (result (eng/dispatchRequest! st.rt line (wallSec!)))
            (response (pairSecond result))
            (_ (tp/writeAllFd! clientFd (str response "\n")))
            (_ (fdClose clientFd))
            (endMs (nowMs!))
            (next (touched (touched st (pairFirst result) startMs (workRequest? line)) (pairFirst result) endMs (workRequest? line)))]
        (pair next response))))

fn jobWith j: AsyncJob out: String errText: String outOpen: Bool errOpen: Bool code: (Option Int64) -> AsyncJob
  (with j :out out :errText errText :outOpen outOpen :errOpen errOpen :code code)

fn jobsWatchFds jobs: (List AsyncJob) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (j AsyncJob)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if (and (= j.kind "forms") j.outOpen) (list (pair j.outFd 1)) (list))
                                      (if (and (= j.kind "forms") j.errOpen) (list (pair j.errFd 1)) (list)))))
        (list) jobs)

fn jobsPids jobs: (List AsyncJob) -> (List Int64)
  (map (fn [(j AsyncJob)] -> Int64 j.pid)
       (filter (fn [(j AsyncJob)] -> Bool (and (= j.kind "forms") (none? j.code))) jobs))

fn readyFd? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn exitedCode exited: (List (Pair Int64 Int64)) pid: Int64 -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (p (Pair Int64 Int64))] -> (Option Int64)
          (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) exited)

fn ! readJobSide! fd: Int64 open: Bool ready: Bool old: String -> (Pair String Bool)
  (if (not (and open ready))
    (pair old open)
    (mt (fdRead fd 65536)
      ((err e) (let [(closed (fdClose fd))] (pair (str old " ERR_FORMS_READ: " e (if (ok? closed) "" " ERR_FORMS_CLOSE")) false)))
      ((ok chunk)
        (if (stringEmpty? chunk)
          (let [(closed (fdClose fd))] (pair (if (ok? closed) old (str old " ERR_FORMS_CLOSE")) false))
          (pair (str old chunk) true)))))

fn ! updateJob! j: AsyncJob ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) -> AsyncJob
  (let [(outR (readJobSide! j.outFd j.outOpen (readyFd? ready j.outFd) j.out))
        (errR (readJobSide! j.errFd j.errOpen (readyFd? ready j.errFd) j.errText))
        (code (if (some? j.code) j.code (exitedCode exited j.pid)))]
    (jobWith j (pairFirst outR) (pairFirst errR) (pairSecond outR) (pairSecond errR) code))

fn ! completeJob! cfg: eng/EngineConfig j: AsyncJob -> Bool
  (let [(answer (if (= j.kind "forms") (formsAnswer (optionOr j.code 1) j.out j.errText) j.response))
        (written (tp/writeAllFd! j.clientFd (str answer "\n")))
        (clientClosed (fdClose j.clientFd))
        (outClosed (if j.outOpen (fdClose j.outFd) (ok ())))
        (errClosed (if j.errOpen (fdClose j.errFd) (ok ())))
        (okAll (and (ok? written) (and (ok? clientClosed) (and (ok? outClosed) (ok? errClosed)))))]
    (if okAll true (engineLog! cfg "failed to deliver or close an asynchronous request")))

fn ! abortFormsJob! j: AsyncJob reason: String -> AsyncJob
  (let [(killed (if (some? j.code) (ok ()) (procKill (- 0 j.pid) "SIGKILL")))
        (waited (if (some? j.code) (ok j.code) (procWaitPid j.pid false)))
        (outClosed (if j.outOpen (fdClose j.outFd) (ok ())))
        (errClosed (if j.errOpen (fdClose j.errFd) (ok ())))
        (details (str reason
                      (if (err? killed) (str "\nERR_FORMS_KILL: " (resultOr killed "unknown")) "")
                      (if (err? waited) (str "\nERR_FORMS_WAIT: " (mt waited ((err e) e) ((ok _) ""))) "")
                      (if (err? outClosed) (str "\nERR_FORMS_CLOSE_STDOUT: " (resultOr outClosed "unknown")) "")
                      (if (err? errClosed) (str "\nERR_FORMS_CLOSE_STDERR: " (resultOr errClosed "unknown")) "")))]
    (jobWith j j.out (str j.errText details) false false (some 1)))

fn ! advanceJobs! cfg: eng/EngineConfig jobs: (List AsyncJob) ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) now: Int64 -> (Pair (List AsyncJob) Bool)
  (mt (listHead jobs)
    ((none) (pair (list) false))
    ((some h)
      (let [(updated (updateJob! h ready exited))
            (timedOut (and (= updated.kind "forms") (none? updated.code) (>= now updated.deadlineMs)))
            (overLimit (> (+ (stringLength updated.out) (stringLength updated.errText)) 4194304))
            (j (if timedOut (abortFormsJob! updated "ERR_FORMS_TIMEOUT: bin/asl ran past 3600 s")
                 (if (and overLimit (= updated.kind "forms")) (abortFormsJob! updated "ERR_FORMS_OUTPUT_LIMIT: output exceeded 4194304 bytes") updated)))
            (done (if (= j.kind "forms") (and (some? j.code) (not (or j.outOpen j.errOpen)))
                    (>= now j.deadlineMs)))
            (tail (advanceJobs! cfg (optionOr (listTail jobs) (list)) ready exited now))
            (_ (if done (completeJob! cfg j) true))
            (rest (if done (pairFirst tail) (cons j (pairFirst tail))))
            (didWork (or (and done (!= j.kind "sleep")) (pairSecond tail)))]
        (pair rest didWork))))

fn ! serveClient! st: ServerState clientFd: Int64 -> (Pair ServerState String)
  (let [(frame (tp/readFrame! clientFd "" (+ (monotonicNs) 10000000000) 8388608))]
    (mt frame
      ((err _) (do (fdClose clientFd) (pair st "")))
      ((ok raw)
        (let [(line (stringTrim raw))]
          (if (stringEmpty? line)
            (do (fdClose clientFd) (pair st ""))
            (if (>= (listLength st.pending) 32)
              (let [(_ (tp/writeAllFd! clientFd "(:receipt :status :error :message busy)\n"))
                    (_ (fdClose clientFd))]
                (pair st ""))
              (if (stringStartsWith? line "{")
                (handleForms! st line clientFd)
                (handlePing! st line clientFd))))))))

fn ! loop! st0: ServerState -> String
  (let [(st (reaped st0))
        (rt st.rt)
        (cfg rt.config)
        (now (nowMs!))
        (running (sp/runningCount rt.supervisor))
        (broken (lifetimeBreak! st))
        (rss (grd/checkRssGuard! cfg.softRssMb cfg.maxRssMb))]
    (cond
      ((not (stringEmpty? broken))
        (do (if (cancelJobs! st.pending) true (engineLog! cfg "async job cleanup failed after lifetime break"))
            (drainThenExit! (withPending st (list)) broken)))
      ((and (listEmpty? st.pending) (wd/isIdle now st.lastActiveMs 0 running st.idleMs))
        (shutdown! st "idle"))
      ((= rss.level ":critical")
        (do (engineLog! cfg rss.criticalMessage) (shutdown! st "rss ceiling")))
      ((and (> st.updatePeriodMs 0) (>= now st.nextUpdateMs))
        (let [(next (rescheduled st (+ now st.updatePeriodMs)))
              (b rt.build)
              (disk (if (stringEmpty? b.entry) b.version (bld/sourceVersion! b.entry)))]
          (if (and (!= disk b.version) (!= disk "absent") (= running 0)
                   (>= (- now st.lastWorkMs) st.updateIdleMs)
                   (listEmpty? st.pending)
                   (not (stringEmpty? b.host)) (!= disk st.rejected))
            (let [(checked (sourcesCheck! b))]
              (if (pairFirst checked)
                (selfUpdate! next disk)
                (do (engineLog! cfg (str "self-update to " disk " skipped, runner check failed: " (pairSecond checked)))
                    (accept! (withRejected next disk)))))
            (accept! next))))
      (else (accept! st))))

fn ! acceptReady! st: ServerState -> String
  (mt (sockAccept st.listener)
    ((err _) (loop! st))
    ((ok clientFd)
      (let [(served (serveClient! st clientFd))]
        (if (stopAnswer? (pairSecond served))
          (shutdown! (pairFirst served) "stop requested")
          (loop! (pairFirst served))))))

fn containsJobClient? jobs: (List AsyncJob) clientFd: Int64 -> Bool
  (listAny? (fn [(j AsyncJob)] -> Bool (= j.clientFd clientFd)) jobs)

fn completedWork? before: (List AsyncJob) after: (List AsyncJob) -> Bool
  (listAny? (fn [(j AsyncJob)] -> Bool
              (and (!= j.kind "sleep") (not (containsJobClient? after j.clientFd)))) before)

fn ! accept! st: ServerState -> String
  (mt (procPoll (listAppend (list (pair st.listener 1)) (jobsWatchFds st.pending)) (jobsPids st.pending) 250)
    ((err e) (shutdown! st (str "listener poll failed: " e)))
    ((ok polled)
      (let [(ready (pairFirst polled))
            (exited (pairSecond polled))
            (advanced (advanceJobs! st.rt.config st.pending ready exited (nowMs!)))
            (pending (pairFirst advanced))
            (base (withPending st pending))
            (now (nowMs!))
            (finished (< (listLength pending) (listLength st.pending)))
            (next (if finished (touched base base.rt now (completedWork? st.pending pending)) base))]
        (if (readyFd? ready st.listener)
          (acceptReady! next)
          (loop! next)))))

fn ! makeParents! path: String -> Bool
  (let [(parts (stringSplit path "/"))
        (dirs (listTake parts (- (listLength parts) 1)))]
    (fold (fn [(acc String) (seg String)] -> String
            (let [(next (if (= acc "") (if (stringEmpty? seg) "/" seg) (if (= acc "/") (str "/" seg) (str acc "/" seg))))]
              (do (if (or (stringEmpty? seg) (isDir? next)) (ok ()) (dirCreate next)) next)))
          ""
          dirs)
    true)

fn ! serve! rootDir: String scope: String build: bld/EngineBuild -> (Result String String)
  (let [(cfg0 (eng/resolveScope! rootDir scope))
        (_ (makeParents! cfg0.socketPath))
        (_ (makeParents! cfg0.pidFile))
        (_ (makeParents! cfg0.logFile))]
    (mt (eng/cmdStart! rootDir scope true false)
      ((err e) (err e))
      ((ok rt0)
        (let [(cfg rt0.config)
              (carried (sp/loadFinished (resultOr (fileReadString (stateFile cfg)) "")))
              (_ (pathRemove (stateFile cfg)))
              (rt (eng/withBuild (eng/withSupervisor rt0 carried) build))
              (_ (pathRemove cfg.socketPath))]
          (mt (unixListen cfg.socketPath)
            ((err e)
              (do (lse/releaseLease! rt.lease)
                  (pathRemove cfg.pidFile)
                  (err (str "ERR_LISTEN_FAILED: " (tp/socketErrorText! e) " at " cfg.socketPath))))
            ((ok listener)
              (let [(now (nowMs!))
                    (idleMs (bld/parseMs (optionOr (envGet "ASL_ENGINE_IDLE_SEC") "900") 900000))
                    (periodMs (bld/parseMs (optionOr (envGet "ASL_ENGINE_UPDATE_SEC") "30") 30000))
                    (updIdleDefault (min 10000 (bld/parseMs (optionOr (envGet "ASL_ENGINE_IDLE_SEC") "10") 10000)))
                    (updIdleMs (bld/parseMs (optionOr (envGet "ASL_ENGINE_UPDATE_IDLE_SEC") "") updIdleDefault))
                    (st (ServerState :rt rt :listener listener :pending (list) :bindMtimeNs (mtimeOf! cfg.socketPath) :idleMs idleMs
                                     :updatePeriodMs periodMs :updateIdleMs updIdleMs
                                     :lastActiveMs now :lastWorkMs now :nextUpdateMs (+ now periodMs) :rejected ""))
                    (_ (engineLog! cfg (str "listening on " cfg.socketPath " pid " (stringFromInt64 (procSelf)) " version " build.version)))]
                (ok (loop! st)))))))))
