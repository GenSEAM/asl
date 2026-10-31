(module asl/agentLoop/tests/stablePrefixTest
  :x [runTests]
  :i [(asl/agentLoop/journal :a jr)])

; (:m :ref LEON-STABLE-PREFIX :do "two sessions of the same card in different worktrees, with different tasks, bases and gates, share a byte-identical system prefix that covers the layers, ops, batch and pool rows; only the env layer, gates and base differ and come last")

fn commonLen a: String b: String lo: Int64 hi: Int64 -> Int64
  (if (>= lo hi)
    lo
    (let [mid (/ (+ lo hi 1) 2)]
      (if (stringStartsWith? b (optionOr (stringSlice a 0 mid) ""))
        (commonLen a b mid hi)
        (commonLen a b lo (- mid 1)))))

fn ! promptFor! root: String task: String base: String gates: (List String) -> String
  (match (jr/buildSystemPrompt (resultOr (realPath ".") ".") task root base gates (some 200000) false)
    ((ok p) p)
    ((err e) ""))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        a (promptFor! repo "Create hello.txt" "main" (list "true"))
        b (promptFor! (str repo "/asl") "Fix the parser bug in ring.py and run the suite" "sh/OTHER" (list "echo one" "echo two"))
        shorter (min (stringLength a) (stringLength b))
        common (commonLen a b 0 shorter)
        sharedHead (optionOr (stringSlice a 0 common) "")
        _ (fileWrite "/tmp/leonPrefixNumbers.txt" (str "common " (stringFromInt64 common) " lenA " (stringFromInt64 (stringLength a)) " lenB " (stringFromInt64 (stringLength b)) "\n"))]
    (do
      (assert (> shorter 0) "both prompts built")
      (assert (stringContains? sharedHead "(:ops ") "the common prefix covers the ops row")
      (assert (stringContains? sharedHead "(:batch ") "the common prefix covers the batch row")
      (assert (stringContains? sharedHead "(:pool ") "the common prefix covers the pool row")
      (assert (>= (* 100 common) (* 85 shorter)) "the common prefix covers at least 85 percent of the shorter system prompt")
      (assert (not (stringContains? a "(:task ")) "the task is not part of the system prompt, it is sent once in the user turn")
      ; (:m :ref L0-EXIT-CONTRACT :do "the prefix teaches only exit forms the loop runs: no (:outcome :abstained) or (:witness) literal, no shell report contract, one (:exit) row whose escalate carries :seen and :tried")
      (assert (not (stringContains? a "(:outcome ")) "the prefix names no (:outcome :abstained) form, which no op runs")
      (assert (not (stringContains? a "(:witness ")) "the prefix names no (:witness) form, which no op runs")
      (assert (not (stringContains? a "(:layer :id reply ")) "the shell report contract (done claimed unverified) is not in Leon's prefix")
      (assert (stringContains? sharedHead "(:exit (:done :when (written gatesPass))") "the common prefix carries the exit row and done ends on written plus green gates")
      (assert (stringContains? sharedHead "(:escalate :reason s :seen s :tried s :when (blocked gateUnrunnable outsideOwns sameFailure3 evidenceDeficit noProgress)") "escalate is licensed for every cause the loop can stop on, not only outsideOwns")
      true))
