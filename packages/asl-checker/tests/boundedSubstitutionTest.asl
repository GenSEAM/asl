(module asl/packages/asl-checker/tests/boundedSubstitutionTest :x [buildVarChain testResolveNonVariable testResolveTransitiveChain testBoundedMetavariableCutoff testResolveVarSubstRecFuel testResolveCycleTermination testCheckerUnifySuiteExecution! runTests] :i [(../src/types :a ty) (../src/unify :a u)])

fn buildVarChain n: Int64 target: ty/Type -> (Map Int64 ty/Type)
  (fold (fn [(s (Map Int64 ty/Type)) (i Int64)] -> (Map Int64 ty/Type) (if (= i n) (mapSet s i target) (mapSet s i (ty/tyVar (+ i 1) "any")))) (mapEmpty) (range 1 (+ n 1)))

fn testResolveNonVariable -> Bool
  (let [(i64 (ty/tyCon "Int64" (list) (none) (none))) (strTy (ty/tyCon "String" (list) (none) (none))) (s0 (mapEmpty))] (assert (u/typeEqual? (u/resolveVarSubst s0 i64) i64) "Direct return on Int64 type") (refute (u/typeEqual? (u/resolveVarSubst s0 i64) strTy) "Int64 does not resolve to String") true)

fn testResolveTransitiveChain -> Bool
  (let [(i64 (ty/tyCon "Int64" (list) (none) (none))) (strTy (ty/tyCon "String" (list) (none) (none))) (v1 (ty/tyVar 1 "any")) (v2 (ty/tyVar 2 "any")) (v3 (ty/tyVar 3 "any")) (s1 (mapSet (mapEmpty) 1 v2)) (s2 (mapSet s1 2 v3)) (s3 (mapSet s2 3 i64))] (assert (u/typeEqual? (u/resolveVarSubst s3 v1) i64) "v1 resolves through v2 and v3 to Int64") (refute (u/typeEqual? (u/resolveVarSubst s3 v1) strTy) "v1 does not resolve to String") (refute (u/typeEqual? (u/resolveVarSubst s3 v1) v2) "v1 does not stop at intermediate variable v2") (refute (u/typeEqual? (u/resolveVarSubst s3 v1) v3) "v1 does not stop at intermediate variable v3") true)

fn testBoundedMetavariableCutoff -> Bool
  (let [(i64 (ty/tyCon "Int64" (list) (none) (none))) (v1 (ty/tyVar 1 "any")) (v101 (ty/tyVar 101 "any")) (s150 (buildVarChain 150 i64)) (s50 (buildVarChain 50 i64)) (res150 (u/resolveVarSubst s150 v1)) (res50 (u/resolveVarSubst s50 v1))] (assert (u/typeEqual? res50 i64) "50-hop chain resolves fully to Int64 within 100 fuel") (refute (u/typeEqual? res50 v1) "50-hop chain does not stop at v1") (assert (u/typeEqual? res150 v101) "150-hop chain is strictly bounded at 100 fuel steps, stopping at v101") (refute (u/typeEqual? res150 i64) "150-hop chain must not run 5000 steps to reach Int64") true)

fn testResolveVarSubstRecFuel -> Bool
  (let [(i64 (ty/tyCon "Int64" (list) (none) (none))) (v1 (ty/tyVar 1 "any")) (v6 (ty/tyVar 6 "any")) (s10 (buildVarChain 10 i64))] (assert (u/typeEqual? (u/resolveVarSubstRec s10 v1 100) i64) "resolveVarSubstRec with positive fuel resolves target") (assert (u/typeEqual? (u/resolveVarSubstRec s10 v1 0) v1) "resolveVarSubstRec with 0 fuel returns current type without stepping") (refute (u/typeEqual? (u/resolveVarSubstRec s10 v1 0) i64) "0 fuel must not resolve substitution") (assert (u/typeEqual? (u/resolveVarSubstRec s10 v1 5) v6) "resolveVarSubstRec with 5 fuel stops at v6") (refute (u/typeEqual? (u/resolveVarSubstRec s10 v1 5) i64) "5 fuel must not reach terminal Int64 on 10-hop chain") true)

fn testResolveCycleTermination -> Bool
  (let [(v1 (ty/tyVar 1 "any")) (v2 (ty/tyVar 2 "any")) (i64 (ty/tyCon "Int64" (list) (none) (none))) (sSelf (mapSet (mapEmpty) 1 v1)) (sCycle (mapSet (mapSet (mapEmpty) 1 v2) 2 v1))] (assert (u/typeEqual? (u/resolveVarSubst sSelf v1) v1) "Self cycle 1 -> 1 terminates with v1") (refute (u/typeEqual? (u/resolveVarSubst sSelf v1) i64) "Self cycle 1 -> 1 does not produce unrelated concrete type") (let [(resCycle (u/resolveVarSubst sCycle v1))] (assert (or (u/typeEqual? resCycle v1) (u/typeEqual? resCycle v2)) "Mutual cycle 1 -> 2 -> 1 terminates safely within fuel bounds") (refute (u/typeEqual? resCycle i64) "Mutual cycle 1 -> 2 -> 1 does not produce unrelated concrete type")) true)

fn testCheckerUnifySuiteExecution! -> Bool
  (let [(res (processRun "bin/asl test asl/packages/asl-checker/tests/unify_test.asl")) (code res.exitCode) (out res.stdout)] (assert (= code 0) "Checker unify_test suite must exit 0") (refute (!= code 0) "Checker unify_test suite must not fail") (assert (stringContains? out "assertion(s) executed") "unify_test must report assertions") (refute (stringContains? out " 0 assertion(s) executed") "unify_test assertions must be non-zero") true)

fn ! runTests -> Bool
  (do (assert (testResolveNonVariable) "testResolveNonVariable must pass") (assert (testResolveTransitiveChain) "testResolveTransitiveChain must pass") (assert (testBoundedMetavariableCutoff) "testBoundedMetavariableCutoff must pass") (assert (testResolveVarSubstRecFuel) "testResolveVarSubstRecFuel must pass") (assert (testResolveCycleTermination) "testResolveCycleTermination must pass") (assert (testCheckerUnifySuiteExecution!) "testCheckerUnifySuiteExecution must pass") true)
