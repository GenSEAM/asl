(module aslGateway/tests/cliPromptFailureTest
  :x [runTests]
  :i [(cliDispatch :a cli)])

fn ! runTests -> Bool
  (let [(root (optionOr (envGet "ROOT_DIR") "."))
        (stamp (stringFromInt64 (nowNs)))
        (goodDir (str "/tmp/asl-gw-promptFailure-good-" stamp))
        (badDir (str "/tmp/asl-gw-promptFailure-bad-" stamp))
        (missingRoot (str "/tmp/asl-gw-promptFailure-noRoot-" stamp))
        (_goodMade (dirCreate goodDir))
        (_badMade (dirCreate badDir))
        (good (cli/cliWritePromptDirFrom! root "agy" "prompt" false goodDir))
        (bad (cli/cliWritePromptDirFrom! missingRoot "agy" "prompt" false badDir))]
    (do
      (assert (ok? good) "agy prompt setup succeeds when the client grammar exists")
      (assert (fileExists? (str goodDir "/.agents/plugins/aslGateway/agents/aslGateway.md")) "successful setup wrote its prompt file")
      (assert (and (err? bad) (stringContains? (mt bad ((err e) e) ((ok _) "")) "/asl/grammar/clients.asn")) "agy prompt setup must return tool-loading errors instead of writing fallback configuration")
      (refute (fileExists? badDir) "failed setup removes its temp directory")
      (let [(_cleanup (pathRemove goodDir))] true)))
