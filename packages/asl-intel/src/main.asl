(module asl-intel
  :x [runIntel! dispatchIntel! makeCtx! makeCtxFor! main]
  :i [(asl-intel/text :a t)
      (asl-intel/host :a h)
      (asl-intel/coupling :a c)
      (asl-intel/search :a se)
      (asl-intel/deadcode :a dc)
      (asl-intel/vacuity :a va)
      (asl-intel/stubs :a st)
      (asl-intel/graph :a g)
      (asl-intel/complexity :a cx)
      (asl-intel/trace :a tr)
      (asl-intel/sweep :a sw)
      (asl-intel/vitality :a vt)
      (asl-intel/lintOp :a lo)])

(schema Opts
  (:f fmt String)
  (:f strict Bool)
  (:f pkg String)
  (:f filter String)
  (:f limit Int64)
  (:f modF String)
  (:f symF String)
  (:f target String)
  (:f hasTarget Bool))

fn opts0 fmt: String -> Opts
  (Opts :fmt fmt :strict false :pkg "" :filter "hotspots" :limit 25 :modF "" :symF "" :target "" :hasTarget false)

fn pyInt s: String -> (Option Int64)
  (let [(u (t/pyStrip s))
        (neg (stringStartsWith? u "-"))
        (body (if (or neg (stringStartsWith? u "+")) (t/sliceStr u 1 (stringLength u)) u))
        (b (stringToBytes body)) (n (bytesLength b))]
    (if (or (= n 0) (or (= (bytesGet b 0) 95) (= (bytesGet b (- n 1)) 95))) (none)
      (mt (digitsVal b n 0 0 false)
        ((some v) (some (if neg (- 0 v) v)))
        ((none) (none)))))

fn digitsVal b: Bytes n: Int64 i: Int64 acc: Int64 lastUnderscore: Bool -> (Option Int64)
  (if (>= i n) (some acc)
    (let [(c (bytesGet b i))]
      (cond
        ((and (>= c 48) (<= c 57)) (if (> acc 922337203685477579) (none) (digitsVal b n (+ i 1) (+ (* acc 10) (- c 48)) false)))
        ((and (= c 95) (not lastUnderscore)) (digitsVal b n (+ i 1) acc true))
        (else (none)))))

fn hasNext? args: (List String) -> Bool
  (not (listEmpty? (optionOr (listTail args) (list))))

fn parseOpts sub: String args: (List String) o: Opts -> Opts
  (mt (listHead args)
    ((none) o)
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))
            (nxt (optionOr (listHead rest) ""))
            (after (optionOr (listTail rest) (list)))
            (valueFlag (fn [(names (List String))] -> Bool (and (listContains? names a) (hasNext? args))))]
        (cond
          ((= a "--summary") (parseOpts sub rest (with o :fmt "summary")))
          ((= a "--json") (parseOpts sub rest (with o :fmt "json")))
          ((= a "--asn") (parseOpts sub rest (with o :fmt "asn")))
          ((and (= a "--strict") (listContains? (list "coupling" "vacuity" "stubs") sub))
            (parseOpts sub rest (with o :strict true)))
          ((and (listContains? (list "coupling" "deadcode") sub) (valueFlag (list "--package" "-p")))
            (parseOpts sub after (with o :pkg nxt)))
          ((and (= sub "graph") (valueFlag (list "--filter" "-f")))
            (parseOpts sub after (with o :filter nxt)))
          ((and (listContains? (list "graph" "complexity") sub) (valueFlag (list "--limit" "-l")))
            (parseOpts sub after (with o :limit (optionOr (pyInt nxt) 25))))
          ((and (= sub "graph") (valueFlag (list "--module" "-m")))
            (parseOpts sub after (with o :modF nxt)))
          ((and (= sub "graph") (valueFlag (list "--symbol" "-s")))
            (parseOpts sub after (with o :symF nxt)))
          ((and (= sub "graph") (not (stringStartsWith? a "-")))
            (if (or (stringContains? a "/") (stringEndsWith? a ".asl"))
              (parseOpts sub rest (with o :modF a))
              (parseOpts sub rest (with o :symF a))))
          ((and (= sub "complexity") (not (stringStartsWith? a "-")))
            (parseOpts sub rest (with o :target a :hasTarget true)))
          ((and (= sub "lint") (not (stringStartsWith? a "-")))
            (parseOpts sub rest (with o :target a :hasTarget true)))
          ((and (= sub "trace") (and (= a "--target") (hasNext? args)))
            (parseOpts sub after (with o :target nxt :hasTarget true)))
          ((and (= sub "trace") (and (not (stringStartsWith? a "--")) (not o.hasTarget)))
            (parseOpts sub rest (with o :target a :hasTarget true)))
          (else (parseOpts sub rest o))))))

fn textOutcome r: (Result String String) -> h/Outcome
  (mt r
    ((ok s) (h/outcome (str s "\n") "" 0))
    ((err e) (h/outcome "" (str "Error: " e "\n") 1)))

fn gitRootFrom! dir: String orig: String -> String
  (cond
    ((fileExists? (t/joinPath dir ".git")) dir)
    ((= (t/dirName dir) dir) orig)
    (else (gitRootFrom! (t/dirName dir) orig)))

fn makeCtx! -> h/Ctx
  (let [(cwd (mt (realPath ".") ((ok p) p) ((err _) ".")))
        (homeEnv (optionOr (envGet "ASL_INTEL_HOME") ""))
        (home (if (stringEmpty? homeEnv) (gitRootFrom! cwd cwd) (t/absPath homeEnv cwd)))]
    (h/Ctx :home home :cwd cwd :aslRoot (optionOr (envGet "ASL_ROOT") "") :env (none)))

fn makeCtxFor! workspaceRoot: String -> h/Ctx
  (let [(base (makeCtx!))]
    (if (and (stringEmpty? (optionOr (envGet "ASL_INTEL_HOME") ""))
             (and (not (fileExists? (str base.home "/asl/packages")))
                  (fileExists? (str workspaceRoot "/asl/packages"))))
      (h/Ctx :home workspaceRoot :cwd base.cwd :aslRoot base.aslRoot :env base.env)
      base))

fn usage -> String
  (t/joinWith (list
    "Usage: asl-intel <coupling|impact|outline|query|deadcode|vacuity|sweep|graph|complexity|stubs|vitality|lint> [options]"
    "  Unified Code Intelligence Engine (ADR D135)"
    "Subcommands:"
    "  vitality [--summary|--json|--asn] (alias: full, all, system)"
    "  stubs [--summary|--json|--asn] [--strict]"
    "  coupling [--summary|--json|--asn] [--strict] [--package <name>]"
    "  graph [--summary|--json|--asn] [--filter <hotspots|complex|coupled|stubs|all>] [--limit <n>] [--module <name>] [--symbol <name>]"
    "  complexity [<target>] [--summary|--json|--asn] [--limit <n>]"
    "  impact <symbol>"
    "  outline <file>"
    "  query <text>"
    "  deadcode [--summary|--json|--asn] [--package <name>]"
    "  lint [<file>] [--summary|--json|--asn]  (idiom checks, e.g. LINT_QUADRATIC_LISTGET; no file: whole tracked tree)"
    "  vacuity [--summary|--json|--asn] [--strict]"
    "  sweep"
    "") "\n")

fn runIntel! ctx: h/Ctx args: (List String) -> h/Outcome
  (let [(sub (optionOr (listHead args) "")) (rest (optionOr (listTail args) (list)))]
    (cond
      ((or (listEmpty? args) (or (= sub "-h") (or (= sub "--help") (= sub "help")))) (h/outcome (usage) "" 0))
      ((= sub "impact") (textOutcome (se/analyzeImpact! ctx (optionOr (listHead rest) "main"))))
      ((= sub "outline") (textOutcome (se/extractOutline! ctx (optionOr (listHead rest) "asl/packages/asl-intel/src/main.asl"))))
      ((= sub "query") (textOutcome (se/querySymbols! ctx (optionOr (listHead rest) ""))))
      ((= sub "coupling") (let [(o (parseOpts sub rest (opts0 "asn")))] (c/runCoupling! ctx o.fmt o.strict)))
      ((= sub "vacuity") (let [(o (parseOpts sub rest (opts0 "asn")))] (va/runVacuity! ctx o.fmt o.strict)))
      ((= sub "graph") (let [(o (parseOpts sub rest (opts0 "asn")))] (g/runGraph! ctx o.fmt o.filter o.limit o.modF o.symF)))
      ((= sub "complexity") (let [(o (parseOpts sub rest (opts0 "asn")))] (cx/runComplexity! ctx o.fmt o.target o.limit)))
      ((listContains? (list "vitality" "full" "all" "system") sub) (let [(o (parseOpts sub rest (opts0 "summary")))] (vt/runVitality! ctx o.fmt)))
      ((or (= sub "sweep") (= sub "check-all")) (sw/runSweep! ctx))
      ((= sub "trace") (let [(o (parseOpts sub rest (opts0 "summary")))] (tr/runTrace! ctx o.fmt o.target)))
      ((= sub "stubs") (let [(o (parseOpts sub rest (opts0 "asn")))] (st/runStubs! ctx o.fmt o.strict)))
      ((= sub "deadcode") (let [(o (parseOpts sub rest (opts0 "asn")))] (dc/runDeadcode! ctx o.fmt o.pkg)))
      ((= sub "lint") (let [(o (parseOpts sub rest (opts0 "asn")))] (lo/runLint! ctx o.fmt o.target)))
      (else (h/outcome "" (str "Unknown intel subcommand: " sub "\n") 1))))

fn dispatchIntel! op: String target: String -> String
  (runIntel! (makeCtx!) (if (stringEmpty? target) (list op) (list op target))).out

fn ! main args: (List String) -> (Result Int64 String)
  (let [(oc (runIntel! (mt (envGet "ASL_INTEL_WORKSPACE") ((some w) (makeCtxFor! w)) ((none) (makeCtx!))) args))]
    (do
      (print oc.out)
      (if (stringEmpty? oc.err) () (eprintln (t/sliceStr oc.err 0 (- (stringLength oc.err) 1))))
      (ok oc.code)))
