(module asl-gateway/tests/cockpitLiveTest
  :x [testCockpitEndpoints! runTests]
  :i [(aslGateway/cockpit :a ck) (localTime :a lt) (asl-tools/fleet/run :a run)])

; (:m :ref MAINFIX1-COCKPITPORT-20261018 :do "ported off the curl/live-daemon design (MAINFIX1-COCKPITSPLIT-20261018, since reverted off frozen.asn per review) onto cockpitHandlerTest.asl's own in-process pattern: call each cockpit handler directly against a synthetic CockpitEnv/GatewayStatus over a throwaway /tmp fixture tree, no daemon, no curl, no network. Keeps every original assertion's intent (vitalityScore+stages present, daemons list names asl-gateway, totalTasks present, decisionsCount present) while reading them off the handler's own CockpitResponse.body instead of a curl exit+stdout pair; a decision and a task fixture file make totalTasks/decisionsCount reflect a real, controlled count (1 each) rather than the vitality-style null/0 fallback a rootEnv with no bin/asl would otherwise give every field")
fn testCockpitEndpoints! -> Bool
  (let [(root "/tmp/mainfix1CockpitLiveFixture")
        (clean (run/runOneLimited (run/job (list "rm" "-rf" root) "." (run/childEnv (list))) (run/limits 60 4)))
        (madeDecisions (dirCreate (str root "/.asl/mem/decisions")))
        (madeTasks (dirCreate (str root "/.asl/mem/tasks")))
        (wroteDecision (fileWrite (str root "/.asl/mem/decisions/D1.asn") "(:decision :d1)"))
        (wroteTask (fileWrite (str root "/.asl/mem/tasks/T1.asn") "(:task :t1)"))
        (env (ck/CockpitEnv :rootEnv (some root) :cwd root :calibrationEnv (none) :zone (lt/utcZone) :platform "darwin"))
        (status (ck/GatewayStatus :pid 4242 :version "mainfix1" :diskVersion "mainfix1" :stale false :inFlight 0 :draining false :updates 0))
        (vitPair (ck/serveCockpitVitalityApi! (ck/emptyIntelCache) 0.0 env))
        (vitResp (pairSecond vitPair))
        (daemonsResp (ck/serveCockpitDaemonsApi status.pid 9765 status))
        (tasksResult (ck/serveCockpitTasksApi! env))
        (memResult (ck/serveCockpitMemApi! env))
        (tasksResp (resultOr tasksResult (ck/CockpitResponse :status 500 :headers (list) :body "")))
        (memResp (resultOr memResult (ck/CockpitResponse :status 500 :headers (list) :body "")))]
    (do
      (assert (ok? madeDecisions) "decisions fixture dir created")
      (assert (ok? madeTasks) "tasks fixture dir created")
      (assert (ok? wroteDecision) "decision fixture file written")
      (assert (ok? wroteTask) "task fixture file written")

      (assert (= vitResp.status 200) "Cockpit vitality endpoint returns 200")
      (assert (stringContains? vitResp.body "\"vitalityScore\"") "Cockpit vitality returns vitalityScore")
      (assert (stringContains? vitResp.body "\"stages\"") "Cockpit vitality returns stages")

      (assert (= daemonsResp.status 200) "Cockpit daemons endpoint returns 200")
      (assert (stringContains? daemonsResp.body "\"daemons\"") "Cockpit daemons returns daemons list")
      (assert (stringContains? daemonsResp.body "asl-gateway") "Cockpit daemons lists asl-gateway")

      (assert (ok? tasksResult) "Cockpit tasks endpoint succeeds")
      (assert (stringContains? tasksResp.body "\"totalTasks\"") "Cockpit tasks returns totalTasks")
      (assert (stringContains? tasksResp.body "\"totalTasks\": 1") "Cockpit tasks counts the fixture task")

      (assert (ok? memResult) "Cockpit mem endpoint succeeds")
      (assert (stringContains? memResp.body "\"decisionsCount\"") "Cockpit mem returns decisionsCount")
      (assert (stringContains? memResp.body "\"decisionsCount\": 1") "Cockpit mem counts the fixture decision")
      true))

fn ! runTests -> Bool
  (testCockpitEndpoints!)
