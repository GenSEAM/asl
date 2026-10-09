(module aslIntel/tests/contextBanditTest
  :x [RunTests runTests]
  :i [(preload :a pl)])

fn testContextBanditArbitration -> Bool
  (let [(armShallow (pl/determineContextRoutingBandit 1.2 false))
        (armDeepHighEntropy (pl/determineContextRoutingBandit 3.5 false))
        (armDeepRefactor (pl/determineContextRoutingBandit 1.0 true))
        (strShallow (pl/armToString armShallow))
        (strDeep (pl/armToString armDeepHighEntropy))]
    (assert (= strShallow "shallow-signature") "Low entropy routes to shallow signature")
    (assert (= strDeep "deep-callgraph") "High entropy routes to deep callgraph")
    (assert (= (pl/armToString armDeepRefactor) "deep-callgraph") "Refactoring flag forces deep callgraph")
    (refute (= strShallow "deep-callgraph") "Refutation: Low entropy must not route to deep callgraph")
    (refute (= strDeep "shallow-signature") "Refutation: High entropy must not route to shallow signature")
    true)

fn testContextBanditAdaptiveLearning -> Bool
  (let [(m0 (pl/makeContextBanditModel))
        (m1 (pl/updateBanditArmReward m0 (pl/armShallowSignature) 2.5 0.5))
        (m2 (pl/updateBanditArmReward m1 (pl/armDeepCallGraph) 0.2 0.5))
        (armAdaptiveAtBorder (pl/determineContextRoutingBanditAdaptive m2 2.6 false))
        (strAdaptive (pl/armToString armAdaptiveAtBorder))]
    (assert (= m0.pullCount 0) "Initial bandit model has 0 pulls")
    (assert (= m2.pullCount 2) "Bandit model has 2 pulls after updates")
    (assert (> m2.shallowWeight 1.5) "Shallow weight increased after high reward")
    (assert (< m2.deepWeight 0.8) "Deep weight decreased after low reward")
    (refute (< m2.shallowWeight 1.0) "Refutation: Shallow weight must not decrease on positive reward")
    (assert (= strAdaptive "shallow-signature") "Adaptive model overrides slight high-entropy prior when shallow has much higher learned weight")
    (refute (= strAdaptive "deep-callgraph") "Refutation: Deep arm must not win when its reward weight collapsed")
    true)

fn testBanditEpsilonDecay -> Bool
  (let [(m0 (pl/makeContextBanditModel))
        (mDecayed (pl/decayBanditEpsilon m0 0.5 0.05))
        (mFloor (pl/decayBanditEpsilon mDecayed 0.1 0.05))]
    (do
      (assert (> m0.epsilon 0.15) "Initial model has default exploration epsilon >= 0.2")
      (assert (< mDecayed.epsilon m0.epsilon) "Decayed epsilon is strictly less than initial epsilon")
      (assert (= mFloor.epsilon 0.05) "Epsilon decay respects minEpsilon floor 0.05")
      (refute (< mFloor.epsilon 0.05) "Refutation: Decayed epsilon must not breach minEpsilon floor")
      true))

fn runTests -> Bool
  (do
    (assert (testContextBanditArbitration) "testContextBanditArbitration passed")
    (assert (testContextBanditAdaptiveLearning) "testContextBanditAdaptiveLearning passed")
    (assert (testBanditEpsilonDecay) "testBanditEpsilonDecay passed")
    true)

fn RunTests -> Bool
  (runTests)
