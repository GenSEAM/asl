(module asl-tools/perfGate
  :x [main Baseline BenchBase CompileBase GcPolicy MeasureRow
      parseForms atomText itemsOf kvGet unquote stripColon textOf quoteStr floatOf intOf
      loadBaselineText loadBaseline renderBaseline
      withinTolerance maxAllowed evaluate findRow
      benchLine? parseBenchRows rowsFromTop parityRowsFromTop ratioOf benchRowsFromText runBenchMeasurements
      osFlag instrRetired fixedInputDir compileWorkloadRow fmt3 rowTol hostLine methodText defaultBaselinePath fmt2
      flagTakesValue? positional optValue]
  :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-tools/nativeTest :a nt)])

(schema BenchBase (:f name String) (:f ratio Float64) (:f tol Float64))
(schema CompileBase (:f name String) (:f instr Int64) (:f tol Float64))
(schema GcPolicy (:f minMib Int64) (:f label String) (:f date String) (:f method String) (:f scope String))
(schema Baseline
  (:f id String) (:f date String) (:f host String) (:f method String)
  (:f tolerance Float64) (:f toleranceLabel String)
  (:f benches (List BenchBase)) (:f compiles (List CompileBase)) (:f gcPolicy (List GcPolicy)))
(schema MeasureRow (:f name String) (:f ok Bool) (:f value Float64) (:f note String))

fn parseForms src: String -> (Result (List rd/SExpr) String)
  (match (ast/readForms (lx/tokenize src))
    ((err e) (err e.msg))
    ((ok pfs) (ok (map (fn [(pf ast/PosForm)] -> rd/SExpr pf.expr) pfs))))

fn atomText s: rd/SExpr -> String
  (match s ((rd/sexprAtom v) v) (_ ""))

fn itemsOf s: rd/SExpr -> (List rd/SExpr)
  (match s ((rd/sexprList xs) xs) ((rd/sexprVect xs) xs) (_ (list)))

fn kvGet items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead items)
    ((none) (none))
    ((some it) (let [(rest (optionOr (listTail items) (list)))]
                 (if (= (atomText it) key) (listHead rest) (kvGet rest key)))))

fn unquote v: String -> String
  (if (and (stringStartsWith? v "\"") (and (stringEndsWith? v "\"") (>= (stringLength v) 2)))
    (stringReplace (stringReplace (optionOr (stringSlice v 1 (- (stringLength v) 1)) v) "\\\"" "\"") "\\\\" "\\")
    v)

fn stripColon v: String -> String
  (if (stringStartsWith? v ":") (optionOr (stringSlice v 1 (stringLength v)) v) v)

fn textOf s: rd/SExpr -> String
  (stripColon (unquote (atomText s)))

fn quoteStr s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn floatOf s: (Option rd/SExpr) -> (Option Float64)
  (match s ((none) (none)) ((some v) (stringToFloat64 (atomText v))))

fn intOf s: (Option rd/SExpr) -> (Option Int64)
  (match s ((none) (none)) ((some v) (stringToInt64 (atomText v))))

fn fmt2 x: Float64 -> String
  (let [(neg (< x 0.0))
        (ax (if neg (* x -1.0) x))
        (hundredths (optionOr (float64ToInt64 (+ (* ax 100.0) 0.5)) 0))
        (ip (/ hundredths 100))
        (frac (mod hundredths 100))]
    (str (if neg "-" "") ip "." (if (< frac 10) "0" "") frac))

fn fmt3 x: Float64 -> String
  (let [(thousandths (optionOr (float64ToInt64 (+ (* x 1000.0) 0.5)) 0))
        (frac (mod thousandths 1000))]
    (str (/ thousandths 1000) "." (if (< frac 100) "0" "") (if (< frac 10) "0" "") frac))

fn subForms items: (List rd/SExpr) tag: String -> (List rd/SExpr)
  (filter (fn [(it rd/SExpr)] -> Bool (= (atomText (optionOr (listHead (itemsOf it)) (rd/makeAtom ""))) tag)) items)

fn parseBenchBase row: rd/SExpr -> BenchBase
  (let [(items (itemsOf row))]
    (BenchBase :name (textOf (optionOr (kvGet items ":name") (rd/makeAtom "")))
               :ratio (optionOr (floatOf (kvGet items ":ratio")) 0.0)
               :tol (optionOr (floatOf (kvGet items ":tol")) 0.0)))

fn parseCompileBase row: rd/SExpr -> CompileBase
  (let [(items (itemsOf row))]
    (CompileBase :name (textOf (optionOr (kvGet items ":name") (rd/makeAtom "")))
                 :instr (optionOr (intOf (kvGet items ":instr")) 0)
                 :tol (optionOr (floatOf (kvGet items ":tol")) 0.0)))

fn parseGcPolicy row: rd/SExpr -> GcPolicy
  (let [(items (itemsOf row))]
    (GcPolicy :minMib (optionOr (intOf (kvGet items ":minMib")) 0)
              :label (textOf (optionOr (kvGet items ":label") (rd/makeAtom "")))
              :date (textOf (optionOr (kvGet items ":date") (rd/makeAtom "")))
              :method (textOf (optionOr (kvGet items ":method") (rd/makeAtom "")))
              :scope (textOf (optionOr (kvGet items ":scope") (rd/makeAtom "")))))

fn loadBaselineText text: String -> (Result Baseline String)
  (match (parseForms text)
    ((err e) (err (str "perfBaseline.asn does not read: " e)))
    ((ok forms)
     (match (listHead forms)
       ((none) (err "perfBaseline.asn is empty"))
       ((some top)
        (let [(items (itemsOf top))]
          (if (!= (atomText (optionOr (listHead items) (rd/makeAtom ""))) ":perfBaseline")
            (err "perfBaseline.asn is not a (:perfBaseline ...) form")
            (let [(benches (map parseBenchBase (subForms items ":bench")))]
              (if (listEmpty? benches)
                (err "perfBaseline.asn has zero (:bench ...) rows; a prior --record run measured none (a bench-name filter swallowed every bench), so checkRun would silently pass with no coverage")
                (ok (Baseline
                      :id (textOf (optionOr (kvGet items ":id") (rd/makeAtom "")))
                      :date (textOf (optionOr (kvGet items ":date") (rd/makeAtom "")))
                      :host (textOf (optionOr (kvGet items ":host") (rd/makeAtom "")))
                      :method (textOf (optionOr (kvGet items ":method") (rd/makeAtom "")))
                      :tolerance (optionOr (floatOf (kvGet items ":tolerance")) 0.35)
                      :toleranceLabel (textOf (optionOr (kvGet items ":toleranceLabel") (rd/makeAtom "")))
                      :benches benches
                      :compiles (map parseCompileBase (subForms items ":compile"))
                      :gcPolicy (map parseGcPolicy (subForms items ":gcPolicy"))))))))))))

fn ! loadBaseline path: String -> (Result Baseline String)
  (match (fileReadString path)
    ((err e) (err (str "perfBaseline " path " is missing or unreadable: " e)))
    ((ok text) (loadBaselineText text)))

fn idLine b: Baseline -> String
  (str "(:perfBaseline :id " b.id " :date " (quoteStr b.date) " :host " (quoteStr b.host) " :tolerance " (fmt2 b.tolerance) " :toleranceLabel " b.toleranceLabel)

fn methodLineOf b: Baseline -> String
  (str "  :method " (quoteStr b.method))

fn benchLine2 x: BenchBase -> String
  (str "  (:bench :name " (quoteStr x.name) " :ratio " (fmt3 x.ratio) " :tol " (fmt2 x.tol) ")")

fn compileLine2 x: CompileBase -> String
  (str "  (:compile :name " (quoteStr x.name) " :instr " x.instr " :tol " (fmt3 x.tol) ")")

fn gcPolicyLine x: GcPolicy -> String
  (str "  (:gcPolicy :minMib " x.minMib " :label " x.label " :date " (quoteStr x.date) " :method " (quoteStr x.method) " :scope " (quoteStr x.scope) ")")

fn renderBaseline b: Baseline -> String
  (let [(allLines (listAppend (listAppend (cons (idLine b) (cons (methodLineOf b) (map benchLine2 b.benches))) (map compileLine2 b.compiles)) (map gcPolicyLine b.gcPolicy)))]
    (str (stringJoin allLines "\n") ")\n"))

fn withinTolerance base: Float64 tolerance: Float64 measured: Float64 -> Bool
  (<= measured (* base (+ 1.0 tolerance)))

fn maxAllowed base: Float64 tolerance: Float64 -> Float64
  (* base (+ 1.0 tolerance))

fn findRow rows: (List MeasureRow) name: String -> (Option MeasureRow)
  (listHead (filter (fn [(r MeasureRow)] -> Bool (= r.name name)) rows))

; (:m :ref PERFGATE :do "a ratio row may rise past base * (1 + tol) by an absolute 0.05 before it is red, so a base near 0 (a bench whose ASL side uses far less memory than C) is not red for a few KB; compile rows carry no slack. Only a rise is red: a faster tree is reported by --record, never failed")
fn rowTol tol: Float64 default: Float64 -> Float64
  (if (> tol 0.0) tol default)

fn evalOne label: String base: Float64 tol: Float64 slack: Float64 row: (Option MeasureRow) -> (List String)
  (match row
    ((none) (list (str label ": no measurement in this run")))
    ((some r)
     (cond
       ((not r.ok) (list (str label ": measurement failed: " r.note)))
       ((<= r.value (+ (maxAllowed base tol) slack)) (list))
       (else (list (str label ": " (fmt2 r.value) " exceeds baseline " (fmt2 base)
                         " x (1+" (fmt2 tol) ") = " (fmt2 (maxAllowed base tol)) (if (> slack 0.0) " + 0.05" "")))))))

fn evaluate baseline: Baseline benchRows: (List MeasureRow) compileRows: (List MeasureRow) -> (List String)
  (let [(benchDefects (fold (fn [(acc (List String)) (b BenchBase)] -> (List String)
                              (listAppend acc (evalOne (str "bench " b.name) b.ratio (rowTol b.tol baseline.tolerance) 0.05 (findRow benchRows b.name))))
                            (list) baseline.benches))
        (compileDefects (fold (fn [(acc (List String)) (c CompileBase)] -> (List String)
                                (listAppend acc (evalOne (str "compile " c.name) (int64ToFloat64 c.instr) (rowTol c.tol 0.02) 0.0 (findRow compileRows c.name))))
                              (list) baseline.compiles))]
    (listAppend benchDefects compileDefects))

; (:m :ref BENCHPARITY :do "lock rows the gate reads: (:bench ...) (whole-program ratios; a row labelled regression guard compares ASL with C of another structure or amount of work and only tracks the compiler over time), (:parity ...) and (:parityHeadline ...)")
fn benchLine? l: String -> Bool
  (or (stringStartsWith? l "(:bench ") (or (stringStartsWith? l "(:parity ") (stringStartsWith? l "(:parityHeadline ")))

; (:m :ref PERFGATE :do "a (:bench ...) lock row yields two gate rows, NAME/MODE/instr = ASL instructions retired over C and NAME/MODE/rss = ASL peak RSS over C, both computed from the raw counts (not the rounded two-decimal text): wall time is in the lock row for humans and never gated, since a loaded host moves it by +-50% on C runs under 20 ms")
fn ratioOf num: (Option Int64) den: (Option Int64) -> (Option Float64)
  (match num
    ((none) (none))
    ((some n) (match den
                ((none) (none))
                ((some d) (if (or (<= n 0) (<= d 0)) (none) (some (/ (int64ToFloat64 n) (int64ToFloat64 d))))))))

fn rowOf label: String bad: Bool note: String ratio: (Option Float64) -> MeasureRow
  (cond
    (bad (MeasureRow :name label :ok false :value 0.0 :note note))
    ((none? ratio) (MeasureRow :name label :ok false :value 0.0 :note "missing or non-positive count"))
    (else (MeasureRow :name label :ok true :value (optionOr ratio 0.0) :note "")))

; (:m :ref BENCHPARITY :do "a (:parity ASL :c C ...) row yields ASL~C/MODE/marginal, the quotient of per-element instructions (instr(n2) - instr(n1)) of ASL over C, which cancels startup; a row that folds (a side under half an instruction per element) yields no gate row, since it measures startup; a (:parityHeadline ...) row yields parity/MODE/headline, the median same-algorithm marginal ratio")
fn parityRowsFromTop items: (List rd/SExpr) -> (List MeasureRow)
  (let [(asl (textOf (optionOr (listGet items 1) (rd/makeAtom "?"))))
        (c (match (kvGet items ":c") ((some v) (textOf v)) ((none) "?")))
        (mode (match (kvGet items ":mode") ((some m) (textOf m)) ((none) "tracing")))
        (label (str asl "~" c "/" mode "/marginal"))
        (errField (kvGet items ":error"))
        (same (= (atomText (optionOr (kvGet items ":same") (rd/makeAtom ""))) "true"))
        (folds (= (atomText (optionOr (kvGet items ":folds") (rd/makeAtom ""))) "true"))]
    (cond
      ((some? errField) (list (rowOf label true (textOf (optionOr errField (rd/makeAtom ""))) (none))))
      ((not same) (list (rowOf label true "output mismatch (:same false)" (none))))
      (folds (list))
      (else (list (rowOf label false "" (floatOf (kvGet items ":marginalRatio")))))))

fn rowsFromTop top: rd/SExpr -> (List MeasureRow)
  (let [(head (atomText (optionOr (listHead (itemsOf top)) (rd/makeAtom ""))))]
    (cond
      ((= head ":parity") (parityRowsFromTop (itemsOf top)))
      ((= head ":parityHeadline")
       (let [(items (itemsOf top))
             (mode (match (kvGet items ":mode") ((some m) (textOf m)) ((none) "tracing")))]
         (list (rowOf (str "parity/" mode "/headline") false "" (floatOf (kvGet items ":medianMarginalRatio"))))))
      (else (benchRowsFromTop top))))

fn benchRowsFromTop top: rd/SExpr -> (List MeasureRow)
  (let [(items (itemsOf top))
        (name (textOf (optionOr (listGet items 1) (rd/makeAtom "?"))))
        (mode (match (kvGet items ":mode") ((some m) (textOf m)) ((none) "tracing")))
        (base (str name "/" mode))
        (errField (kvGet items ":error"))
        (mismatch (and (some? (kvGet items ":same")) (!= (atomText (optionOr (kvGet items ":same") (rd/makeAtom ""))) "true")))
        (bad (or (some? errField) mismatch))
        (note (if (some? errField) (textOf (optionOr errField (rd/makeAtom ""))) "output mismatch (:same false)"))]
    (list (rowOf (str base "/instr") bad note (ratioOf (intOf (kvGet items ":aslInstr")) (intOf (kvGet items ":cInstr"))))
          (rowOf (str base "/rss") bad note (ratioOf (intOf (kvGet items ":aslRssKb")) (intOf (kvGet items ":cRssKb"))))))

fn parseBenchRows line: String -> (List MeasureRow)
  (match (parseForms line)
    ((err e) (list (MeasureRow :name "?" :ok false :value 0.0 :note (str "bench line does not read: " e))))
    ((ok forms)
     (match (listHead forms)
       ((none) (list (MeasureRow :name "?" :ok false :value 0.0 :note "empty bench line")))
       ((some top) (rowsFromTop top)))))

fn benchRowsFromText text: String -> (List MeasureRow)
  (fold (fn [(acc (List MeasureRow)) (l String)] -> (List MeasureRow) (listAppend acc (parseBenchRows l)))
        (list) (filter benchLine? (stringLines text)))

; (:m :ref HL-FIXWAVE :do "both spawns here used to hardcode asl/host/out/asl-host, the stage-0 interpreter HL-DELETE retired for good; bin/asl (the native CLI launcher, self-building from the asl1 seed) is what runs bench/native/run.asl and asl1.asl now")
fn ! runBenchMeasurements runs: Int64 names: (List String) modes: String -> (List MeasureRow)
  (let [(work (str ".asl/cache/perfGate/" (procSelf)))
        (_ (dirCreate work))
        (lockPath (str work "/benchLock.asn"))
        (_ (pathRemove lockPath))
        (argv (listAppend (list "bin/asl" "run" "bench/native/run.asl" "--runs" (stringFromInt64 runs) "--mode" modes "--parity" "--lock" lockPath) names))
        (_ (nt/runProc argv (none)))
        (text (resultOr (fileReadString lockPath) ""))
        (_ (pathRemove lockPath))]
    (benchRowsFromText text))

fn ! osFlag -> String
  (if (stringContains? (nt/runProc (list "uname" "-s") (none)).stdout "Darwin") "-l" "-v")

; (:m :ref PERFGATE :do "instructions retired of one child tree, from /usr/bin/time -l (Darwin); -1 where the platform prints none (Linux -v has no such line), which the gate reports as an unmeasured row rather than passing it")
fn instrRetired text: String -> Int64
  (match (listHead (filter (fn [(l String)] -> Bool (stringContains? l "instructions retired")) (stringLines text)))
    ((some l) (optionOr (stringToInt64 (optionOr (listHead (stringSplit (stringTrim l) " ")) "")) -1))
    ((none) -1))

fn fixedInputCommit -> String
  "b9c1acb05"

fn ! perfHome -> String
  (str (optionOr (envGet "HOME") ".") "/.asl/run/perfGate")

; (:m :ref PERFGATE :do "FIXED-INPUT-B9C1 (.asl/mem/benchmarks/fixedInput-20261022.asn): git archive of b9c1acb05 asl, unpacked once per machine; the compile workload must not change with the tree under test, only the compiler does")
fn ! fixedInputDir -> (Result String String)
  (let [(dir (str (perfHome) "/fixedInput-" (fixedInputCommit)))]
    (if (fileExists? (str dir "/asl/prelude/prelude.asl"))
      (ok dir)
      (let [(_ (dirCreate dir))
            (tar (str dir ".tar"))
            (a (nt/runProc (list "git" "archive" "--format=tar" "-o" tar (fixedInputCommit) "asl") (none)))]
        (if (!= a.exitCode 0)
          (err (str "git archive " (fixedInputCommit) " failed: " (stringTrim a.stderr)))
          (let [(x (nt/runProc (list "tar" "-xf" tar "-C" dir) (none)))
                (_ (pathRemove tar))]
            (if (!= x.exitCode 0) (err (str "tar failed: " (stringTrim x.stderr))) (ok dir)))))))

fn ! compilerBinary work: String given: (Option String) -> (Result String String)
  (match given
    ((some p) (ok (resultOr (realPath p) p)))
    ((none)
     (let [(out (str work "/asl1.nt"))
           (r (nt/runProc (list "nice" "-n" "10" "bin/asl" "build" "asl/packages/asl-compiler/src/asl1.asl" "-o" out) (none)))]
       (if (= r.exitCode 0) (ok (resultOr (realPath out) out)) (err (str "asl1 build exit " r.exitCode ": " (stringTrim r.stderr)))))))

; (:m :ref PERFGATE :do "compile workload = instructions retired by the tree's notrace asl1 (bin/asl build asl1.asl) compiling FIXED-INPUT-B9C1's asl1.asl to LLVM IR; deterministic to about 0.2% across rounds and loads (2026-10-23 notrace 165.70e9 166.00e9), so the 2% gate does not read load")
fn ! compileWorkloadRow compiler: (Option String) -> MeasureRow
  (let [(name "fixedNt")
        (rel (str ".asl/cache/perfGate/" (procSelf)))
        (_ (dirCreate rel))
        (work (resultOr (realPath rel) rel))]
    (match (fixedInputDir)
      ((err e) (MeasureRow :name name :ok false :value 0.0 :note e))
      ((ok dir)
       (match (compilerBinary work compiler)
         ((err e) (MeasureRow :name name :ok false :value 0.0 :note e))
         ((ok bin)
          (let [(ll (str work "/fixedNt.ll"))
                (env (nt/withEnvOverrides! (list (str "ASL_ROOT=" dir) (str "ASL_PRELUDE=" dir "/asl/prelude/prelude.asl") "ASL_HOST_CACHE=0")))
                (out (nt/runProcIn (list "/usr/bin/time" (osFlag) bin "build" "asl/packages/asl-compiler/src/asl1.asl" "-o" ll) (some dir) (some env)))
                (size (resultOr (fileSize ll) 0))
                (_ (pathRemove ll))]
            (if (or (!= out.exitCode 0) (<= size 0))
              (MeasureRow :name name :ok false :value 0.0 :note (str "fixedNt compile failed (exit " out.exitCode ", ll bytes " size "): " (stringTrim out.stderr)))
              (let [(n (instrRetired out.stderr))]
                (if (<= n 0)
                  (MeasureRow :name name :ok false :value 0.0 :note "no instructions retired line in /usr/bin/time output")
                  (MeasureRow :name name :ok true :value (int64ToFloat64 n) :note ""))))))))))

fn civilDate ns: Int64 -> String
  (let [(z (+ (/ ns 86400000000000) 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (- (+ doe (/ doe 36524)) (/ doe 1460)) (/ doe 146096)) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str y "-" (if (< m 10) "0" "") m "-" (if (< d 10) "0" "") d))

fn ! hostLine -> String
  (let [(u (stringTrim (nt/runProc (list "uname" "-sm") (none)).stdout))
        (cv (optionOr (listHead (stringLines (nt/runProc (list "clang" "--version") (none)).stdout)) ""))
        (darwin (stringContains? (nt/runProc (list "uname" "-s") (none)).stdout "Darwin"))
        (load (stringTrim (if darwin
                             (nt/runProc (list "sysctl" "-n" "vm.loadavg") (none)).stdout
                             (nt/runProc (list "cat" "/proc/loadavg") (none)).stdout)))]
    (str u "; " cv "; load " load))

fn methodText -> String
  (str "bench/native/run.asl --mode both: 19 benches, clang -O2 C vs ASL built twice, notrace (bin/asl build, the CLI default) and tracing (tools/nativeTest, rc 0), same argv size; "
       "gated ratios are ASL/C instructions retired and ASL/C peak RSS (/usr/bin/time -l, deterministic, load-free), never wall time; rows labelled regression guard compare with C of another structure or work and only track the compiler; "
       "--parity adds NAME~C/MODE/marginal rows (per-element instructions at n2 minus n1, ASL over C, same algorithm or idiomatic C, folded rows left out) and parity/MODE/headline (median same-algorithm marginal ratio); "
       "compile = instructions retired by the tree's notrace asl1 compiling FIXED-INPUT-B9C1 (git archive b9c1acb05 asl) asl1.asl to LLVM IR; "
       "gate fails when a row exceeds baseline * (1 + its tol) (+0.05 absolute on ratio rows)")

fn ! defaultBaselinePath -> String
  (str (optionOr (envGet "ASL_ROOT") ".") "/.asl/mem/bench/perfBaseline.asn")

fn optValue args: (List String) flag: String -> (Option String)
  (match (listHead args)
    ((none) (none))
    ((some a) (if (= a flag) (listGet args 1) (optValue (optionOr (listTail args) (list)) flag))))

fn flagTakesValue? flag: String -> Bool
  (listContains? (list "--baseline" "--runs" "--tolerance" "--modes" "--compiler") flag)

fn positional args: (List String) acc: (List String) -> (List String)
  (match (listHead args)
    ((none) (listReverse acc))
    ((some a) (if (stringStartsWith? a "--")
                (positional (listDrop args (if (flagTakesValue? a) 2 1)) acc)
                (positional (listDrop args 1) (cons a acc)))))

; (:m :ref PERFGATE :do "adopted tolerances (2026-10-23): instructions-retired ratio rows 0.15, peak-RSS ratio rows 0.25, fixedNt compile instructions 0.02; the ratio rows are far steadier than wall time (fib notrace 1211520824 vs 1211574072 C instructions in two runs), so these are wide against noise and narrow against a real slowdown")
fn rowTolFor name: String tolArg: (Option Float64) -> Float64
  (match tolArg
    ((some t) t)
    ((none) (if (stringEndsWith? name "/rss") 0.25 0.15)))

fn ! measureAll runs: Int64 names: (List String) modes: String compiler: (Option String) skipBench: Bool skipCompile: Bool -> (Pair (List MeasureRow) (List MeasureRow))
  (pair (if skipBench (list) (runBenchMeasurements runs names modes))
        (if skipCompile (list) (list (compileWorkloadRow compiler))))

fn ! recordRun baselinePath: String runs: Int64 names: (List String) tolArg: (Option String) modes: String compiler: (Option String) -> (Result Int64 String)
  (let [(measured (measureAll runs names modes compiler false false))
        (benchRows (pairFirst measured))
        (compileRows (pairSecond measured))
        (prior (loadBaseline baselinePath))
        (tol (match tolArg
               ((some s) (some (optionOr (stringToFloat64 s) 0.35)))
               ((none) (none))))
        (okBenches (filter (fn [(r MeasureRow)] -> Bool r.ok) benchRows))
        (okCompiles (filter (fn [(r MeasureRow)] -> Bool r.ok) compileRows))
        (failed (listAppend (filter (fn [(r MeasureRow)] -> Bool (not r.ok)) benchRows)
                             (filter (fn [(r MeasureRow)] -> Bool (not r.ok)) compileRows)))
        (newBaseline (Baseline :id "nativePerfGate" :date (civilDate (nowNs)) :host (hostLine) :method (methodText)
                                :tolerance 0.35 :toleranceLabel "adopted"
                                :benches (map (fn [(r MeasureRow)] -> BenchBase (BenchBase :name r.name :ratio r.value :tol (rowTolFor r.name tol))) okBenches)
                                :compiles (map (fn [(r MeasureRow)] -> CompileBase (CompileBase :name r.name :instr (optionOr (float64ToInt64 r.value) 0) :tol (optionOr tol 0.02))) okCompiles)
                                :gcPolicy (match prior ((ok b) b.gcPolicy) ((err _) (list)))))]
    (do
      (fold (fn [(acc Unit) (r MeasureRow)] -> Unit (do (eprintln (str "perfGate: " r.name " did not measure: " r.note)) acc)) () failed)
      (match (dirCreate (str (optionOr (envGet "ASL_ROOT") ".") "/.asl/mem/bench"))
        ((err _) ())
        ((ok _) ()))
      (if (not (listEmpty? failed))
        (err "perfGate: --record refused, some rows did not measure (a baseline must hold every row)")
        (match (fileWrite baselinePath (renderBaseline newBaseline))
          ((err e) (err (str "perfGate: cannot write " baselinePath ": " e)))
          ((ok _) (do (println (renderBaseline newBaseline)) (ok 0)))))))

fn ! checkRun baselinePath: String runs: Int64 names: (List String) modes: String compiler: (Option String) skipBench: Bool skipCompile: Bool -> (Result Int64 String)
  (match (loadBaseline baselinePath)
    ((err e) (err e))
    ((ok baseline)
     (let [(measured (measureAll runs names modes compiler skipBench skipCompile))
           (benchRows (pairFirst measured))
           (compileRows (pairSecond measured))
           (inScope (Baseline :id baseline.id :date baseline.date :host baseline.host :method baseline.method
                              :tolerance baseline.tolerance :toleranceLabel baseline.toleranceLabel
                              :benches (if skipBench (list) (filter (fn [(b BenchBase)] -> Bool (and (or (= modes "both") (= modes (benchMode b.name))) (or (listEmpty? names) (listContains? names (benchOf b.name))))) baseline.benches))
                              :compiles (if skipCompile (list) baseline.compiles)
                              :gcPolicy baseline.gcPolicy))
           (defects (evaluate inScope benchRows compileRows))]
       (do (fold (fn [(acc Unit) (d String)] -> Unit (do (eprintln (str "perfGate: " d)) acc)) () defects)
           (println (str "(:perfGate :rows " (+ (listLength benchRows) (listLength compileRows)) " :defects " (listLength defects) ")"))
           (ok (if (listEmpty? defects) 0 1))))))

fn benchMode name: String -> String
  (optionOr (listGet (stringSplit name "/") 1) "")

fn benchOf name: String -> String
  (optionOr (listHead (stringSplit name "/")) "")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(record (listContains? args "--record"))
        (baselinePath (optionOr (optValue args "--baseline") (defaultBaselinePath)))
        (runs (optionOr (stringToInt64 (optionOr (optValue args "--runs") "1")) 1))
        (tolArg (optValue args "--tolerance"))
        (modes (optionOr (optValue args "--modes") "both"))
        (compiler (optValue args "--compiler"))
        (names (positional args (list)))]
    (if record
      (recordRun baselinePath runs names tolArg modes compiler)
      (checkRun baselinePath runs names modes compiler (listContains? args "--skip-bench") (listContains? args "--skip-compile"))))
