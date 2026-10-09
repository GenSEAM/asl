(module asl-cli/tests/delegateCommandTest :x [runTests])

fn ! runTests -> Bool
  (let [(pwdRes (processRun "pwd -P"))
        (root (stringTrim pwdRes.stdout))
        (host (str root "/asl/host/out/asl-host"))
        (prefix (str "cd '" root "' && PATH=/usr/bin:/bin ASL_HOST='" host "' ./bin/asl "))
        (searchRes (processRun (str prefix "search")))
        (researchRes (processRun (str prefix "research")))
        (searchOut (str searchRes.stdout searchRes.stderr))
        (researchOut (str researchRes.stdout researchRes.stderr))]
    (do
      (assert (stringContains? searchOut "ERR_MISSING_ARG") "search reaches the delegate query validation without networking")
      (assert (not (stringContains? searchOut "asl-search binary or tool not found")) "search does not seek the deleted tool")
      (assert (stringContains? researchOut "ERR_MISSING_ARG") "research reaches the delegate topic validation without networking")
      (assert (not (stringContains? researchOut "asl-research binary or tool not found")) "research does not seek the deleted tool")))
  true
