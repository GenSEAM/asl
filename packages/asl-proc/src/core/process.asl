(module asl-proc/coreProcess :x [ProcessCmd ProcessOutput ProcessError ProcessReceipt ProcessSession cmd withCwd withTimeout withStdin withEnv buildShellCmd exec! execRaw! runSimple! sessionSpawn! sessionSpawnWithPid! sessionSendInput! sessionInput! sessionPollTail! sessionTail! sessionEmitStdout! sessionEmitStderr! sessionKill! sessionCheckDeadlock sessionStepDeadline! sessionTickIdle sessionExtendTimeout sessionSetTimeout makeProcessReceipt renderReceipt receiptTokens] :i [(asl-text/text :a txt)])

(schema ProcessCmd (:f bin String) (:f args (List String)) (:f env (Map String String)) (:f cwd (Option String)) (:f timeoutMs Int64 :default 5000) (:f stdinData (Option String)))

(schema ProcessOutput (:f exitCode Int64) (:f stdout String) (:f stderr String) (:f durationMs Int64))

(schema ProcessReceipt (:f exitCode Int64) (:f durationMs Int64) (:f peakRssMb Int64) (:f spoolPath String) (:f summary String))

(schema ProcessSession (:f id String) (:f pid Int64) (:f state String) (:f cmd ProcessCmd) (:f stdinBuffer (List String)) (:f stdoutBuffer (List String)) (:f stderrBuffer (List String)) (:f exitCode (Option Int64)) (:f idleMs Int64) (:f timeoutMs Int64) (:f deadlockDetected Bool) (:f deadlocked Bool) (:f termDeadlineMs Int64) (:f killDeadlineMs Int64) (:f terminationReceipt (Option ProcessReceipt)))

(enum ProcessError (:c notFound [(bin String)] "Command binary was not found") (:c timeout [(ms Int64)] "Command execution timed out") (:c permissionDenied [(path String)] "Access permission denied to executable") (:c executionFailed [(code Int64) (msg String)] "Process exited with non-zero status"))

fn cmd bin: String args: (List String) -> ProcessCmd
  (ProcessCmd :bin bin :args args :env (mapEmpty) :cwd (none) :timeoutMs 5000 :stdinData (none))

fn withCwd c: ProcessCmd dir: String -> ProcessCmd
  (with c :cwd (some dir))

fn withTimeout c: ProcessCmd ms: Int64 -> ProcessCmd
  (with c :timeoutMs ms)

fn withStdin c: ProcessCmd input: String -> ProcessCmd
  (with c :stdinData (some input))

fn withEnv c: ProcessCmd k: String v: String -> ProcessCmd
  (with c :env (mapSet c.env k v))

fn quoteShellArg arg: String -> String
  (str "'" (stringReplace arg "'" "'\\''") "'")

fn stripTrailingNewline s: String -> String
  (if (stringEndsWith? s "\n") (optionOr (stringSlice s 0 (- (stringLength s) 1)) s) s)

fn formatTimeoutSeconds ms: Int64 -> String
  (let [(sec (/ ms 1000)) (fraction (mod (/ ms 100) 10))] (if (< ms 1000) (str "0." (stringFromInt64 (/ ms 100))) (if (> fraction 0) (str (stringFromInt64 sec) "." (stringFromInt64 fraction)) (stringFromInt64 sec))))

fn buildShellCmd c: ProcessCmd stdinPath: String -> String
  (let [(b c.bin) (args c.args) (quotedBin (quoteShellArg b)) (quotedArgs (map quoteShellArg args)) (baseCmd (if (listEmpty? quotedArgs) quotedBin (str quotedBin " " (stringJoin quotedArgs " ")))) (envKeys (mapKeys c.env)) (envPrefix (if (listEmpty? envKeys) "" (let [(entries (map (fn [(k String)] -> String (let [(v (optionOr (mapGet c.env k) ""))] (str k "=" (quoteShellArg v)))) envKeys))] (str "env " (stringJoin entries " ") " ")))) (cwdPrefix (mt c.cwd ((some d) (str "cd " (quoteShellArg d) " && ")) ((none) ""))) (cmdWithEnv (str cwdPrefix envPrefix baseCmd)) (stdinOpt c.stdinData) (stdinPart (mt stdinOpt ((some s) (if (stringEmpty? s) "< /dev/null" (if (stringEmpty? stdinPath) "" (str "< " (quoteShellArg stdinPath))))) ((none) "< /dev/null"))) (innerCmd (mt stdinOpt ((some s) (if (and (not (stringEmpty? s)) (stringEmpty? stdinPath)) (str "printf '%s' " (quoteShellArg s) " | ( " cmdWithEnv " )") (str "( " cmdWithEnv " ) " stdinPart))) ((none) (str "( " cmdWithEnv " ) " stdinPart)))) (timeout c.timeoutMs)] (if (<= timeout 0) innerCmd (let [(tSec (formatTimeoutSeconds timeout))] (str "S=$(mktemp 2>/dev/null || echo /tmp/.asl_wd_sentinel_$$); rm -f $S; ( " innerCmd " ) & P=$!; (sleep " tSec " >/dev/null 2>&1 < /dev/null && touch $S && kill -9 $P 2>/dev/null) >/dev/null 2>&1 < /dev/null & W=$!; wait $P 2>/dev/null; R=$?; { kill -9 $W && wait $W; } 2>/dev/null; if [ -f $S ]; then rm -f $S; exit 124; else rm -f $S; exit $R; fi"))))

fn buildShellCmdArgs b: String args: (List String) stdinVal: String -> String
  (let [(c (ProcessCmd :bin b :args args :env (mapEmpty) :cwd (none) :timeoutMs 5000 :stdinData (if (stringEmpty? stdinVal) (none) (some stdinVal))))] (buildShellCmd c ""))

fn envRowKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn childEnv! overrides: (Map String String) -> (Option (List String))
  (let [(keys (mapKeys overrides))]
    (if (listEmpty? keys)
      (none)
      (let [(kept (filter (fn [(row String)] -> Bool (none? (mapGet overrides (envRowKey row)))) (envList)))
            (added (map (fn [(k String)] -> String (str k "=" (optionOr (mapGet overrides k) ""))) keys))]
        (some (listAppend kept added)))))

(schema ExecIo (:f pending String) (:f inOpen Bool) (:f outOpen Bool) (:f errOpen Bool) (:f out String) (:f errText String))

fn pollSet sp: SpawnedProc io: ExecIo -> (List (Pair Int64 Int64))
  (let [(w (if io.inOpen (list (pair sp.stdin 2)) (list)))
        (o (if io.outOpen (list (pair sp.stdout 1)) (list)))
        (e (if io.errOpen (list (pair sp.stderr 1)) (list)))]
    (listAppend w (listAppend o e)))

fn readyOn ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (not (listEmpty? (filter (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)))

fn ! stepStdin sp: SpawnedProc io: ExecIo -> ExecIo
  (if (stringEmpty? io.pending)
    (do (fdClose sp.stdin) (with io :pending "" :inOpen false))
    (mt (fdWrite sp.stdin io.pending)
      ((ok n) (with io :pending (optionOr (stringSlice io.pending n (stringLength io.pending)) "") :inOpen true))
      ((err e) (if (= e "wouldBlock") io (do (fdClose sp.stdin) (with io :pending "" :inOpen false))))))

fn ! stepOut sp: SpawnedProc io: ExecIo -> ExecIo
  (mt (fdRead sp.stdout 65536)
    ((ok chunk) (if (stringEmpty? chunk)
      (do (fdClose sp.stdout) (with io :outOpen false))
      (with io :outOpen true :out (str io.out chunk))))
    ((err e) (if (= e "wouldBlock") io (do (fdClose sp.stdout) (with io :outOpen false)))))

fn ! stepErr sp: SpawnedProc io: ExecIo -> ExecIo
  (mt (fdRead sp.stderr 65536)
    ((ok chunk) (if (stringEmpty? chunk)
      (do (fdClose sp.stderr) (with io :errOpen false))
      (with io :errOpen true :errText (str io.errText chunk))))
    ((err e) (if (= e "wouldBlock") io (do (fdClose sp.stderr) (with io :errOpen false)))))

fn ! closeOpen sp: SpawnedProc io: ExecIo -> Bool
  (do (if io.inOpen (fdClose sp.stdin) (ok ())) (if io.outOpen (fdClose sp.stdout) (ok ())) (if io.errOpen (fdClose sp.stderr) (ok ())) true)

fn ! pumpIo sp: SpawnedProc io: ExecIo deadlineNs: Int64 -> (Result ExecIo Int64)
  (if (not (or io.outOpen io.errOpen))
    (do (if io.inOpen (fdClose sp.stdin) (ok ())) (ok io))
    (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
      (if (<= leftMs 0)
        (do (closeOpen sp io) (err 0))
        (mt (fdPoll (pollSet sp io) leftMs)
          ((err _) (do (closeOpen sp io) (err 1)))
          ((ok ready)
            (let [(io1 (if (and io.inOpen (readyOn ready sp.stdin)) (stepStdin sp io) io))
                  (io2 (if (and io1.outOpen (readyOn ready sp.stdout)) (stepOut sp io1) io1))
                  (io3 (if (and io2.errOpen (readyOn ready sp.stderr)) (stepErr sp io2) io2))]
              (pumpIo sp io3 deadlineNs)))))))

fn spawnError b: String e: String -> ProcessError
  (cond ((= e "notFound") (notFound b)) ((= e "permission") (permissionDenied b)) (else (executionFailed -1 e)))

fn ! execCapture! c: ProcessCmd stripOutput: Bool -> (Result ProcessOutput ProcessError)
  (let [(b c.bin) (timeoutMsVal c.timeoutMs) (startNs (monotonicNs))]
    (if (<= timeoutMsVal 0)
      (err (timeout timeoutMsVal))
      (mt (procSpawnv (listAppend (list b) c.args) c.cwd (childEnv! c.env))
        ((err e) (err (spawnError b e)))
        ((ok sp)
          (let [(nb (fdNonBlocking sp.stdin true))
                (io0 (ExecIo :pending (optionOr c.stdinData "") :inOpen true :outOpen true :errOpen true :out "" :errText ""))
                (pumped (pumpIo sp io0 (+ startNs (* timeoutMsVal 1000000))))]
            (mt pumped
              ((err _) (do (procKill (- 0 sp.pid) "SIGKILL") (procWaitPid sp.pid false) (err (timeout timeoutMsVal))))
              ((ok io)
                (mt (procWaitPid sp.pid false)
                  ((err e) (err (executionFailed -1 e)))
                  ((ok code) (ok (ProcessOutput :exitCode (optionOr code -1) :stdout (if stripOutput (stripTrailingNewline io.out) io.out) :stderr (if stripOutput (stripTrailingNewline io.errText) io.errText) :durationMs (/ (- (monotonicNs) startNs) 1000000))))))))))))

fn ! exec! c: ProcessCmd -> (Result ProcessOutput ProcessError)
  (execCapture! c true)

fn ! execRaw! c: ProcessCmd -> (Result ProcessOutput ProcessError)
  (execCapture! c false)

fn runSimple! bin: String args: (List String) -> (Result String ProcessError)
  (mt (exec! (cmd bin args)) ((ok out) (if (= out.exitCode 0) (ok out.stdout) (err (executionFailed out.exitCode out.stderr)))) ((err e) (err e)))

fn makeProcessReceipt exitCode: Int64 durationMs: Int64 peakRssMb: Int64 spoolPath: String summary: String -> ProcessReceipt
  (ProcessReceipt :exitCode exitCode :durationMs durationMs :peakRssMb peakRssMb :spoolPath spoolPath :summary summary)

fn renderReceipt r: ProcessReceipt -> String
  (str "(:proc-receipt :exit " (stringFromInt64 r.exitCode) " :duration-ms " (stringFromInt64 r.durationMs) " :peak-rss-mb " (stringFromInt64 r.peakRssMb) " :spool-path \"" r.spoolPath "\"" " :summary \"" r.summary "\")")

fn receiptTokens r: ProcessReceipt -> Int64
  (txt/estimateTokens (renderReceipt r))

fn sessionSpawnWithPid! id: String pid: Int64 c: ProcessCmd -> ProcessSession
  (ProcessSession :id id :pid pid :state "active" :cmd c :stdinBuffer (list) :stdoutBuffer (list) :stderrBuffer (list) :exitCode (none) :idleMs 0 :timeoutMs c.timeoutMs :deadlockDetected false :termDeadlineMs 10000 :killDeadlineMs 12000 :terminationReceipt (none))

fn sessionSpawn! id: String c: ProcessCmd -> ProcessSession
  (sessionSpawnWithPid! id 1001 c)

fn sessionSendInput! s: ProcessSession input: String -> ProcessSession
  (if (= s.state "terminated") s (ProcessSession :id s.id :pid s.pid :state "active" :cmd s.cmd :stdinBuffer (listAppend s.stdinBuffer (list input)) :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs 0 :timeoutMs s.timeoutMs :deadlockDetected false :termDeadlineMs s.termDeadlineMs :killDeadlineMs s.killDeadlineMs :terminationReceipt s.terminationReceipt))

fn sessionInput! s: ProcessSession input: String -> ProcessSession
  (sessionSendInput! s input)

fn sessionEmitStdout! s: ProcessSession line: String -> ProcessSession
  (ProcessSession :id s.id :pid s.pid :state (if (= s.state "terminated") "terminated" "active") :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer (listAppend s.stdoutBuffer (list line)) :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs 0 :timeoutMs s.timeoutMs :deadlockDetected false :termDeadlineMs s.termDeadlineMs :killDeadlineMs s.killDeadlineMs :terminationReceipt s.terminationReceipt)

fn sessionEmitStderr! s: ProcessSession line: String -> ProcessSession
  (ProcessSession :id s.id :pid s.pid :state s.state :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer (listAppend s.stderrBuffer (list line)) :exitCode s.exitCode :idleMs 0 :timeoutMs s.timeoutMs :deadlockDetected false :termDeadlineMs s.termDeadlineMs :killDeadlineMs s.killDeadlineMs :terminationReceipt s.terminationReceipt)

fn sessionPollTail! s: ProcessSession n: Int64 -> (List String)
  (let [(buf s.stdoutBuffer) (cnt (listLength buf))] (cond ((<= n 0) (list)) ((>= n cnt) buf) (else (optionOr (listSlice buf (- cnt n) cnt) (list)))))

fn sessionTail! s: ProcessSession n: Int64 -> (List String)
  (sessionPollTail! s n)

fn sessionKill! s: ProcessSession sig: String -> ProcessSession
  (let [(code (cond ((= sig "SIGHUP") -1) ((= sig "SIGINT") -2) ((= sig "SIGQUIT") -3) ((= sig "SIGKILL") -9) ((= sig "SIGUSR1") -10) ((= sig "SIGUSR2") -12) ((= sig "SIGPIPE") -13) ((= sig "SIGALRM") -14) ((= sig "SIGTERM") -15) (else -9)))] (ProcessSession :id s.id :pid s.pid :state "terminated" :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode (some code) :idleMs s.idleMs :timeoutMs s.timeoutMs :deadlockDetected false :termDeadlineMs s.termDeadlineMs :killDeadlineMs s.killDeadlineMs :terminationReceipt s.terminationReceipt))

fn sessionCheckDeadlock s: ProcessSession idleCeiling: Int64 -> ProcessSession
  (let [(cap (if (<= idleCeiling 0) (if (<= s.timeoutMs 0) 10000 s.timeoutMs) idleCeiling)) (breached (>= s.idleMs cap))] (ProcessSession :id s.id :pid s.pid :state (if (= s.state "terminated") "terminated" (if breached "idle" "active")) :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs s.idleMs :timeoutMs s.timeoutMs :deadlockDetected breached :termDeadlineMs s.termDeadlineMs :killDeadlineMs s.killDeadlineMs :terminationReceipt s.terminationReceipt))

fn sessionTickIdle s: ProcessSession deltaMs: Int64 -> ProcessSession
  (let [(newIdle (+ s.idleMs deltaMs)) (ceiling (if (> s.timeoutMs 10000) s.timeoutMs 10000)) (isDeadlocked (>= newIdle ceiling))] (ProcessSession :id s.id :pid s.pid :state (if isDeadlocked "idle" s.state) :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs newIdle :timeoutMs s.timeoutMs :deadlockDetected isDeadlocked :termDeadlineMs s.termDeadlineMs :killDeadlineMs s.killDeadlineMs :terminationReceipt s.terminationReceipt))

fn sessionExtendTimeout s: ProcessSession extendMs: Int64 -> ProcessSession
  (ProcessSession :id s.id :pid s.pid :state s.state :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs 0 :timeoutMs (+ s.timeoutMs extendMs) :deadlockDetected false :termDeadlineMs (+ s.termDeadlineMs extendMs) :killDeadlineMs (+ s.killDeadlineMs extendMs) :terminationReceipt s.terminationReceipt)

fn sessionSetTimeout s: ProcessSession newMs: Int64 -> ProcessSession
  (ProcessSession :id s.id :pid s.pid :state s.state :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs 0 :timeoutMs newMs :deadlockDetected false :termDeadlineMs newMs :killDeadlineMs (+ newMs 2000) :terminationReceipt s.terminationReceipt)

fn sessionStepDeadline! s: ProcessSession deltaMs: Int64 spoolPath: String -> ProcessSession
  (if (= s.state "terminated") s (let [(newIdle (+ s.idleMs deltaMs)) (termLimit s.termDeadlineMs) (killLimit s.killDeadlineMs)] (cond ((>= newIdle killLimit) (let [(receipt (makeProcessReceipt -9 newIdle 0 spoolPath "Stdin deadlock guard: SIGKILL dispatched at 12s"))] (ProcessSession :id s.id :pid s.pid :state "terminated" :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode (some -9) :idleMs newIdle :timeoutMs s.timeoutMs :deadlockDetected true :termDeadlineMs termLimit :killDeadlineMs killLimit :terminationReceipt (some receipt)))) ((>= newIdle termLimit) (let [(receipt (makeProcessReceipt -15 newIdle 0 spoolPath "Stdin deadlock guard: SIGTERM dispatched at 10s"))] (ProcessSession :id s.id :pid s.pid :state "terminated" :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode (some -15) :idleMs newIdle :timeoutMs s.timeoutMs :deadlockDetected true :termDeadlineMs termLimit :killDeadlineMs killLimit :terminationReceipt (some receipt)))) (else (ProcessSession :id s.id :pid s.pid :state s.state :cmd s.cmd :stdinBuffer s.stdinBuffer :stdoutBuffer s.stdoutBuffer :stderrBuffer s.stderrBuffer :exitCode s.exitCode :idleMs newIdle :timeoutMs s.timeoutMs :deadlockDetected false :termDeadlineMs termLimit :killDeadlineMs killLimit :terminationReceipt s.terminationReceipt)))))
