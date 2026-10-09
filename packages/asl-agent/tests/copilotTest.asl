(module aslAgent/copilotTest :x [testPointerDereference! testStagingLifecycle testIntentRecordingQuerying testTraceVerification! runTests] :i [(copilot :a cop)])

fn testPointerDereference! -> Bool
  (let [(ptr (cop/makePointer "b3-dom-01" (cop/ptrDom) "Login form DOM tree" "sha256:abcd")) (fact (cop/dereferencePointer! ptr "submit_button_visible"))] (assert (>= (stringLength fact) 20) "fact length >= 20") (assert (not (stringContains? fact "error")) "fact must not contain error") true)

fn testStagingLifecycle -> Bool
  (let [(prop (cop/makeProposal "branch-alpha" "decisions.asn" "(:dec :id 1)")) (path (cop/stageProposal prop)) (committed (cop/commitStagedProposal prop))] (assert (>= (stringLength path) 15) "path length >= 15") (assert committed.isCommitted "proposal is committed") true)

fn testIntentRecordingQuerying -> Bool
  (let [(rec (cop/intentRecord "decision" "dec:001" "ASL Native" "docs/ADR.md:1")) (qry (cop/intentQuery "dec:001" "fulfills"))] (assert (>= (stringLength rec) 20) "rec length >= 20") (assert (>= (stringLength qry) 20) "qry length >= 20") true)

fn testTraceVerification! -> Bool
  (do (let [(res (fileRead ".asl/mem/intent.asn")) (tv (cop/traceVerify! "eddie-run")) (un (println (str "FILE: " res " TV: " tv)))] (assert tv "trace verify eddie-run") (assert (not (cop/traceVerify! "non-existent-symbol")) "trace verify non-existent fails") true))

fn ! runTests -> Bool
  (do (assert (testPointerDereference!) "test-pointer-dereference must pass") (assert (testStagingLifecycle) "test-staging-lifecycle must pass") (assert (testIntentRecordingQuerying) "test-intent-recording-querying must pass") (assert (testTraceVerification!) "test-trace-verification must pass") true)
