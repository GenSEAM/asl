(module aslHarness/tbench4Hardener :x [TBenchHardener SkeletonLog IdleTimeoutTimer sanitizeTerminalExecution extractProcSkeleton makeTbenchHardener makeSkeletonLog makeIdleTimeoutTimer] :i [])

(schema IdleTimeoutTimer (:f slidingTimeoutMs I64) (:f hardCeilingMs I64) (:f escalationSigkill Bool))

(schema SkeletonLog (:f totalLines I64) (:f errorLines I64) (:f headSnippet Str) (:f tailSnippet Str) (:f exitedCleanly Bool))

(schema TBenchHardener (:f nonInteractive Bool) (:f idleTimer IdleTimeoutTimer) (:f maxLogLines I64))

fn makeIdleTimeoutTimer sliding: I64 ceiling: I64 sigkill: Bool -> IdleTimeoutTimer
  (IdleTimeoutTimer :slidingTimeoutMs sliding :hardCeilingMs ceiling :escalationSigkill sigkill)

fn makeSkeletonLog total: I64 errors: I64 head: Str tail: Str clean: Bool -> SkeletonLog
  (SkeletonLog :totalLines total :errorLines errors :headSnippet head :tailSnippet tail :exitedCleanly clean)

fn makeTbenchHardener nonInt: Bool idleTimer: IdleTimeoutTimer maxLines: I64 -> TBenchHardener
  (TBenchHardener :nonInteractive nonInt :idleTimer idleTimer :maxLogLines maxLines)

fn sanitizeTerminalExecution cmd: Str hardener: TBenchHardener -> Str
  (let [(trimmed (stringTrim cmd))] (cond ((stringEmpty? trimmed) "") (hardener.nonInteractive (cond ((stringContains? trimmed "sudo ") (stringReplace trimmed "sudo " "sudo -n ")) ((stringContains? trimmed "apt-get ") (str "DEBIAN_FRONTEND=noninteractive " trimmed " -y")) (true (str "CI=1 TERM=dumb " trimmed)))) (true trimmed)))

fn countErrorLines text: Str -> I64
  (let [(c1 (if (stringContains? text "error:") 1 0)) (c2 (if (stringContains? text "FAILED") 1 0)) (c3 (if (stringContains? text "fatal:") 1 0)) (c4 (if (stringContains? text "Permission denied") 1 0))] (+ c1 (+ c2 (+ c3 c4))))

fn extractProcSkeleton output: Str exitCode: I64 -> SkeletonLog
  (let [(clean (stringTrim output)) (errors (countErrorLines clean)) (isClean (= exitCode 0)) (head (if (> (stringLength clean) 80) (stringReplace clean "
" " | ") clean)) (tail (if (stringContains? clean "error") "contains error signature" "exit nominal"))] (makeSkeletonLog 10 errors head tail isClean))
