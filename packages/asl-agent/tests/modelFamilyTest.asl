(module aslAgent/tests/modelFamilyTest
  :x [runTests]
  :i [(aslAgent/runLoop :a rl)])

; (:m :ref GRADER-SAME-MODEL-ALIAS :do "a Kimi-written unit served as k3.1-pro and graded by the same model served as moonshotai/Kimi-K3.1-Pro must compare equal, so specCheckRun! compares modelFamily names, not raw served names")
fn runTests -> Bool
  (do
    (assert (= (rl/modelFamily "k3.1-pro") "k3.1-pro")
      "modelFamily of k3.1-pro is k3.1-pro")
    (assert (= (rl/modelFamily "moonshotai/Kimi-K3.1-Pro") "k3.1-pro")
      "modelFamily of moonshotai/Kimi-K3.1-Pro is k3.1-pro")
    (assert (= (rl/modelFamily "kimi-k3.1-pro") "k3.1-pro")
      "modelFamily of kimi-k3.1-pro is k3.1-pro")
    (assert (= (rl/modelFamily "deepseek-ai/DeepSeek-V4.1-Flash-1017") "deepseek-v4.1-flash-1017")
      "modelFamily of deepseek-ai/DeepSeek-V4.1-Flash-1017 is deepseek-v4.1-flash-1017")
    (assert (not (= (rl/modelFamily "k3.1-pro") (rl/modelFamily "deepseek-v4.1-flash-1017")))
      "modelFamily of k3.1-pro differs from deepseek-v4.1-flash-1017")
    true)
