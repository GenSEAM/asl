(module asl-sh/tests/process-test
  :d "Unit tests for typed process execution and shell pipelines."
  :x [run-tests run-tests!]
  :i [(asl-sh/process :a proc)
      (asl-sh/pipe :a pipe)])

(df test-exec-echo [] -> Bool
  :d "Verifies exec! running echo with argument vector"
  (let [(res (proc/exec! (proc/cmd "echo" (list "hello" "world"))))]
    (assert (= (.-_tag res) "ok") "echo must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exit-code out) 0) "echo exit code 0")
      (assert (= (.-stdout out) "hello world") "echo stdout match")
      (assert (= (.-stderr out) "") "echo stderr empty")
      true)))

(df test-exec-cat-stdin [] -> Bool
  :d "Verifies exec! running cat with piped stdin"
  (let [(c (proc/with-stdin (proc/cmd "cat" (list)) "stream data"))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "cat must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exit-code out) 0) "cat exit code 0")
      (assert (= (.-stdout out) "stream data") "cat stdout match")
      true)))

(df test-exec-true-false [] -> Bool
  :d "Verifies exec! exit codes for true and false commands"
  (let [(r-true (proc/exec! (proc/cmd "true" (list))))
        (r-false (proc/exec! (proc/cmd "false" (list))))]
    (assert (= (.-_tag r-true) "ok") "true must return ok")
    (assert (= (.-exit-code (.-value r-true)) 0) "true exit code 0")
    (assert (= (.-_tag r-false) "ok") "false must return ok")
    (assert (= (.-exit-code (.-value r-false)) 1) "false exit code 1")
    true))

(df test-exec-grep-filtering [] -> Bool
  :d "Verifies exec! grep filtering on stdin data"
  (let [(input "alpha\nbeta target\ngamma")
        (c (proc/with-stdin (proc/cmd "grep" (list "target")) input))
        (res (proc/exec! c))]
    (assert (= (.-_tag res) "ok") "grep must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exit-code out) 0) "grep exit code 0")
      (assert (= (.-stdout out) "beta target") "grep matched expected line")
      true)))

(df test-exec-not-found [] -> Bool
  :d "Verifies exec! returns not-found error for unknown command"
  (let [(res (proc/exec! (proc/cmd "nonexistent-cmd-xyz" (list))))]
    (assert (= (.-_tag res) "err") "unknown cmd must error")
    true))

(df test-pipe-echo-cat [] -> Bool
  :d "Verifies 2-stage pipeline connecting echo to cat"
  (let [(p (pipe/make-pipeline (list (proc/cmd "echo" (list "piped payload"))
                                     (proc/cmd "cat" (list)))))
        (res (pipe/pipe! p))]
    (assert (= (.-_tag res) "ok") "pipeline must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exit-code out) 0) "pipe exit code 0")
      (assert (= (.-stdout out) "piped payload") "pipe output matches")
      true)))

(df test-pipe-multi-stage [] -> Bool
  :d "Verifies multi-stage pipeline with echo and grep"
  (let [(p (pipe/make-pipeline (list (proc/cmd "echo" (list "line one\nneedle line\nline three"))
                                     (proc/cmd "grep" (list "needle")))))
        (res (pipe/pipe! p))]
    (assert (= (.-_tag res) "ok") "multi-stage pipeline must succeed")
    (let [(out (.-value res))]
      (assert (= (.-exit-code out) 0) "grep pipe exit 0")
      (assert (= (.-stdout out) "needle line") "grep pipe filtered line")
      true)))

(df run-tests [] -> Bool
  :d "Runs all process execution and pipe engine tests"
  (do
    (assert (test-exec-echo) "test-exec-echo must pass")
    (assert (test-exec-cat-stdin) "test-exec-cat-stdin must pass")
    (assert (test-exec-true-false) "test-exec-true-false must pass")
    (assert (test-exec-grep-filtering) "test-exec-grep-filtering must pass")
    (assert (test-exec-not-found) "test-exec-not-found must pass")
    (assert (test-pipe-echo-cat) "test-pipe-echo-cat must pass")
    (assert (test-pipe-multi-stage) "test-pipe-multi-stage must pass")
    true))

(df ! run-tests! [] -> (Result Unit String)
  :d "Runner entrypoint returning Result"
  (if (run-tests)
      (ok ())
      (err "process_test failed")))
