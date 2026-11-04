(module aslAgent/tests/stablePrefixTest
  :x [runTests]
  :i [(aslAgent/journal :a jr) (asl-harness/launch :a lh)])

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

; (:m :ref L0-EXIT-CONTRACT :do "harness5 rendered for another client at a fixed date and platform, as asl launch renders it")
fn ! renderFor! repo: String client: String -> String
  (let [paths (lh/pathsFor repo (lh/runnerDisplay! repo))
        loaded (lh/loadSources paths "" (resultOr (fileReadString paths.clients) "") (resultOr (fileReadString paths.tools) ""))
        opts (lh/RenderOpts :cwd repo :client client :mode "implement" :core false :promptDir none :drop (list) :only (list)
                            :fills (list) :once false :platform "linux" :date "2026-01-02")]
    (match (lh/probe! repo)
      ((err e) "")
      ((ok probe) (match (lh/renderAsnFor loaded probe opts) ((ok text) text) ((err e) "")))))

fn keepsShellLayers? text: String -> Bool
  (and (stringContains? text "(:layer :id reply ")
       (and (stringContains? text "(:layer :id abstain ") (stringContains? text "(:layer :id breaker ")))

; (:m :ref L0-EXIT-CONTRACT :do "the stop signals the exit row names: each must be a decision string the loop source returns or records")
fn exitSignals -> (List String)
  (list "repeatFailure" "readStreak" "noWriteTurns" "wallBudget" "tokenBudget")

fn ! loopSource! -> String
  (str (resultOr (fileReadString "asl/packages/asl-agent/src/loop.asl") "") (resultOr (fileReadString "asl/packages/asl-agent/src/main.asl") "")
       (resultOr (fileReadString "asl/packages/asl-agent/src/runLoop.asl") ""))

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        a (promptFor! repo "Create hello.txt" "main" (list "true"))
        b (promptFor! (str repo "/asl") "Fix the parser bug in ring.py and run the suite" "sh/OTHER" (list "echo one" "echo two"))
        shorter (min (stringLength a) (stringLength b))
        common (commonLen a b 0 shorter)
        sharedHead (optionOr (stringSlice a 0 common) "")
        src (loopSource!)
        _ (fileWrite "/tmp/leonPrefixNumbers.txt" (str "common " (stringFromInt64 common) " lenA " (stringFromInt64 (stringLength a)) " lenB " (stringFromInt64 (stringLength b)) "\n"))]
    (do
      (assert (> shorter 0) "both prompts built")
      (assert (stringContains? sharedHead "(:ops ") "the common prefix covers the ops row")
      (assert (stringContains? sharedHead "(:batch ") "the common prefix covers the batch row")
      (assert (stringContains? sharedHead "(:pool ") "the common prefix covers the pool row")
      (assert (>= (* 100 common) (* 85 shorter)) "the common prefix covers at least 85 percent of the shorter system prompt")
      (assert (not (stringContains? a "(:task ")) "the task is not part of the system prompt, it is sent once in the user turn")
      ; (:m :ref L0-EXIT-CONTRACT :do "the prefix teaches only exit forms the loop runs: no (:outcome :abstained) or (:witness) literal, no shell report contract, one (:exit) row whose escalate carries :seen and :tried and preempts the loop stop signals; other clients keep the shell layers")
      (assert (not (stringContains? a "(:outcome ")) "the prefix names no (:outcome :abstained) form, which no op runs")
      (assert (not (stringContains? a "(:witness ")) "the prefix names no (:witness) form, which no op runs")
      (assert (not (stringContains? a "(:layer :id reply ")) "the shell report contract (done claimed unverified) is not in Leon's prefix")
      (assert (stringContains? sharedHead "(:exit (:done :when (written gatesPass))") "the common prefix carries the exit row and done ends on written plus green gates")
      (assert (stringContains? sharedHead (str "(:escalate :reason s :seen s :tried s :names (file receiptId) :when outsideOwns :preempts (" (stringJoin (exitSignals) " ") "))")) "escalate preempts the stop signals the loop itself ends a run on")
      (assert (listAll? (fn [s] (stringContains? src (str "\"" s "\""))) (exitSignals)) (str "every signal the exit row names is a string the loop source uses: " (stringJoin (filter (fn [s] (not (stringContains? src (str "\"" s "\"")))) (exitSignals)) " ")))
      (assert (stringContains? sharedHead "(:yields sameFailure3 (newHypothesis escalate))") "the third same failure yields a new hypothesis or an escalation, not escalation alone")
      (assert (not (stringContains? a "taskAsksCommit")) "no row teaches a commit on taskAsksCommit, which nothing computes")
      (assert (listAll? keepsShellLayers? (map (fn [c] (renderFor! repo c)) (list "claude" "codex" "agy"))) "claude, codex and agy renders keep reply, abstain and breaker")
      (assert (keepsShellLayers? (renderFor! repo "chat")) "the toolless chat render keeps reply, abstain and breaker")
      (assert (not (keepsShellLayers? (renderFor! repo "leon"))) "the leon render drops them")
      true))
