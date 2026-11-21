(module asl-gates/auditDeps
  :x [cliEntry baselinePath lockPath packageOf stripRoot importClosure! cliFiles! depsChecks baselineText budgetChecks cmdDeps! cmdBudget!]
  :i [(asl-gates/auditGates :a ag) (asl-gates/auditLanded :a al) (asl-checker/resolve :a r)])

; (:m :ref SPEED-LOCKS :do "audit deps: the native CLI dep set is the import closure of native.asl (the set nativeBuild keys the CLI by: the closure plus prelude.asl and the prelude/native files) read with the checker's own resolver, compared with the tracked baseline; a path not in the baseline or a count above it fails with the path, so the set only shrinks. The DAG rule: a file of a :core package may not import a file of a :tools package unless a (:debt :from FILE :toPackage PKG) row records it; a new edge fails, debt rows only come out. audit budget: the build milliseconds and binary bytes of the lock .asl/mem/bench/nativeBuild.asn per target; a measured row (--measured FILE, written by a build) more than 15 percent above its lock fails unless a (:reason :target T :metric M :upTo N and a reason text) row allows it, no measured row passes :unmeasured")
fn cliEntry -> String
  "asl/packages/asl-cli/src/native.asl"

fn baselinePath -> String
  "asl/packages/asl-gates/baselines/cliDeps.asn"

fn lockPath -> String
  ".asl/mem/bench/nativeBuild.asn"

fn packageOf path: String -> String
  (let [(parts (stringSplit path "/"))
        (p0 (optionOr (listGet parts 0) ""))
        (p1 (optionOr (listGet parts 1) ""))]
    (if (and (= p0 "asl") (= p1 "packages"))
      (optionOr (listGet parts 2) "")
      (if (= p0 "asl") p1 p0)))

fn stripRoot prefix: String p: String -> String
  (if (stringStartsWith? p prefix) (optionOr (stringSlice p (stringLength prefix) (stringLength p)) p) p)

fn distinctSorted xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (listHead acc) (some x)) acc (cons x acc))) (list) (listSort xs)))

fn edgesOf prefix: String cl: (Map String r/ModuleSummary) -> (List String)
  (fold (fn [(acc (List String)) (k String)] -> (List String)
          (let [(m (optionOr (mapGet cl k) (r/emptyModuleSummary)))]
            (listAppend acc (map (fn [(t String)] -> String (str (stripRoot prefix k) " " (stripRoot prefix t))) (mapValues m.imports)))))
        (list) (mapKeys cl))

; (:m :ref SPEED-LOCKS :do "the closure of an entry under root: its module files root-relative, sorted, and its import edges as FROM TO lines; an error when the imports do not load")
fn ! importClosure! root: String entry: String -> (Result (Pair (List String) (List String)) String)
  (let [(prefix (str (resultOr (realPath root) root) "/"))
        (name (optionOr (stringSlice entry 0 (- (stringLength entry) 4)) entry))]
    (match (r/loadModuleDeps! (list root) (list name))
      ((err e) (err (str "the imports of " entry " do not load: " e)))
      ((ok cl) (ok (pair (distinctSorted (cons entry (map (fn [(k String)] -> String (stripRoot prefix k)) (filter (fn [(k String)] -> Bool (stringStartsWith? k "/")) (mapKeys cl)))))
                         (distinctSorted (edgesOf prefix cl)))))))

; (:m :ref SPEED-LOCKS :do "the native CLI dep set the way the cli stage of buildCode! in nativeBuild keys it: the closures of native.asl and of the asl1 compiler it is built with, prelude.asl, the prelude/native .asl files and the two fixed inputs libaslrt.a and seed.asn, with the closure edges")
fn asl1Entry -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn ! cliFiles! root: String -> (Result (Pair (List String) (List String)) String)
  (match (importClosure! root (cliEntry))
    ((err e) (err e))
    ((ok c)
     (match (importClosure! root (asl1Entry))
       ((err e) (err e))
       ((ok k)
        (let [(natives (map (fn [(n String)] -> String (str "asl/prelude/native/" n))
                            (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) (resultOr (dirList (str root "/asl/prelude/native")) (list)))))
              (fixed (list "asl/prelude/prelude.asl" "asl/host/out/libaslrt.a" "asl/seed/seed.asn"))]
          (ok (pair (distinctSorted (listAppend fixed (listAppend natives (listAppend (pairFirst c) (pairFirst k)))))
                    (distinctSorted (listAppend (pairSecond c) (pairSecond k))))))))))

fn rowsOf text: String tag: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) (str "(" tag " "))) (stringLines text))

fn headOf text: String -> String
  (optionOr (listHead (rowsOf text ":cliDeps")) "")

fn asSet xs: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (x String)] -> (Map String Bool) (mapSet acc x true)) (mapEmpty) xs)

fn edgeFrom e: String -> String
  (optionOr (listHead (stringSplit e " ")) "")

fn edgeTo e: String -> String
  (optionOr (listGet (stringSplit e " ") 1) "")

; (:m :ref SPEED-LOCKS :do "the core to tool edges as FROM->PACKAGE keys, one per file and tool package")
fn violations core: (List String) tools: (List String) edges: (List String) -> (List String)
  (distinctSorted
    (map (fn [(e String)] -> String (str (edgeFrom e) "->" (packageOf (edgeTo e))))
         (filter (fn [(e String)] -> Bool (and (listContains? core (packageOf (edgeFrom e))) (listContains? tools (packageOf (edgeTo e))))) edges)))

fn debtKey row: String -> String
  (str (al/rowText row "from") "->" (al/rowText row "toPackage"))

fn countOf text: String -> Int64
  (intOf (headOf text) "count")

; (:m :ref SPEED-LOCKS :do "the checks of audit deps over a baseline text, the dep files and the edges: cliDepSet (a path not in the baseline is named), cliDepCount (not above the baseline count) and cliCoreDag (every core to tool package edge recorded as debt); a baseline without its head row fails")
fn depsChecks baseline: String files: (List String) edges: (List String) -> (List ag/Check)
  (let [(head (headOf baseline))
        (knownList (map (fn [(l String)] -> String (al/rowText l "path")) (rowsOf baseline ":dep")))
        (known (asSet knownList))
        (core (al/rowItems head "core"))
        (tools (al/rowItems head "tools"))
        (debtList (map debtKey (rowsOf baseline ":debt")))
        (debt (asSet debtList))
        (fresh (filter (fn [(f String)] -> Bool (not (mapHas? known f))) files))
        (all (violations core tools edges))
        (bad (filter (fn [(v String)] -> Bool (not (mapHas? debt v))) all))
        (fileSet (asSet files))
        (allSet (asSet all))
        (staleDeps (filter (fn [(p String)] -> Bool (not (mapHas? fileSet p))) knownList))
        (staleDebt (filter (fn [(v String)] -> Bool (not (mapHas? allSet v))) debtList))]
    (if (stringEmpty? head)
      (list (ag/failCheck "cliDepSet" "ERR_NO_BASELINE" (str "no (:cliDeps ...) head row in " (baselinePath)) (none) (none)))
      (listAppend
        (listAppend (ag/perItem "cliDepSet" fresh "ERR_CLI_DEP_NEW" (some (listLength files)))
                    (if (> (listLength files) (countOf baseline))
                      (list (ag/failCheck "cliDepCount" "ERR_CLI_DEP_COUNT" (str (ag/itos (listLength files)) " deps, baseline " (ag/itos (countOf baseline))) (none) (none)))
                      (list (ag/passCheck "cliDepCount" (some (listLength files)) (none)))))
        (listAppend (ag/perItem "cliCoreDag" bad "ERR_CORE_IMPORTS_TOOL" (some (listLength all)))
                    (listAppend (ag/perItem "cliDepStale" staleDeps "ERR_CLI_DEP_STALE" (some (listLength knownList)))
                                (ag/perItem "cliDebtStale" staleDebt "ERR_CLI_DEBT_STALE" (some (listLength debtList))))))))

; (:m :ref SPEED-LOCKS :do "the baseline file text for a dep set: head row with method, scope, date and count, one :dep row per path, one :debt row per core to tool package edge")
fn baselineText date: String core: (List String) tools: (List String) files: (List String) edges: (List String) -> String
  (let [(vs (violations core tools edges))]
    (str "(:cliDeps :method \"import closure of " (cliEntry) " by the checker resolver plus prelude.asl and prelude/native, as depsOf! in nativeBuild builds it; audit deps --record\" :scope \"main worktree, native CLI\" :date \"" date "\" :count " (ag/itos (listLength files))
         " :core (" (stringJoin core " ") ") :tools (" (stringJoin tools " ") "))\n"
         (stringJoin (map (fn [(f String)] -> String (str "(:dep :path \"" f "\")")) files) "\n") "\n"
         (stringJoin (map (fn [(v String)] -> String (str "(:debt :from \"" (optionOr (listHead (stringSplit v "->")) "") "\" :toPackage \"" (optionOr (listGet (stringSplit v "->") 1) "") "\")")) vs) "\n") "\n"))

fn flagValue argv: (List String) key: String -> String
  (match (listHead argv)
    ((none) "")
    ((some a) (if (stringStartsWith? a (str key "="))
                (optionOr (stringSlice a (+ (stringLength key) 1) (stringLength a)) "")
                (flagValue (optionOr (listTail argv) (list)) key))))

fn listFlag argv: (List String) key: String fallback: (List String) -> (List String)
  (if (stringEmpty? (flagValue argv key)) fallback (stringSplit (flagValue argv key) ","))

fn ! recordDeps! root: String argv: (List String) old: String files: (List String) edges: (List String) -> ag/AuditRun
  (let [(oldHead (headOf old))
        (core (listFlag argv "--core" (al/rowItems oldHead "core")))
        (tools (listFlag argv "--tools" (al/rowItems oldHead "tools")))
        (date (flagValue argv "--date"))
        (known (asSet (map (fn [(l String)] -> String (al/rowText l "path")) (rowsOf old ":dep"))))
        (grown (if (stringEmpty? oldHead) (list) (filter (fn [(f String)] -> Bool (not (mapHas? known f))) files)))]
    (if (and (not (listEmpty? grown)) (not (listContains? argv "--allowGrowth")))
      (ag/emit "deps" (ag/perItem "record" grown "ERR_RECORD_GROWTH" (none)) "" "" false)
    (if (or (stringEmpty? date) (listEmpty? tools))
      (ag/emit "deps" (list (ag/failCheck "record" "ERR_USAGE" "--record needs --date=YYYY-MM-DD and --tools=a,b (or an existing baseline)" (none) (none))) "" "" false)
      (match (fileWrite (str root "/" (baselinePath)) (stringToBytes (baselineText date core tools files edges)))
        ((err e) (ag/emit "deps" (list (ag/failCheck "record" "ERR_IO" e (none) (none))) "" "" false))
        ((ok _) (ag/emit "deps" (list (ag/passCheck "record" (some (listLength files)) (none))) "" "" false))))))

; (:m :ref SPEED-LOCKS :do "audit deps [--record --date=YYYY-MM-DD --core=a,b --tools=c,d]: without flags checks the tree against the baseline; --record rewrites the baseline from the tree (core and tools default to the lists of the existing baseline)")
fn ! cmdDeps! root: String argv: (List String) -> ag/AuditRun
  (match (cliFiles! root)
    ((err e) (ag/emit "deps" (list (ag/failCheck "closure" "ERR_CLI_CLOSURE" e (none) (none))) "" "" false))
    ((ok c)
     (let [(old (optionOr (ag/readText! (str root "/" (baselinePath))) ""))]
       (if (listContains? argv "--record")
         (recordDeps! root argv old (pairFirst c) (pairSecond c))
         (ag/emit "deps" (depsChecks old (pairFirst c) (pairSecond c)) (str ":count " (ag/itos (listLength (pairFirst c)))) "" false)))))

fn intOf row: String key: String -> Int64
  (match (stringIndexOf row (str ":" key " "))
    ((none) -1)
    ((some i) (let [(rest (optionOr (stringSlice row (+ i (stringLength key) 2) (stringLength row)) ""))]
                (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ")")) "") " ")) "")) -1))))

fn lockFor lock: String target: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (= (al/rowText l "target") target)) (rowsOf lock ":lock"))) "")

fn allowed reasons: (List String) target: String metric: String -> Int64
  (fold (fn [(best Int64) (l String)] -> Int64
          (if (and (= (al/rowText l "target") target) (= (al/rowText l "metric") metric))
            (if (> (intOf l "upTo") best) (intOf l "upTo") best)
            best))
        0 reasons)

fn metricNames -> (List String)
  (list "emitMs" "linkMs" "asl1EmitMs" "asl1LinkMs" "binBytes")

fn metricCheck lock: String target: String lk: String m: String reasons: (List String) k: String -> ag/Check
  (let [(base (intOf lk k))
        (now (intOf m k))
        (id (str "buildBudget:" target ":" k))]
    (if (or (< base 0) (< now 0))
      (ag/passCheck id (none) (none))
      (if (or (<= (* now 100) (* base 115)) (>= (allowed reasons target k) now))
        (ag/passCheck id (some now) (none))
        (ag/failCheck id "ERR_BUILD_BUDGET" (str "measured " (ag/itos now) " over lock " (ag/itos base) " by more than 15 percent, no :reason row") (some now) (none)))))

fn unknownKeys row: String -> (List String)
  (filter (fn [(w String)] -> Bool (and (stringStartsWith? w ":") (not (listContains? (list ":measure" ":target" ":emitMs" ":linkMs" ":asl1EmitMs" ":asl1LinkMs" ":binBytes") (optionOr (listHead (stringSplit w ")")) w)))))
          (stringSplit (stringTrim row) " "))

fn targetChecks lock: String reasons: (List String) m: String -> (List ag/Check)
  (let [(target (al/rowText m "target"))
        (lk (lockFor lock target))]
    (if (stringEmpty? lk)
      (list (ag/failCheck (str "buildBudget:" target) "ERR_NO_LOCK" (str "no (:lock :target " target ") row in " (lockPath)) (none) (none)))
      (map (fn [(k String)] -> ag/Check (metricCheck lock target lk m reasons k)) (metricNames))))

; (:m :ref SPEED-LOCKS :do "one check per measured row and metric: over 115 percent of the lock fails ERR_BUILD_BUDGET unless a reason row for that target and metric has :upTo at or above the measured value; a metric missing from the lock or the measurement is skipped; no measured row at all passes buildBudget:unmeasured")
fn budgetChecks lock: String measured: String -> (List ag/Check)
  (let [(rows (rowsOf measured ":measure"))
        (reasons (rowsOf lock ":reason"))]
    (if (listEmpty? rows)
      (list (ag/passCheck "buildBudget:unmeasured" (some (listLength (rowsOf lock ":lock"))) (none)))
      (fold (fn [(acc (List ag/Check)) (m String)] -> (List ag/Check)
              (listAppend acc (if (listEmpty? (unknownKeys m)) (targetChecks lock reasons m) (ag/perItem "buildBudget:key" (unknownKeys m) "ERR_BAD_MEASURE_KEY" (none)))))
            (list) rows)))

; (:m :ref SPEED-LOCKS :do "audit budget [--measured=FILE]: the lock rows of .asl/mem/bench/nativeBuild.asn against the measured rows of FILE; without FILE nothing is measured and the audit passes :unmeasured")
fn ! cmdBudget! root: String argv: (List String) -> ag/AuditRun
  (let [(lock (ag/readText! (str root "/" (lockPath))))
        (given (flagValue argv "--measured"))
        (measured (if (stringEmpty? given) (some "") (ag/readText! given)))]
    (match lock
      ((none) (ag/emit "budget" (list (ag/failCheck "lock" "ERR_NO_LOCK" (str "cannot read " (lockPath)) (none) (none))) "" "" false))
      ((some lt) (match measured
        ((none) (ag/emit "budget" (list (ag/failCheck "measured" "ERR_IO" (str "cannot read " given) (none) (none))) "" "" false))
        ((some mt) (ag/emit "budget" (budgetChecks lt mt) (if (stringEmpty? mt) ":unmeasured" "") "" false))))))
