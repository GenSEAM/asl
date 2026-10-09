(module aslVdom/tests/signalTest
  :x [testSignalSourceIntegrity! testSignalGrammarRegistration testSignalSyntaxAndDelimiters! testSignalRuntimeBehavior! testReactiveDependencyPropagation runTests RunTests!]
  :i [(aslVdom/signals :a sig)])

fn testSignalSourceIntegrity! -> Bool
  (let [(sRes (fileRead "asl/packages/asl-vdom/src/signals.asl"))]
    (mt sRes
      ((err e) (assert false (str "Failed to read signals.asl: " e)))
      ((ok src)
        (do
          (assert (or (stringContains? src "schema Signal") (stringContains? src "dfs Signal")) "defines Signal struct")
          (assert (or (stringContains? src "schema Computed") (stringContains? src "dfs Computed")) "defines Computed struct")
          (assert (or (stringContains? src "schema Effect") (stringContains? src "dfs Effect")) "defines Effect struct")
          (assert (stringContains? src "fn makeSignal") "defines makeSignal constructor")
          (assert (stringContains? src "fn signalGet") "defines signalGet reader")
          (assert (stringContains? src "fn signalSet") "defines signalSet updater")
          (assert (stringContains? src "fn signalSubscribe") "defines signalSubscribe observer")
          (assert (stringContains? src "fn makeComputed") "defines makeComputed constructor")
          (assert (stringContains? src "fn computedInvalidate") "defines computedInvalidate mutator")
          (assert (stringContains? src "fn makeEffect") "defines makeEffect constructor")
          (assert (stringContains? src "fn runEffect") "defines runEffect runner")
          (refute (stringContains? src "Mach-O") "Zero Mach-O emission in signals")
          (refute (stringContains? src "ELF64") "Zero ELF64 emission in signals"))))
    true)

fn testSignalSymbolExports! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-vdom/src/signals.asl"))]
    (mt gRes
      ((err ge) (assert false (str "Failed to read signals.asl: " ge)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc "Signal") "module defines Signal")
          (assert (stringContains? gSrc "Computed") "module defines Computed")
          (assert (stringContains? gSrc "Effect") "module defines Effect")
          (assert (stringContains? gSrc "makeSignal") "module defines makeSignal")
          (assert (stringContains? gSrc "signalGet") "module defines signalGet")
          (assert (stringContains? gSrc "signalSet") "module defines signalSet")
          (assert (stringContains? gSrc "signalSubscribe") "module defines signalSubscribe")
          (refute (stringContains? gSrc "make_signal") "Strict camelCase in module symbols"))))
    true)

fn testSignalSyntaxAndDelimiters! -> Bool
  (let [(chkCmd "./bin/asl check asl/packages/asl-vdom/src/signals.asl")
        (chkRes (processRun chkCmd))]
    (assert (= chkRes.exitCode 0) "asl check exits 0 on signals.asl")
    (assert (stringContains? chkRes.stdout "(:check :id balance :status :passed)") "signals.asl delimiter balance verified cleanly")
    (refute (stringContains? chkRes.stdout "Syntax error") "Zero syntax errors in signals.asl")
    (refute (stringContains? chkRes.stdout "unbalanced") "Zero unbalanced delimiters in signals.asl")
    true)

fn testSignalRuntimeBehavior! -> Bool
  (let [(evalSignalCmd "./bin/asl eval '(:signal :id \"count\" :value 0 :subscribers ())'")
        (evalSignalRes (processRun evalSignalCmd))
        (evalSetCmd "./bin/asl eval '(:signal :id \"count\" :value 1 :subscribers ())'")
        (evalSetRes (processRun evalSetCmd))]
    (assert (= evalSignalRes.exitCode 0) "asl eval exits 0 on initial signal")
    (assert (stringContains? evalSignalRes.stdout ":value 0") "signal holds initial value 0")
    (refute (stringContains? evalSignalRes.stdout ":value 1") "initial signal refutes value 1")
    (assert (= evalSetRes.exitCode 0) "asl eval exits 0 on updated signal")
    (assert (stringContains? evalSetRes.stdout ":value 1") "updated signal holds value 1")
    (refute (stringContains? evalSetRes.stdout ":value 0") "updated signal refutes value 0")
    true)

fn testReactiveDependencyPropagation -> Bool
  (let [(c1 (sig/makeComputed "doubleCount" "20" (list "count")))
        (c2 (sig/makeComputed "other" "99" (list "otherSig")))
        (e1 (sig/makeEffect "logCount" (list "count")))
        (e2 (sig/makeEffect "logOther" (list "otherSig")))
        (comps (list c1 c2))
        (effs (list e1 e2))
        (updatedComps (sig/propagateSignalChange "count" comps))
        (updatedEffs (sig/propagateEffects "count" effs))
        (c1After (optionOr (listHead updatedComps) c1))
        (e1After (optionOr (listHead updatedEffs) e1))
        (batch0 (sig/queueSignalUpdate (sig/makeSignalBatch) "otherSig"))
        (batchPair (sig/flushSignalBatch batch0))
        (batchCleared (pairFirst batchPair))
        (queuedIds (pairSecond batchPair))
        (batchPropagation (sig/propagateSignalBatch queuedIds comps effs))
        (compsAfterBatch (pairFirst batchPropagation))
        (effsAfterBatch (pairSecond batchPropagation))
        (c2AfterBatch (optionOr (listHead (optionOr (listTail compsAfterBatch) (list))) c2))
        (e2AfterBatch (optionOr (listHead (optionOr (listTail effsAfterBatch) (list))) e2))]
    (do
      (assert c1After.dirty "dependent computed c1 is marked dirty after signal update")
      (refute (not c1After.dirty) "dirty flag refutes non-dirty")
      (assert (= e1After.runCount 1) "dependent effect runCount is incremented")
      (refute (!= e1After.runCount 1) "effect runCount refutes non-1")
      (assert (not batchCleared.isPending) "flushed batch is no longer pending")
      (assert c2AfterBatch.dirty "batch propagation marks c2 dirty")
      (assert (= e2AfterBatch.runCount 1) "batch propagation runs e2")
      true))

fn ! runTests -> Bool
  (do
    (assert (testSignalSourceIntegrity!) "Signal source integrity passed")
    (assert (testSignalSymbolExports!) "Signal symbol exports passed")
    (assert (testSignalSyntaxAndDelimiters!) "Signal syntax and delimiters passed")
    (assert (testSignalRuntimeBehavior!) "Signal runtime behavior passed")
    (assert (testReactiveDependencyPropagation) "Reactive dependency propagation passed")
    true)

fn RunTests! -> Bool
  (runTests)
