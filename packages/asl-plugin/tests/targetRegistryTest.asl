(module asl-plugin/tests/targetRegistryTest
  :d "Unit tests and D77 refutations for dynamic target registry and dispatch under ADR D93."
  :x [runTests testEmptyRegistry testRegisterTarget testDispatchSuccessful testDispatchUnregisteredError testTargetRegistryD77Refutations]
  :i [(targetRegistry :a tr) (ast :a a)])

(df testEmptyRegistry [] -> Bool
  :d "Verifies that an empty target registry has no targets and returns none on lookup."
  (let [(reg (tr/emptyTargetRegistry))
        (targets (tr/listRegisteredTargets reg))]
    (assert (list-empty? targets) "Empty registry has empty target list")
    (refute (not (list-empty? targets)) "Empty registry target list is refuted non-empty under D77")
    (assert (= (list-length targets) 0) "Empty registry has target count 0")
    (refute (> (list-length targets) 0) "Empty registry refutes positive target count under D77")
    (assert (not (tr/hasTarget? reg "wat")) "Empty registry does not have wat target")
    (refute (tr/hasTarget? reg "wat") "Empty registry refutes wat target presence under D77")
    (assert (not (tr/hasTarget? reg "c99")) "Empty registry does not have c99 target")
    (refute (tr/hasTarget? reg "c99") "Empty registry refutes c99 target presence under D77")
    (assert (option-none? (tr/lookupTarget reg "wat")) "Empty registry returns none on wat lookup")
    (refute (option-some? (tr/lookupTarget reg "wat")) "Empty registry refutes some on wat lookup under D77")
    true))

(df testRegisterTarget [] -> Bool
  :d "Verifies registering targets updates the registry with target metadata and emitters."
  (let [(reg (tr/emptyTargetRegistry))
        (mockWat (fn [(forms (List a/TopForm)) (opts (Map Str Str))] -> (Result Str Str)
                   (ok (str "wat-binary-size:" (string-from-int64 (list-length forms))))))
        (mockRust (fn [(forms (List a/TopForm)) (opts (Map Str Str))] -> (Result Str Str)
                    (ok "rust-codegen-success")))
        (reg1 (tr/registerTarget reg "wat" "WebAssembly Text format backend" mockWat))
        (reg2 (tr/registerTarget reg1 "rust" "Rust safe backend" mockRust))]
    (assert (tr/hasTarget? reg1 "wat") "reg1 has target wat")
    (refute (not (tr/hasTarget? reg1 "wat")) "reg1 refutes absence of wat target")
    (assert (not (tr/hasTarget? reg1 "rust")) "reg1 does not have target rust")
    (refute (tr/hasTarget? reg1 "rust") "reg1 refutes presence of rust target")
    (assert (= (list-length (tr/listRegisteredTargets reg1)) 1) "reg1 has exactly 1 target")
    (assert (tr/hasTarget? reg2 "wat") "reg2 has target wat")
    (refute (not (tr/hasTarget? reg2 "wat")) "reg2 refutes absence of wat target")
    (assert (tr/hasTarget? reg2 "rust") "reg2 has target rust")
    (refute (not (tr/hasTarget? reg2 "rust")) "reg2 refutes absence of rust target")
    (assert (= (list-length (tr/listRegisteredTargets reg2)) 2) "reg2 has exactly 2 targets")
    (assert (list-contains? (tr/listRegisteredTargets reg2) "wat") "reg2 list contains wat")
    (assert (list-contains? (tr/listRegisteredTargets reg2) "rust") "reg2 list contains rust")
    (refute (list-contains? (tr/listRegisteredTargets reg2) "unknown") "reg2 list refutes unknown target")
    (assert (option-some? (tr/lookupTarget reg2 "wat")) "lookup wat returns some")
    (refute (option-none? (tr/lookupTarget reg2 "wat")) "lookup wat refutes none")
    (assert (option-some? (tr/lookupTarget reg2 "rust")) "lookup rust returns some")
    (refute (option-none? (tr/lookupTarget reg2 "rust")) "lookup rust refutes none")
    true))

(df testDispatchSuccessful [] -> Bool
  :d "Verifies code generation dispatch to a registered target emitter."
  (let [(reg (tr/emptyTargetRegistry))
        (mockEmitter (fn [(forms (List a/TopForm)) (opts (Map Str Str))] -> (Result Str Str)
                       (ok (str "(module (func $main (result i32) (i32.const " (string-from-int64 (list-length forms)) ")))"))))
        (regWat (tr/registerTarget reg "wat" "Wasm backend" mockEmitter))
        (res (tr/dispatchTargetCodegen regWat "wat" (list) (map-empty)))]
    (assert (is-ok? res) "Dispatch to registered target succeeds")
    (refute (is-err? res) "Dispatch to registered target refutes error under D77")
    (mt res
      ((ok code)
       (do
         (assert (string-contains? code "(module") "Emitted code contains expected wat module")
         (refute (string-empty? code) "Emitted code is refuted empty under D77")
         (assert (= code "(module (func $main (result i32) (i32.const 0)))") "Emitted code matches expected output")
         true))
      ((err _) false))))

(df testDispatchUnregisteredError [] -> Bool
  :d "Verifies that dispatching to an unregistered target produces structured error."
  (let [(reg (tr/emptyTargetRegistry))
        (resWat (tr/dispatchTargetCodegen reg "wat" (list) (map-empty)))
        (resGo (tr/dispatchTargetCodegen reg "go" (list) (map-empty)))]
    (assert (is-err? resWat) "Dispatch to unregistered wat yields error")
    (refute (is-ok? resWat) "Dispatch to unregistered wat refutes ok under D77")
    (assert (is-err? resGo) "Dispatch to unregistered go yields error")
    (refute (is-ok? resGo) "Dispatch to unregistered go refutes ok under D77")
    (mt resWat
      ((ok _) false)
      ((err msgWat)
       (do
         (assert (= msgWat "unsupported-target: wat") "Error message matches expected format")
         (refute (string-empty? msgWat) "Error message refutes empty string under D77")
         (assert (string-contains? msgWat "unsupported-target: ") "Error message contains prefix")
         true)))
    (mt resGo
      ((ok _) false)
      ((err msgGo)
       (do
         (assert (= msgGo "unsupported-target: go") "Go error message matches expected format")
         (refute (string-empty? msgGo) "Go error message refutes empty string under D77")
         true)))))

(df testTargetRegistryD77Refutations [] -> Bool
  :d "Rigorous D77 refutations guarding against unregistered target invocation and registry anomalies."
  (let [(reg (tr/emptyTargetRegistry))
        (mock (fn [(forms (List a/TopForm)) (opts (Map Str Str))] -> (Result Str Str)
                (ok "valid-output")))
        (reg1 (tr/registerTarget reg "wat" "Wasm backend" mock))
        (targets (tr/listRegisteredTargets reg1))
        (resUnreg (tr/dispatchTargetCodegen reg1 "invalid-target-xyz" (list) (map-empty)))]
    (refute (list-empty? targets) "Targets list refutes empty after registration")
    (refute (not (= (list-length targets) 1)) "Targets count refutes anything other than 1")
    (refute (tr/hasTarget? reg1 "invalid-target-xyz") "Registry refutes presence of unregistered target")
    (refute (option-some? (tr/lookupTarget reg1 "invalid-target-xyz")) "Lookup refutes some for unregistered target")
    (refute (is-ok? resUnreg) "Dispatch refutes ok for unregistered target")
    (mt resUnreg
      ((ok _) false)
      ((err errMsg)
       (do
         (refute (not (= errMsg "unsupported-target: invalid-target-xyz")) "Error refutes mismatched diagnostic")
         (refute (= errMsg "") "Error message refutes empty string")
         true)))))

(df runTests [] -> Bool
  :d "Executes all targetRegistry unit tests and D77 refutations."
  (do
    (assert (testEmptyRegistry) "testEmptyRegistry must pass")
    (assert (testRegisterTarget) "testRegisterTarget must pass")
    (assert (testDispatchSuccessful) "testDispatchSuccessful must pass")
    (assert (testDispatchUnregisteredError) "testDispatchUnregisteredError must pass")
    (assert (testTargetRegistryD77Refutations) "testTargetRegistryD77Refutations must pass")
    true))
