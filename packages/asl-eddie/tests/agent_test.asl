(module asl-eddie/test
  :d "Unit tests for asl-eddie autonomous agent: policy sandbox, triage, and ReAct loop."
  :x [main]
  :i [(policy :a pol) (triage :a tr) (agent :a ag)])

(df test-policy-sandbox [] -> Bool
  (let [(m (pol/make-manifest "/workspace" (list "/workspace/tree") "/tmp" false))
        (p1 (pol/check-permission "read" "/workspace/src/app.asl" m))
        (p2 (pol/check-permission "write" "/etc/passwd" m))
        (p3 (pol/check-permission "write" "/workspace/../escape" m))]
    (and (and (.-allowed p1)
              (not (.-allowed p2)))
         (not (.-allowed p3)))))

(df test-triage-collapse [] -> Bool
  (let [(ctx (tr/make-workspace-context "asl" "/workspace" true (list "asl")))
        (d1 (tr/triage-request "fix and test and refactor core" ctx))]
    (.-collapsed-single d1)))

(df test-agent-react-step [] -> Bool
  (let [(m (pol/make-manifest "/workspace" (list) "/tmp" false))
        (sess (ag/make-agent-session "inspect repo" m))
        (res (ag/step-agent sess "fs:read" "/workspace/src/app.asl" "dummy payload"))]
    (.-success res)))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Runs unit tests for asl-eddie agent suite."
  (if (and (and (test-policy-sandbox)
                (test-triage-collapse))
           (test-agent-react-step))
    (let [(u (println "asl-eddie agent tests passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "asl-eddie agent test failure"))]
      (err (other)))))
