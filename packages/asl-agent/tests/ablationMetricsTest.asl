(module aslAgent/ablationMetricsTest :x [testFeedbackTokenAblation testAutonomyFrictionAblation testTuiFoldingAblation runTests] :i [(feedback :a fb) (policy :a pol) (tui :a tui)])

fn testFeedbackTokenAblation -> Bool
  (let [(verboseMsg "Certainly! I'd be happy to help with that. Please let me know if you need anything else. We will now update src/app.asl.") (cleanMsg (fb/stripPoliteFluff verboseMsg)) (verboseToks (/ (stringLength verboseMsg) 4)) (cleanToks (/ (stringLength cleanMsg) 4))] (assert (< cleanToks verboseToks) "clean tokens < verbose tokens") (assert (> verboseToks 25) "verbose tokens > 25") true)

fn testAutonomyFrictionAblation -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (rRead (pol/checkAutonomyPermission "read" "/workspace/src/app.asl" m (pol/levelGuarded))) (rWrite (pol/checkAutonomyPermission "write" "/workspace/src/app.asl" m (pol/levelGuarded)))] (assert rRead.silent "read must be silent") (assert (not rWrite.silent) "write must not be silent") true)

fn testTuiFoldingAblation -> Bool
  (let [(folding (tui/formatToolCall "patch" "src/app.asl#entry" "applied (<50us)"))] (assert (stringContains? folding "[>] [patch]") "folding contains marker") (assert (not (stringContains? folding "\n")) "folding single line") true)

fn runTests -> Bool
  (do (assert (testFeedbackTokenAblation) "test-feedback-token-ablation must pass") (assert (testAutonomyFrictionAblation) "test-autonomy-friction-ablation must pass") (assert (testTuiFoldingAblation) "test-tui-folding-ablation must pass") true)
