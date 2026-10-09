(module aslHarness/preMortem :x [ConsequenceRisk PreMortemVerdict evaluatePreMortem generateFalsificationTrigger] :i [])

(schema ConsequenceRisk (:f description Str) (:f hopCount I64) (:f falsificationTrigger Str) (:f severity Str) (:f isGrounded Bool))

(schema PreMortemVerdict (:f passed Bool) (:f consequences (List ConsequenceRisk)) (:f blockedReasons (List Str)))

(schema PreMortemAcc (:f evaluated (List ConsequenceRisk)) (:f reasons (List Str)))

fn generateFalsificationTrigger riskName: Str targetFile: Str assertionCondition: Str -> Str
  (str "asl test " targetFile " --assert \"" riskName ":" assertionCondition "\"")

fn evaluatePreMortem actionDescription: Str risks: (List ConsequenceRisk) maxHops: I64 -> PreMortemVerdict
  (let [(effectiveMax (if (> maxHops 2) 2 (if (< maxHops 0) 0 maxHops))) (initialAcc (PreMortemAcc :evaluated (list) :reasons (list))) (finalAcc (fold (fn [(acc PreMortemAcc) (r ConsequenceRisk)] -> PreMortemAcc (let [(desc r.description) (hops r.hopCount) (trig r.falsificationTrigger) (sev r.severity) (initGrounded r.isGrounded) (exceedsCeiling (> hops effectiveMax)) (missingTrigger (stringEmpty? trig)) (isCritical (= sev "critical")) (unanchored (not initGrounded)) (nowGrounded (and (not exceedsCeiling) (and (not missingTrigger) initGrounded))) (evalRisk (ConsequenceRisk :description desc :hopCount hops :falsificationTrigger trig :severity sev :isGrounded nowGrounded)) (r1 (if exceedsCeiling (listAppend acc.reasons (list (str "Speculation ceiling exceeded for '" desc "': hop-count " (stringFromInt64 hops) " exceeds ceiling " (stringFromInt64 effectiveMax)))) acc.reasons)) (r2 (if missingTrigger (listAppend r1 (list (str "Missing falsification trigger for consequence: '" desc "'"))) r1)) (r3 (if isCritical (listAppend r2 (list (str "Critical unmitigated consequence risk: '" desc "'"))) r2)) (r4 (if (and unanchored (not exceedsCeiling)) (listAppend r3 (list (str "Ungrounded consequence risk: '" desc "'"))) r3))] (PreMortemAcc :evaluated (listAppend acc.evaluated (list evalRisk)) :reasons r4))) initialAcc risks)) (allReasons finalAcc.reasons) (passed (= (listLength allReasons) 0))] (PreMortemVerdict :passed passed :consequences finalAcc.evaluated :blockedReasons allReasons))
