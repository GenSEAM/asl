(module aslHarness/sufficiency :x [SufficiencyState SufficiencyReport evaluateSufficiency isSufficient?] :i [])

(enum SufficiencyState (:c suffComplete [] "All required criteria verified and complete") (:c suffPartial [] "Substantial portion complete but gaps remain") (:c suffInsufficient [] "Core criteria unfulfilled or failing"))

(schema SufficiencyReport (:f targetCount I64) (:f completedCount I64) (:f state SufficiencyState) (:f summary Str))

fn evaluateSufficiency targets: (List Str) completed: (List Str) -> SufficiencyReport
  (let [(total (listLength targets)) (done (listLength completed)) (st (cond ((= total 0) (suffComplete)) ((>= done total) (suffComplete)) ((> done 0) (suffPartial)) (true (suffInsufficient)))) (msg (if (>= done total) "All acceptance criteria verified." "Gaps remaining in verification criteria."))] (SufficiencyReport :targetCount total :completedCount done :state st :summary msg))

fn isSufficient? rep: SufficiencyReport -> Bool
  (mt rep.state ((suffComplete) true) ((suffPartial) false) ((suffInsufficient) false))
