(module asl-gates/tests/auditDepsTest
  :x [runTests]
  :i [(asl-gates/auditDeps :a ad) (asl-gates/auditGates :a ag)])

; (:m :ref SPEED-LOCKS :do "pure rules of audit deps and audit budget over fixture texts, then the real tree: the recorded baseline passes, a fake extra dep fails by its path, a dep count above the baseline fails, a new core to tool import fails and a recorded debt edge passes; the budget lock passes unmeasured, within 15 percent, fails above it, passes above it with a reason row, and a target without a lock row fails")
fn failedOf checks: (List ag/Check) -> (List ag/Check)
  (filter (fn [(c ag/Check)] -> Bool (and (!= c.status ":passed") (!= c.status ":skipped"))) checks)

fn failedIds checks: (List ag/Check) -> (List String)
  (map (fn [(c ag/Check)] -> String c.id) (failedOf checks))

fn firstErr checks: (List ag/Check) -> String
  (optionOr (listHead (map (fn [(c ag/Check)] -> String c.err) (failedOf checks))) "")

fn evs checks: (List ag/Check) -> String
  (stringJoin (map (fn [(c ag/Check)] -> String c.ev) (failedOf checks)) ",")

fn fixtureBaseline -> String
  (str "(:cliDeps :method \"m\" :scope \"s\" :date \"d\" :count 3 :core (asl-cli asl-checker) :tools (asl-intel))\n"
       "(:dep :path \"asl/packages/asl-cli/src/a.asl\")\n"
       "(:dep :path \"asl/packages/asl-checker/src/b.asl\")\n"
       "(:dep :path \"asl/packages/asl-intel/src/c.asl\")\n"
       "(:debt :from \"asl/packages/asl-cli/src/a.asl\" :toPackage \"asl-intel\")\n")

fn baseFiles -> (List String)
  (list "asl/packages/asl-cli/src/a.asl" "asl/packages/asl-checker/src/b.asl" "asl/packages/asl-intel/src/c.asl")

fn ! testDepsPure -> Bool
  (let [(edges (list "asl/packages/asl-cli/src/a.asl asl/packages/asl-intel/src/c.asl" "asl/packages/asl-cli/src/a.asl asl/packages/asl-checker/src/b.asl"))
        (green (ad/depsChecks (fixtureBaseline) (baseFiles) edges))
        (extra (ad/depsChecks (fixtureBaseline) (cons "asl/packages/asl-intel/src/d.asl" (baseFiles)) edges))
        (coreEdge (ad/depsChecks (fixtureBaseline) (baseFiles) (cons "asl/packages/asl-checker/src/b.asl asl/packages/asl-intel/src/c.asl" edges)))
        (shrunk (ad/depsChecks (fixtureBaseline) (list "asl/packages/asl-cli/src/a.asl") (list)))
        (noHead (ad/depsChecks "" (baseFiles) edges))]
    (do (assert (listEmpty? (failedOf green)) (str "the recorded set and the recorded debt edge pass: " (evs green)))
        (assert (and (= (firstErr extra) "ERR_CLI_DEP_NEW") (stringContains? (evs extra) "asl-intel/src/d.asl")) (str "a new dep fails with its path: " (evs extra)))
        (assert (listContains? (failedIds extra) "cliDepCount") "and the count above the baseline fails too")
        (assert (and (= (firstErr coreEdge) "ERR_CORE_IMPORTS_TOOL") (stringContains? (evs coreEdge) "b.asl->asl-intel")) (str "a core file importing a tool package that is no debt fails: " (evs coreEdge)))
        (assert (and (= (firstErr shrunk) "ERR_CLI_DEP_STALE") (listContains? (failedIds shrunk) "cliDebtStale")) (str "baseline rows the computation no longer yields fail, so a lost closure is red: " (evs shrunk)))
        (assert (= (firstErr noHead) "ERR_NO_BASELINE") "no head row fails")
        (assert (= (ad/packageOf "asl/packages/asl-cli/src/a.asl") "asl-cli") "package of a package file")
        (assert (= (ad/packageOf "asl/tools/x/y.asl") "tools") "package of asl/tools")
        (assert (= (ad/packageOf "asl/prelude/prelude.asl") "prelude") "package of the prelude")
        true))

fn lockText -> String
  (str "(:buildLock :id X)\n"
       "(:lock :target \"linux-x86_64\" :emitMs 1000 :linkMs 2000 :binBytes 5000 :date \"d\")\n"
       "(:reason :target \"linux-x86_64\" :metric \"binBytes\" :upTo 7000 :why \"asl-intel grew\")\n")

fn measured emit: Int64 bin: Int64 -> String
  (str "(:measure :target \"linux-x86_64\" :emitMs " (stringFromInt64 emit) " :linkMs 2000 :binBytes " (stringFromInt64 bin) ")\n")

fn ! testBudgetPure -> Bool
  (let [(unmeasured (ad/budgetChecks (lockText) ""))
        (within (ad/budgetChecks (lockText) (measured 1150 5750)))
        (over (ad/budgetChecks (lockText) (measured 1151 5000)))
        (reasoned (ad/budgetChecks (lockText) (measured 1000 7000)))
        (reasonedOver (ad/budgetChecks (lockText) (measured 1000 7001)))
        (typo (ad/budgetChecks (lockText) "(:measure :target \"linux-x86_64\" :emitMss 1)\n"))
        (nolock (ad/budgetChecks (lockText) "(:measure :target \"darwin-arm64\" :emitMs 1)\n"))]
    (do (assert (and (listEmpty? (failedOf unmeasured)) (stringContains? (stringJoin (map (fn [(c ag/Check)] -> String c.id) unmeasured) ",") "unmeasured")) "no measured row passes unmeasured")
        (assert (listEmpty? (failedOf within)) (str "115 percent exactly passes: " (evs within)))
        (assert (and (= (firstErr over) "ERR_BUILD_BUDGET") (listContains? (failedIds over) "buildBudget:linux-x86_64:emitMs")) "one millisecond above 115 percent fails")
        (assert (listEmpty? (failedOf reasoned)) "above 115 percent with a reason row up to the value passes")
        (assert (listContains? (failedIds reasonedOver) "buildBudget:linux-x86_64:binBytes") "above the reason's :upTo fails")
        (assert (= (firstErr typo) "ERR_BAD_MEASURE_KEY") "a misspelt measure key is an error, not a silent skip")
        (assert (= (firstErr nolock) "ERR_NO_LOCK") "a target without a lock row fails")
        true))

fn ! testRealTree -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (baseline (optionOr (ag/readText! (str root "/" (ad/baselinePath))) ""))]
    (match (ad/cliFiles! root)
      ((err e) (do (assert false (str "the CLI closure loads: " e)) false))
      ((ok c)
       (let [(files (pairFirst c))
             (edges (pairSecond c))
             (green (ad/depsChecks baseline files edges))
             (viaCmd (ad/cmdDeps! root (list)))
             (extra (ad/depsChecks baseline (cons "asl/packages/asl-intel/src/zzFakeDep.asl" files) edges))
             (core (ad/depsChecks baseline files (cons "asl/packages/asl-checker/src/check.asl asl/packages/asl-intel/src/intel.asl" edges)))
             (budget (ad/cmdBudget! root (list)))]
         (do (assert (listEmpty? (failedOf green)) (str "the tree passes its baseline: " (evs green)))
             (assert (= viaCmd.exitCode 0) (str "audit deps exits 0 on the tree: " viaCmd.receipt))
             (assert (and (> (listLength files) 200) (stringContains? baseline "(:cliDeps")) "a real dep set and a head row")
             (assert (and (= (firstErr extra) "ERR_CLI_DEP_NEW") (stringContains? (evs extra) "zzFakeDep")) "a fake extra dep in the real set fails by its path")
             (assert (= (firstErr core) "ERR_CORE_IMPORTS_TOOL") "a core to tool import added to the real edges fails")
             (assert (and (= budget.exitCode 0) (stringContains? budget.receipt "unmeasured")) (str "audit budget passes unmeasured: " budget.receipt))
             true)))))

fn ! runTests -> Bool
  (do (assert (testDepsPure) "deps pure rules")
      (assert (testBudgetPure) "budget pure rules")
      (assert (testRealTree) "the real tree")
      true)
