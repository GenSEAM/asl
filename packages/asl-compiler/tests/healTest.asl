(module asl-compiler/tests/healTest :x [testSynthesizePatches testTransactionRollback testCircuitBreakerCeiling testRollbackRecord runTests] :i [(heal :a h) (asl-ir/patch :a patch)])

fn testSynthesizePatches -> Bool
  (let [(pImp (h/synthesizeHealPatch "ERR_MISSING_IMPORT" "pkg/a" "imports" "[]" "(foo :a f)")) (pMatch (h/synthesizeHealPatch "ERR_UNHANDLED_VARIANT" "pkg/b" "fnB" "(mt x ((a) 1))" "((b) 2)")) (pType (h/synthesizeHealPatch "ERR_TYPE_MISMATCH" "pkg/c" "fnC" "Str" "Int64")) (pExp (h/synthesizeHealPatch "ERR_UNEXPORTED_SYMBOL" "pkg/d" "exports" "[:x [x]]" "y")) (pUnknown (h/synthesizeHealPatch "ERR_RANDOM" "pkg/e" "fnE" "old" "new"))] (assert (some? pImp) "missing import patch synthesized") (assert (some? pMatch) "unhandled variant patch synthesized") (assert (some? pType) "type mismatch patch synthesized") (assert (some? pExp) "unexported symbol patch synthesized") (assert (none? pUnknown) "unknown error produces none") (refute (none? pImp) "refute none for import") (refute (none? pMatch) "refute none for match") (refute (none? pType) "refute none for type") (refute (none? pExp) "refute none for export") (refute (some? pUnknown) "refute some for unknown") true)

fn testTransactionRollback -> Bool
  (let [(src "(module pkg/test :x [foo])\n\n(fn foo [] -> Int64 1)\n") (badOp (patch/makePatchOpReplace "unknownSymbol" "body" "old" "new")) (badPatch (patch/makeAstPatch "bad" "pkg/test" (none) (none) (list badOp))) (res (h/applyHealTransaction src badPatch))] (refute res.success "bad patch fails") (assert res.isRolledBack "transaction rolled back") (assert (== res.patchedSource src) "source preserved") (refute (== res.errorMessage "") "error message present") true)

fn testCircuitBreakerCeiling -> Bool
  (let [(a1 (h/canRetryHeal 1 3)) (a2 (h/canRetryHeal 2 3)) (a3 (h/canRetryHeal 3 3)) (a4 (h/canRetryHeal 4 3))] (assert a1 "attempt 1 valid") (assert a2 "attempt 2 valid") (assert a3 "attempt 3 valid") (refute a4 "attempt 4 rejected") true)

fn testRollbackRecord -> Bool
  (let [(inv (patch/makeAstPatch "inv" "pkg/m" (none) (none) (list))) (rec (h/createRollbackJournalEntry "p-1" "f.asl" "pkg/m" "r1" "r2" inv 12345))] (assert (== rec.patchId "p-1") "patch id matches") (assert (== rec.targetFile "f.asl") "target file matches") (assert (== rec.preRoot "r1") "pre root matches") (assert (== rec.postRoot "r2") "post root matches") (assert (== rec.timestamp 12345) "timestamp matches") (refute (== rec.preRoot rec.postRoot) "roots differ") true)

fn runTests -> Bool
  (and (testSynthesizePatches) (and (testTransactionRollback) (and (testCircuitBreakerCeiling) (testRollbackRecord))))
