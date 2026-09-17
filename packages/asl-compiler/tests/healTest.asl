(module asl-compiler/tests/healTest
  :d "Unit tests for autonomous self-healing compiler bridge and candidate patch synthesis under ADR D97."
  :x [testSynthesizePatches
      testTransactionRollback
      testCircuitBreakerCeiling
      testRollbackRecord
      runTests]
  :i [(heal :a h)
      (asl-ir/patch :a patch)])

(df testSynthesizePatches [] -> Bool
  (:d "Asserts synthesis of various diagnostic error patches.")
  (let [(pImp (h/synthesizeHealPatch "ERR_MISSING_IMPORT" "pkg/a" "imports" "[]" "(foo :a f)"))
        (pMatch (h/synthesizeHealPatch "ERR_UNHANDLED_VARIANT" "pkg/b" "fnB" "(mt x ((a) 1))" "((b) 2)"))
        (pType (h/synthesizeHealPatch "ERR_TYPE_MISMATCH" "pkg/c" "fnC" "Str" "Int64"))
        (pExp (h/synthesizeHealPatch "ERR_UNEXPORTED_SYMBOL" "pkg/d" "exports" "[:x [x]]" "y"))
        (pUnknown (h/synthesizeHealPatch "ERR_RANDOM" "pkg/e" "fnE" "old" "new"))]
    (assert (option-some? pImp) "missing import patch synthesized")
    (assert (option-some? pMatch) "unhandled variant patch synthesized")
    (assert (option-some? pType) "type mismatch patch synthesized")
    (assert (option-some? pExp) "unexported symbol patch synthesized")
    (assert (option-none? pUnknown) "unknown error produces none")
    (refute (option-none? pImp) "refute none for import")
    (refute (option-none? pMatch) "refute none for match")
    (refute (option-none? pType) "refute none for type")
    (refute (option-none? pExp) "refute none for export")
    (refute (option-some? pUnknown) "refute some for unknown")
    true))

(df testTransactionRollback [] -> Bool
  (:d "Asserts transactional rollback upon invalid patch application.")
  (let [(src "(module pkg/test :x [foo])\n\n(df foo [] -> Int64 1)\n")
        (badOp (patch/makePatchOpReplace "unknownSymbol" "body" "old" "new"))
        (badPatch (patch/makeAstPatch "bad" "pkg/test" (none) (none) (list badOp)))
        (res (h/applyHealTransaction src badPatch))]
    (refute (.-success res) "bad patch fails")
    (assert (.-isRolledBack res) "transaction rolled back")
    (assert (== (.-patchedSource res) src) "source preserved")
    (refute (== (.-errorMessage res) "") "error message present")
    true))

(df testCircuitBreakerCeiling [] -> Bool
  (:d "Asserts circuit breaker bounds retry attempts to max 3.")
  (let [(a1 (h/canRetryHeal 1 3))
        (a2 (h/canRetryHeal 2 3))
        (a3 (h/canRetryHeal 3 3))
        (a4 (h/canRetryHeal 4 3))]
    (assert a1 "attempt 1 valid")
    (assert a2 "attempt 2 valid")
    (assert a3 "attempt 3 valid")
    (refute a4 "attempt 4 rejected")
    true))

(df testRollbackRecord [] -> Bool
  (:d "Asserts creation of rollback journal record.")
  (let [(inv (patch/makeAstPatch "inv" "pkg/m" (none) (none) (list)))
        (rec (h/createRollbackJournalEntry "p-1" "f.asl" "pkg/m" "r1" "r2" inv 12345))]
    (assert (== (.-patchId rec) "p-1") "patch id matches")
    (assert (== (.-targetFile rec) "f.asl") "target file matches")
    (assert (== (.-preRoot rec) "r1") "pre root matches")
    (assert (== (.-postRoot rec) "r2") "post root matches")
    (assert (== (.-timestamp rec) 12345) "timestamp matches")
    (refute (== (.-preRoot rec) (.-postRoot rec)) "roots differ")
    true))

(df runTests [] -> Bool
  (and (testSynthesizePatches)
  (and (testTransactionRollback)
  (and (testCircuitBreakerCeiling)
       (testRollbackRecord)))))
