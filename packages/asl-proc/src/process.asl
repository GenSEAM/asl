(module asl-proc/process :x [status list procStatus procList proc/status proc/list cmd withCwd withTimeout withStdin withEnv buildShellCmd exec! execRaw! runSimple! sessionSpawn! sessionSpawnWithPid! sessionSendInput! sessionInput! sessionPollTail! sessionTail! sessionEmitStdout! sessionEmitStderr! sessionKill! sessionCheckDeadlock sessionStepDeadline! sessionTickIdle sessionExtendTimeout sessionSetTimeout makeProcessReceipt renderReceipt receiptTokens] :i [(asl-proc/coreProcess :a cp) (apm :a apm)])

fn status elapsedMs: I64 deadlineMs: I64 opName: Str -> apm/SupervisorVerdict
  (apm/superviseStep elapsedMs deadlineMs opName)

fn list entries: (List apm/DaemonEntry) -> Str
  (apm/formatDaemonTable entries)

fn procStatus elapsedMs: I64 deadlineMs: I64 opName: Str -> apm/SupervisorVerdict
  (apm/superviseStep elapsedMs deadlineMs opName)

fn procList entries: (List apm/DaemonEntry) -> Str
  (apm/formatDaemonTable entries)

fn proc/status elapsedMs: I64 deadlineMs: I64 opName: Str -> apm/SupervisorVerdict
  (apm/superviseStep elapsedMs deadlineMs opName)

fn proc/list entries: (List apm/DaemonEntry) -> Str
  (apm/formatDaemonTable entries)

fn cmd bin: String args: (List String) -> cp/ProcessCmd
  (cp/cmd bin args)

fn withCwd c: cp/ProcessCmd dir: String -> cp/ProcessCmd
  (cp/withCwd c dir)

fn withTimeout c: cp/ProcessCmd ms: Int64 -> cp/ProcessCmd
  (cp/withTimeout c ms)

fn withStdin c: cp/ProcessCmd input: String -> cp/ProcessCmd
  (cp/withStdin c input)

fn withEnv c: cp/ProcessCmd k: String v: String -> cp/ProcessCmd
  (cp/withEnv c k v)

fn buildShellCmd c: cp/ProcessCmd stdinPath: String -> String
  (cp/buildShellCmd c stdinPath)

fn ! exec! c: cp/ProcessCmd -> (Result cp/ProcessOutput cp/ProcessError)
  (cp/exec! c)

fn ! execRaw! c: cp/ProcessCmd -> (Result cp/ProcessOutput cp/ProcessError)
  (cp/execRaw! c)

fn ! runSimple! bin: String args: (List String) -> (Result String cp/ProcessError)
  (cp/runSimple! bin args)

fn ! sessionSpawn! id: String c: cp/ProcessCmd -> cp/ProcessSession
  (cp/sessionSpawn! id c)

fn ! sessionSpawnWithPid! id: String pid: Int64 c: cp/ProcessCmd -> cp/ProcessSession
  (cp/sessionSpawnWithPid! id pid c)

fn ! sessionSendInput! s: cp/ProcessSession input: String -> cp/ProcessSession
  (cp/sessionSendInput! s input)

fn ! sessionInput! s: cp/ProcessSession input: String -> cp/ProcessSession
  (cp/sessionInput! s input)

fn sessionPollTail! s: cp/ProcessSession n: Int64 -> (List String)
  (cp/sessionPollTail! s n)

fn sessionTail! s: cp/ProcessSession n: Int64 -> (List String)
  (cp/sessionTail! s n)

fn ! sessionEmitStdout! s: cp/ProcessSession line: String -> cp/ProcessSession
  (cp/sessionEmitStdout! s line)

fn ! sessionEmitStderr! s: cp/ProcessSession line: String -> cp/ProcessSession
  (cp/sessionEmitStderr! s line)

fn ! sessionKill! s: cp/ProcessSession sig: String -> cp/ProcessSession
  (let [(effectiveSig (if (stringEmpty? sig) "SIGKILL" sig))] (cp/sessionKill! s effectiveSig))

fn sessionCheckDeadlock s: cp/ProcessSession idleCeiling: Int64 -> cp/ProcessSession
  (let [(res (cp/sessionCheckDeadlock s idleCeiling))] (cp/ProcessSession :id res.id :pid res.pid :state res.state :cmd res.cmd :stdinBuffer res.stdinBuffer :stdoutBuffer res.stdoutBuffer :stderrBuffer res.stderrBuffer :exitCode res.exitCode :idleMs res.idleMs :timeoutMs res.timeoutMs :deadlockDetected res.deadlockDetected :deadlocked res.deadlockDetected :termDeadlineMs res.termDeadlineMs :killDeadlineMs res.killDeadlineMs :terminationReceipt res.terminationReceipt))

fn ! sessionStepDeadline! s: cp/ProcessSession deltaMs: Int64 spoolPath: String -> cp/ProcessSession
  (cp/sessionStepDeadline! s deltaMs spoolPath)

fn sessionTickIdle s: cp/ProcessSession deltaMs: Int64 -> cp/ProcessSession
  (cp/sessionTickIdle s deltaMs)

fn sessionExtendTimeout s: cp/ProcessSession extendMs: Int64 -> cp/ProcessSession
  (cp/sessionExtendTimeout s extendMs)

fn sessionSetTimeout s: cp/ProcessSession newMs: Int64 -> cp/ProcessSession
  (cp/sessionSetTimeout s newMs)

fn makeProcessReceipt exitCode: Int64 durationMs: Int64 peakRssMb: Int64 spoolPath: String summary: String -> cp/ProcessReceipt
  (cp/makeProcessReceipt exitCode durationMs peakRssMb spoolPath summary)

fn renderReceipt r: cp/ProcessReceipt -> String
  (cp/renderReceipt r)

fn receiptTokens r: cp/ProcessReceipt -> Int64
  (cp/receiptTokens r)
