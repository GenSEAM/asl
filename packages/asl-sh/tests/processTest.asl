(module asl-sh/tests/processTest
  :d "Unit tests for typed process execution and shell pipelines."
  :x [runTests runTests!]
  :i [(asl-sh/process :a proc)
      (asl-sh/pipe :a pipe)])

(df testExecEcho [] -> Bool
  :d "Verifies exec! running echo with argument vector"
  (let [(res (proc/exec! (proc/cmd "echo" (list "hello" "world"))))]
    (assert (= (.-_tag res) "ok") "echo must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "echo exit code 0")
      (assert (= (.-stdout out) "hello world") "echo stdout match")
      (assert (= (.-stderr out) "") "echo stderr empty")
      true)))

(df testExecCatStdin [] -> Bool
  :d "Verifies exec! running cat with piped stdin"
  (let [(c (proc/withStdin (proc/cmd "cat" (list)) "stream data"))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "cat must succeed")
    (let [(out (.-value res))]
      (do
        (assert (= (.-exitCode out) 0) "cat exit code 0")
        (assert (= (.-stdout out) "stream data") "cat stdout match")
        true))))

(df testExecTrueFalse [] -> Bool
  :d "Verifies exec! exit codes for true and false commands"
  (let [(rTrue (proc/exec! (proc/cmd "true" (list))))
        (rFalse (proc/exec! (proc/cmd "false" (list))))]
    (assert (= (.-_tag rTrue) "ok") "true must return ok")
    (assert (= (.-exitCode (.-value rTrue)) 0) "true exit code 0")
    (assert (= (.-_tag rFalse) "ok") "false must return ok")
    (assert (= (.-exitCode (.-value rFalse)) 1) "false exit code 1")
    true))

(df testExecGrepFiltering [] -> Bool
  :d "Verifies exec! grep filtering on stdin data"
  (let [(input "alpha\nbeta target\ngamma")
        (c (proc/withStdin (proc/cmd "grep" (list "target")) input))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "grep must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "grep exit code 0")
      (assert (= (.-stdout out) "beta target") "grep matched expected line")
      true)))

(df testExecNotFound [] -> Bool
  :d "Verifies exec! returns not-found error for unknown command"
  (let [(res (proc/exec! (proc/cmd "nonexistent-cmd-xyz" (list))))]
    (assert (= (.-_tag res) "err") "unknown cmd must error")
    true))

(df testExecStdinFailure [] -> Bool
  :d "Verifies exec! returns correct non-zero exit code when stdin is provided."
  (let [(c (proc/withStdin (proc/cmd "grep" (list "nonexistent_pattern")) "some data\nstream data"))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "grep must complete normally")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 1) "grep exit code 1 for no match")
      (assert (= (.-stdout out) "") "grep stdout empty")
      true)))

(df testPipeEchoCat [] -> Bool
  :d "Verifies 2-stage pipeline connecting echo to cat"
  (let [(p (pipe/makePipeline (list (proc/cmd "echo" (list "piped payload"))
                                     (proc/cmd "cat" (list)))))
        (res (pipe/pipe! p))]
    (assert (= (.-_tag res) "ok") "pipeline must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "pipe exit code 0")
      (assert (= (.-stdout out) "piped payload") "pipe output matches")
      true)))

(df testPipeMultiStage [] -> Bool
  :d "Verifies multi-stage pipeline with echo and grep"
  (let [(p (pipe/makePipeline (list (proc/cmd "echo" (list "line one\nneedle line\nline three"))
                                     (proc/cmd "grep" (list "needle")))))
        (res (pipe/pipe! p))]
    (assert (= (.-_tag res) "ok") "multi-stage pipeline must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "grep pipe exit 0")
      (assert (= (.-stdout out) "needle line") "grep pipe filtered line")
      true)))

(df testExecCwd [] -> Bool
  :d "Verifies exec! respects cwd working directory."
  (let [(c (proc/withCwd (proc/cmd "pwd" (list)) "tmp"))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "pwd in tmp must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "pwd exit code 0")
      (assert (string-ends-with? (.-stdout out) "/tmp") "pwd stdout ends with /tmp")
      true)))

(df testExecEnv [] -> Bool
  :d "Verifies exec! passes environment variable overrides."
  (let [(c (proc/withEnv (proc/cmd "sh" (list "-c" "echo $ASL_TEST_ENV_VAR")) "ASL_TEST_ENV_VAR" "custom_proc_val"))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "echo env var must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "env test exit code 0")
      (assert (= (.-stdout out) "custom_proc_val") "env var value matches")
      true)))

(df testExecTimeout [] -> Bool
  :d "Verifies exec! enforces execution timeout deadline on long running process."
  (let [(c (proc/withTimeout (proc/cmd "sleep" (list "5")) 200))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "err") "sleep 5 with 200ms timeout must return err")
    (let [(errVal (.-value res))]
      (assert (= (.-_variant errVal) "timeout") "error variant must be timeout")
      true)))

(df testExecLargeStdin [] -> Bool
  :d "Verifies exec! handles large stdin without overflowing ARG_MAX."
  (let [(chunk "0123456789abcdef0123456789abcdef")
        (largeInput (fold (fn [(acc String) (_i Int64)] -> String (str acc chunk)) "" (range 0 2000)))
        (c (proc/withStdin (proc/cmd "wc" (list "-c")) largeInput))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "large stdin wc must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exitCode out) 0) "wc exit code 0")
      (assert (string-contains? (.-stdout out) "64000") "wc output contains 64000 bytes")
      true)))

(df runTests [] -> Bool
  :d "Runs all process execution and pipe engine tests"
  (do
    (assert (testExecEcho) "test-exec-echo must pass")
    (assert (testExecCatStdin) "test-exec-cat-stdin must pass")
    (assert (testExecTrueFalse) "test-exec-true-false must pass")
    (assert (testExecGrepFiltering) "test-exec-grep-filtering must pass")
    (assert (testExecNotFound) "test-exec-not-found must pass")
    (assert (testExecStdinFailure) "test-exec-stdin-failure must pass")
    (assert (testPipeEchoCat) "test-pipe-echo-cat must pass")
    (assert (testPipeMultiStage) "test-pipe-multi-stage must pass")
    (assert (testExecCwd) "test-exec-cwd must pass")
    (assert (testExecEnv) "test-exec-env must pass")
    (assert (testExecTimeout) "test-exec-timeout must pass")
    (assert (testExecLargeStdin) "test-exec-large-stdin must pass")
    true))

(df ! runTests! [] -> (Result Unit String)
  :d "Runner entrypoint returning Result"
  (if (runTests)
      (ok ())
      (err "process_test failed")))
