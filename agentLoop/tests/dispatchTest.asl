(module asl/agentLoop/tests/dispatchTest
  :x [runTests])

fn ! runTests -> Bool
  (let [tmp (processRun "mktemp -d /tmp/asl-agent-dispatch.XXXXXX")
        root (stringTrim tmp.stdout)
        repo (resultOr (realPath ".") ".")
        layout (processRun (str "mkdir -p " root "/asl && ln -s " repo "/asl/agentLoop " root "/asl/agentLoop && ln -s " repo "/asl/grammar " root "/asl/grammar"))
        main (str repo "/asl/agentLoop/main.asl")
        host (str repo "/asl/host/out/asl-host")
        proc (processRun (str "ASL_ROOT_DIR=" root " " host " run " main " '(:agent :task \"dispatch smoke\" :dryRun true :root \"" root "\")'"))
        output proc.stdout
        relativeProc (processRun (str "cd " root " && ASL_ROOT_DIR=" root " " host " run " main " '(:agent :task \"relative workspace\" :dryRun true :root \"" root "\")'"))
        relativeOutput relativeProc.stdout
        removed (pathRemove root)]
    (do
      (assert (= tmp.exitCode 0) "temporary workspace created")
      (assert (= layout.exitCode 0) "target workspace has the agent and grammar modules")
      (assert (fileExists? host) "stage-0 host is available")
      (assert (= proc.exitCode 0) "self-hosted agent entry point exits successfully")
      (assert (stringContains? output "(:dryRunReceipt") "self-hosted agent entry point returns its dry-run receipt")
      (assert (stringContains? output "Task: dispatch smoke") "receipt preserves the requested task")
      (assert (= relativeProc.exitCode 0) "self-hosted entry point runs from the workspace directory")
      (assert (stringContains? relativeOutput "(:dryRunReceipt") "workspace-relative invocation returns a receipt")
      (assert (ok? removed) "temporary workspace removed")
      true))
