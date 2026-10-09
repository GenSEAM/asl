(module aslHarness/containerBenchTest :x [testContainerConfigDocker testContainerConfigModal testContainerExecutionEvaluation testDualPolarityRefutations runTests] :i [(containerBench :a cb)])

fn testContainerConfigDocker -> Bool
  (let [(cfg (cb/makeContainerConfig :docker "gemma-4-31b-it" 90 true))]
    (assert (= cfg.target "docker") "target must be docker")
    (assert (= cfg.model "gemma-4-31b-it") "model matches")
    (assert cfg.airgap "airgap active")
    (assert (cb/isLocalExecution? cfg) "docker is local execution")
    true)

fn testContainerConfigModal -> Bool
  (let [(cfg (cb/makeContainerConfig :modal "gemma-4-31b-it" 90 false))]
    (assert (= cfg.target "modal") "target must be modal")
    (assert (not (cb/isLocalExecution? cfg)) "modal is cloud execution")
    true)

fn testContainerExecutionEvaluation -> Bool
  (let [(cfg (cb/makeContainerConfig :docker "gemma-4-31b-it" 90 true))
        (res (cb/evaluateContainerRun cfg "TB4-SOLV-01" 0 4520 4 74.5 true))
        (receipt (cb/formatContainerReceipt res))]
    (assert res.passed "clean exit indicates pass")
    (assert (= res.exitCode 0) "exit code matches")
    (assert (stringContains? receipt ":target :docker") "receipt records docker target")
    (assert (stringContains? receipt ":status :verified") "receipt verifies nominal run")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(dockerCfg (cb/makeContainerConfig :docker "gemma-4-31b-it" 90 true))
        (failedRes (cb/evaluateContainerRun dockerCfg "TB4-001" 1 12000 6 0.0 false))]
    (refute (not (cb/isLocalExecution? dockerCfg)) "docker target must not be classified as remote")
    (refute failedRes.passed "failed return code must not pass")
    (refute (stringContains? (cb/formatContainerReceipt failedRes) ":status :verified") "failed run must not be formatted as verified")
    true)

fn runTests -> Bool
  (do
    (testContainerConfigDocker)
    (testContainerConfigModal)
    (testContainerExecutionEvaluation)
    (testDualPolarityRefutations)
    true)
