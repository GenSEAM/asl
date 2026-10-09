(module asl-mesh/tests/descriptorTest
  :x [testShardDescriptor testStaticGateDescriptor testEventHookDescriptor testDefectCategoryDescriptor testSafetyPolicyDescriptor testExecutionAllowed runTests]
  :i [(asl-mesh/descriptor :a desc)])

fn testShardDescriptor -> Bool
  (let [(paths (list "asl/packages/asl-compiler" "asl/packages/asl-ir"))
        (s (desc/makeShardDescriptor "shard-compiler" "Core Compiler" paths "falsify" "verification" "google/gemma-4-31b-it:free" 0.55 "critical" "Logic flaws"))]
    (do
      (assert (= s.id "shard-compiler") "shard id is shard-compiler")
      (refute (!= s.id "shard-compiler") "refutes mismatched shard id")
      (assert (= s.intent "falsify") "intent is falsify")
      (assert (= s.attractor "verification") "attractor is verification")
      (assert (= (listLength s.paths) 2) "paths length is 2")
      (assert (desc/validateShardDescriptor s) "shard descriptor passes validation")
      (refute (not (desc/validateShardDescriptor s)) "refutes invalid shard descriptor")
      true))

fn testStaticGateDescriptor -> Bool
  (let [(gCmd (desc/makeStaticGateDescriptor "gates" "./bin/asl audit gates" "" "Core verification gates"))
        (gEval (desc/makeStaticGateDescriptor "evalGate" "" "(= (+ 40 2) 42)" "Pure ASL executable expression"))]
    (do
      (assert (= gCmd.id "gates") "cmd gate id is gates")
      (assert (desc/validateStaticGateDescriptor gCmd) "cmd gate is valid")
      (assert (= gEval.id "evalGate") "eval gate id is evalGate")
      (assert (desc/validateStaticGateDescriptor gEval) "eval gate is valid")
      (refute (not (desc/validateStaticGateDescriptor gEval)) "refutes invalid eval gate")
      true))

fn testEventHookDescriptor -> Bool
  (let [(h1 (desc/makeEventHookDescriptor "onCorroborated" "formulateVirtualFix" "Auto-formulate virtual fix"))
        (h2 (desc/makeEventHookDescriptor "onCheatingAlert" "quarantineAndLog" "Log and quarantine"))]
    (do
      (assert (= h1.event "onCorroborated") "event name matches")
      (assert (= h1.action "formulateVirtualFix") "action matches")
      (assert (= h2.event "onCheatingAlert") "cheating alert event matches")
      (assert (desc/validateEventHookDescriptor h1) "event hook passes validation")
      (refute (not (desc/validateEventHookDescriptor h1)) "refutes invalid event hook")
      true))

fn testDefectCategoryDescriptor -> Bool
  (let [(c (desc/makeDefectCategoryDescriptor "syntaxMalformation" "critical" "Unbalanced S-expressions or invalid AST forms"))]
    (do
      (assert (= c.id "syntaxMalformation") "category id matches")
      (assert (= c.severity "critical") "severity matches")
      (assert (desc/validateDefectCategoryDescriptor c) "category descriptor is valid")
      (refute (not (desc/validateDefectCategoryDescriptor c)) "refutes invalid category descriptor")
      true))

fn testSafetyPolicyDescriptor -> Bool
  (let [(pol (desc/makeSafetyPolicyDescriptor true true true true))]
    (do
      (assert pol.zeroLineNumbers "zero line numbers enabled")
      (assert pol.pureDyck1Only "pure dyck1 enabled")
      (assert pol.antiVacuity "anti-vacuity enabled")
      (assert pol.readOnlyProposals "read-only proposals enabled")
      (assert (desc/validateSafetyPolicyDescriptor pol) "safety policy is valid")
      (refute (not (desc/validateSafetyPolicyDescriptor pol)) "refutes invalid safety policy")
      true))

fn testExecutionAllowed -> Bool
  (do
    (assert (desc/isExecutionAllowed "system" "start") "system plane can start")
    (assert (desc/isExecutionAllowed "system" "stop") "system plane can stop")
    (assert (desc/isExecutionAllowed "system" "sweep") "system plane can sweep")
    (assert (not (desc/isExecutionAllowed "worker" "start")) "worker plane cannot start")
    (refute (desc/isExecutionAllowed "worker" "start") "refutes worker plane starting")
    (assert (not (desc/isExecutionAllowed "worker" "stop")) "worker plane cannot stop")
    (refute (desc/isExecutionAllowed "worker" "stop") "refutes worker plane stopping")
    (assert (desc/isExecutionAllowed "worker" "status") "worker plane can run status")
    true)

fn runTests -> Bool
  (do
    (assert (testShardDescriptor) "testShardDescriptor")
    (assert (testStaticGateDescriptor) "testStaticGateDescriptor")
    (assert (testEventHookDescriptor) "testEventHookDescriptor")
    (assert (testDefectCategoryDescriptor) "testDefectCategoryDescriptor")
    (assert (testSafetyPolicyDescriptor) "testSafetyPolicyDescriptor")
    (assert (testExecutionAllowed) "testExecutionAllowed")
    true)
