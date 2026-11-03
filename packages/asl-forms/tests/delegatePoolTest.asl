(module asl-forms/tests/delegatePoolTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (asl/agentLoop/pool :a pl) (asl/agentLoop/main :a m)])

; (:m :ref LEON-POOL-WIRE :do "an (:agent :pool (...)) step routes to the pool: its (:task ...) elements become (:agent :task ...) forms and the pool's one (:poolReceipt ...) line comes back as the step receipt; the runner here is asl/agentLoop/pool poolMainWith! in-process with a fake task runner, so no binary is spawned and no model is called")

fn ctx -> d/DelegateCtx
  (d/DelegateCtx :rootDir "/" :binDir "/" :wsDir "/")

fn ! fakeTask! repoRoot: String t: pl/PoolTask -> m/MainResult
  (m/MainResult :stdout "(:agentReceipt :status :ok :phases () :unbacked 0)" :exitCode 0)

fn ! poolRunner! forms: (List String) -> d/Spawned
  (let [(res (pl/poolMainWith! forms "/" "/" (pl/defaultLimits) fakeTask!))]
    (d/Spawned :code res.exitCode :out res.stdout :errText "" :failure ""))

; (:m :ref WALL-GRACEFUL :do "a pool child killed at its deadline comes back as ERR_AGENT_TIMEOUT; any other spawn failure stays ERR_AGENT_DISPATCH")
fn ! timeoutRunner! forms: (List String) -> d/Spawned
  (d/Spawned :code -1 :out "" :errText "" :failure (d/timeoutText (list "leon" "pool") 5))

fn ! spawnFailRunner! forms: (List String) -> d/Spawned
  (d/Spawned :code -1 :out "" :errText "" :failure "procSpawnv: no such file: leon")

fn step owns2: String -> String
  (str "(:agent :pool ((:task \"first (one)\" :root \"/tmp/delegatePoolA\" :owns (\"a.txt\")) (:task \"second\" :root \"/tmp/delegatePoolA\" :owns (\"" owns2 "\"))))")

fn ! runTests -> Bool
  (let [(forms (d/poolForms (step "b.txt")))
        (okOut (d/poolStepWith (ctx) 3 (mapEmpty) (step "b.txt") poolRunner!))
        (waited (d/poolStepWith (ctx) 4 (mapEmpty) (step "a.txt") poolRunner!))
        (bad (d/poolStepWith (ctx) 5 (mapEmpty) "(:agent :pool ())" poolRunner!))
        (late (d/poolStepWith (ctx) 6 (mapEmpty) (step "b.txt") timeoutRunner!))
        (unspawned (d/poolStepWith (ctx) 7 (mapEmpty) (step "b.txt") spawnFailRunner!))]
    (do
      (assert (d/poolRoute? "agent" (step "b.txt")) "an agent step with a :pool list routes to the pool")
      (assert (not (d/poolRoute? "agent" "(:agent :task \"t\" :pool-ish 1)")) "an ordinary agent step does not")
      (assert (not (d/poolRoute? "search" (step "b.txt"))) "only the agent op routes")
      (assert (match forms ((ok fs) (= (listLength fs) 2)) ((err _) false)) "two task forms are read, a ( inside a string is not a list")
      (assert (match forms ((ok fs) (listAll? (fn [(f String)] -> Bool (stringStartsWith? f "(:agent :task ")) fs)) ((err _) false)) "each (:task ...) becomes an (:agent :task ...) form")
      (assert (stringContains? okOut.line ":op \"agent\" :status \"ok\" :pool true :receipt (:poolReceipt :tasks 2 :admitted 2 :lanes 1 :ok 2 ") (str "a two-task pool step returns one pool receipt: " okOut.line))
      (assert (= (listLength (stringSplit okOut.line "(:slot ")) 3) "the receipt carries two slots")
      (assert (= okOut.errCount 0) "an all-ok pool step counts no error")
      (assert (stringContains? waited.line ":status \"ok\" :pool true :receipt (:poolReceipt :tasks 2 :admitted 2 ") (str "an overlapping pair is admitted, the second waiting: " waited.line))
      (assert (stringContains? waited.line "(:slot :idx 1 :lane 0 ") "the waiting task shares the first one's lane")
      (assert (stringContains? waited.line ":waitedFor (0) ") "the waiting slot names the task it waited for")
      (assert (stringContains? bad.line "ERR_POOL_FORM") "an empty :pool list is rejected")
      (assert (and (stringContains? late.line ":error-code \":ERR_AGENT_TIMEOUT\"") (not (stringContains? late.line "ERR_AGENT_DISPATCH"))) (str "a child killed at its deadline is a timeout: " late.line))
      (assert (stringContains? unspawned.line ":error-code \":ERR_AGENT_DISPATCH\"") (str "a child that never started stays a dispatch failure: " unspawned.line))
      true))
