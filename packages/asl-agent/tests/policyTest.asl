(module aslAgent/policyTest :x [testL0AskMode testL1GuardedMode testL2FullautoMode testSandboxTraversalRejections runTests] :i [(policy :a pol)])

"run: (run-tests)"

fn testL0AskMode -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (rRead (pol/checkAutonomyPermission "read" "/workspace/src/app.asl" m (pol/levelAsk))) (rTest (pol/checkAutonomyPermission "test" "/workspace/tests/app-test.asl" m (pol/levelAsk))) (rWrite (pol/checkAutonomyPermission "write" "/workspace/src/app.asl" m (pol/levelAsk))) (rExec (pol/checkAutonomyPermission "exec" "/workspace/bin/run" m (pol/levelAsk)))] (assert rRead.silent "L0 read is silent") (assert rTest.silent "L0 test is silent") (assert (not rWrite.silent) "L0 write prompts user") (assert (not rExec.silent) "L0 exec prompts user") true)

fn testL1GuardedMode -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (rRead (pol/checkAutonomyPermission "read" "/workspace/src/app.asl" m (pol/levelGuarded))) (rTest (pol/checkAutonomyPermission "test" "/workspace/tests/app-test.asl" m (pol/levelGuarded))) (rWrite (pol/checkAutonomyPermission "write" "/workspace/src/app.asl" m (pol/levelGuarded))) (rExec (pol/checkAutonomyPermission "exec" "/workspace/bin/run" m (pol/levelGuarded)))] (assert rRead.silent "L1 read is silent") (assert rTest.silent "L1 test is silent") (assert (not rWrite.silent) "L1 write prompts user") (assert (not rExec.silent) "L1 exec prompts user") true)

fn testL2FullautoMode -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (rRead (pol/checkAutonomyPermission "read" "/workspace/src/app.asl" m (pol/levelAuto))) (rWrite (pol/checkAutonomyPermission "write" "/workspace/src/app.asl" m (pol/levelAuto))) (rExec (pol/checkAutonomyPermission "exec" "/workspace/bin/run" m (pol/levelAuto)))] (assert rRead.silent "L2 read is silent") (assert rWrite.silent "L2 write is silent") (assert rExec.silent "L2 exec is silent") true)

fn testSandboxTraversalRejections -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (rTrav (pol/checkAutonomyPermission "read" "/workspace/../etc/passwd" m (pol/levelAuto))) (rSys (pol/checkAutonomyPermission "read" "/etc/shadow" m (pol/levelAuto)))] (assert (not rTrav.allowed) "traversal is rejected") (assert (not rSys.allowed) "system file access is rejected") true)

fn runTests -> Bool
  (do (testL0AskMode) (testL1GuardedMode) (testL2FullautoMode) (testSandboxTraversalRejections) true)
