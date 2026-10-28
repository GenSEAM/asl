(module asl-proc/tests/processTest :x [runTests runTests!] :i [(asl-proc/process :a proc) (asl-proc/pipe :a pipe) (asl-proc/coreProcess :a cp)])

fn outOf r: (Result cp/ProcessOutput cp/ProcessError) -> cp/ProcessOutput
  (match r ((ok o) o) ((err _) (cp/ProcessOutput :exitCode -1 :stdout "" :stderr "" :durationMs 0)))

fn isTimeout r: (Result cp/ProcessOutput cp/ProcessError) -> Bool
  (match r ((err e) (match e ((timeout ms) true) (_ false))) (_ false))

fn testExecEcho! -> Bool
  (let [(res (proc/exec! (proc/cmd "echo" (list "hello" "world"))))] (assert (ok? res) "echo must succeed") (let [(out (outOf res))] (assert (= out.exitCode 0) "echo exit code 0") (assert (= out.stdout "hello world") "echo stdout match") (assert (= out.stderr "") "echo stderr empty") true))

fn testExecCatStdin! -> Bool
  (let [(c (proc/withStdin (proc/cmd "cat" (list)) "stream data")) (res (proc/exec! c))] (assert (ok? res) "cat must succeed") (let [(out (outOf res))] (do (assert (= out.exitCode 0) "cat exit code 0") (assert (= out.stdout "stream data") "cat stdout match") true)))

fn testExecTrueFalse! -> Bool
  (let [(rTrue (proc/exec! (proc/cmd "true" (list)))) (rFalse (proc/exec! (proc/cmd "false" (list))))] (assert (ok? rTrue) "true must return ok") (assert (= (outOf rTrue).exitCode 0) "true exit code 0") (assert (ok? rFalse) "false must return ok") (assert (= (outOf rFalse).exitCode 1) "false exit code 1") true)

fn testExecGrepFiltering! -> Bool
  (let [(input "alpha\nbeta target\ngamma") (c (proc/withStdin (proc/cmd "grep" (list "target")) input)) (res (proc/exec! c))] (assert (ok? res) "grep must succeed") (let [(out (outOf res))] (assert (= out.exitCode 0) "grep exit code 0") (assert (= out.stdout "beta target") "grep matched expected line") true))

fn testExecNotFound! -> Bool
  (let [(res (proc/exec! (proc/cmd "nonexistent-cmd-xyz" (list))))] (assert (err? res) "unknown cmd must error") true)

fn testExecStdinFailure! -> Bool
  (let [(c (proc/withStdin (proc/cmd "grep" (list "nonexistent_pattern")) "some data\nstream data")) (res (proc/exec! c))] (assert (ok? res) "grep must complete normally") (let [(out (outOf res))] (assert (= out.exitCode 1) "grep exit code 1 for no match") (assert (= out.stdout "") "grep stdout empty") true))

fn testPipeEchoCat! -> Bool
  (let [(p (pipe/makePipeline (list (proc/cmd "echo" (list "piped payload")) (proc/cmd "cat" (list))))) (res (pipe/pipe! p))] (assert (ok? res) "pipeline must succeed") (let [(out (outOf res))] (assert (= out.exitCode 0) "pipe exit code 0") (assert (= out.stdout "piped payload") "pipe output matches") true))

fn testPipeMultiStage! -> Bool
  (let [(p (pipe/makePipeline (list (proc/cmd "echo" (list "line one\nneedle line\nline three")) (proc/cmd "grep" (list "needle"))))) (res (pipe/pipe! p))] (assert (ok? res) "multi-stage pipeline must succeed") (let [(out (outOf res))] (assert (= out.exitCode 0) "grep pipe exit 0") (assert (= out.stdout "needle line") "grep pipe filtered line") true))

fn testExecCwd! -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/asl-proc-test-" (stringFromInt64 (monotonicNs)))) (tmpDir (str base "/tmp")) (_ (dirCreate tmpDir)) (c (proc/withCwd (proc/cmd "pwd" (list)) tmpDir)) (res (proc/exec! c)) (out (outOf res)) (_ (pathRemove base))] (do (assert (ok? res) "pwd in tmp must succeed") (assert (= out.exitCode 0) "pwd exit code 0") (assert (stringEndsWith? (stringTrim out.stdout) "/tmp") "pwd stdout ends with /tmp") true))

fn testExecEnv! -> Bool
  (let [(c (proc/withEnv (proc/cmd "sh" (list "-c" "echo $ASL_TEST_ENV_VAR")) "ASL_TEST_ENV_VAR" "custom_proc_val")) (res (proc/exec! c))] (assert (ok? res) "echo env var must succeed") (let [(out (outOf res))] (assert (= out.exitCode 0) "env test exit code 0") (assert (= out.stdout "custom_proc_val") "env var value matches") true))

fn testExecTimeout! -> Bool
  (let [(c (proc/withTimeout (proc/cmd "sleep" (list "5")) 200)) (res (proc/exec! c))] (assert (err? res) "sleep 5 with 200ms timeout must return err") (let [(errVal (isTimeout res))] (assert errVal "error variant must be timeout") true))

fn testExecLargeStdin! -> Bool
  (let [(chunk "0123456789abcdef0123456789abcdef") (c1 (str chunk chunk chunk chunk chunk chunk chunk chunk chunk chunk)) (c2 (str c1 c1 c1 c1 c1 c1 c1 c1 c1 c1)) (largeInput (str c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2 c2)) (c (proc/withStdin (proc/cmd "wc" (list "-c")) largeInput)) (res (proc/exec! c))] (assert (ok? res) "large stdin wc must succeed") (let [(out (outOf res))] (assert (= out.exitCode 0) "wc exit code 0") (assert (stringContains? out.stdout "64000") "wc output contains 64000 bytes") true))

fn testCommandConstruction -> Bool
  (let [(base (proc/cmd "echo" (list "hello" "world")))
        (withDir (proc/withCwd base "tmp"))
        (withE (proc/withEnv withDir "STAGE" "production"))
        (withT (proc/withTimeout withE 4000))
        (withIn (proc/withStdin withT "input stream"))
        (shellCmd (proc/buildShellCmd withIn "tmp/mock_stdin.txt"))]
    (assert (= base.bin "echo") "base cmd binary matches echo")
    (refute (!= base.bin "echo") "base cmd binary must not deviate from echo")
    (assert (= (listLength base.args) 2) "base cmd arg count is 2")
    (assert (= withT.timeoutMs 4000) "timeout configured to 4000ms")
    (refute (!= withT.timeoutMs 4000) "timeout must not deviate from 4000ms")
    (assert (stringContains? shellCmd "'echo'") "shell command contains quoted binary")
    (assert (stringContains? shellCmd "cd 'tmp' &&") "shell command contains working directory prefix")
    (assert (stringContains? shellCmd "STAGE='production'") "shell command contains environment binding")
    (assert (stringContains? shellCmd "sleep 4") "shell command configures the timeout interval")
    (refute (stringContains? shellCmd "STAGE=production ") "environment values must be shell-quoted")
    true)


fn ! runTests -> Bool
  (do (assert (testCommandConstruction) "testCommandConstruction must pass") (assert (testExecEcho!) "test-exec-echo must pass") (assert (testExecCatStdin!) "test-exec-cat-stdin must pass") (assert (testExecTrueFalse!) "test-exec-true-false must pass") (assert (testExecGrepFiltering!) "test-exec-grep-filtering must pass") (assert (testExecNotFound!) "test-exec-not-found must pass") (assert (testExecStdinFailure!) "test-exec-stdin-failure must pass") (assert (testPipeEchoCat!) "test-pipe-echo-cat must pass") (assert (testPipeMultiStage!) "test-pipe-multi-stage must pass") (assert (testExecCwd!) "test-exec-cwd must pass") (assert (testExecEnv!) "test-exec-env must pass") (assert (testExecTimeout!) "test-exec-timeout must pass") (assert (testExecLargeStdin!) "test-exec-large-stdin must pass") true)

fn ! runTests! -> (Result Unit String)
  (if (runTests) (ok ()) (err "process_test failed"))
