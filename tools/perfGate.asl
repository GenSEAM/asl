(module asl-tools/perfGate
  :x [main Baseline BenchBase CompileBase GcPolicy MeasureRow
      parseForms atomText itemsOf kvGet unquote stripColon textOf quoteStr floatOf intOf
      loadBaselineText loadBaseline renderBaseline
      withinTolerance maxAllowed evaluate findRow
      benchLine? parseBenchLine benchRowsFromText runBenchMeasurements
      osFlag userMsOf compileWorkloadRow hostLine methodText defaultBaselinePath fmt2
      flagTakesValue? positional optValue]
  :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-tools/nativeTest :a nt)])

(schema BenchBase (:f name String) (:f ratio Float64))
(schema CompileBase (:f name String) (:f userMs Int64))
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

fn subForms items: (List rd/SExpr) tag: String -> (List rd/SExpr)
  (filter (fn [(it rd/SExpr)] -> Bool (= (atomText (optionOr (listHead (itemsOf it)) (rd/makeAtom ""))) tag)) items)

fn parseBenchBase row: rd/SExpr -> BenchBase
  (let [(items (itemsOf row))]
    (BenchBase :name (textOf (optionOr (kvGet items ":name") (rd/makeAtom "")))
               :ratio (optionOr (floatOf (kvGet items ":ratio")) 0.0)))

fn parseCompileBase row: rd/SExpr -> CompileBase
  (let [(items (itemsOf row))]
    (CompileBase :name (textOf (optionOr (kvGet items ":name") (rd/makeAtom "")))
                 :userMs (optionOr (intOf (kvGet items ":userMs")) 0)))

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
  (str "  (:bench :name " (quoteStr x.name) " :ratio " (fmt2 x.ratio) ")")

fn compileLine2 x: CompileBase -> String
  (str "  (:compile :name " (quoteStr x.name) " :userMs " x.userMs ")")

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

fn evalOne label: String base: Float64 tol: Float64 row: (Option MeasureRow) -> (List String)
  (match row
    ((none) (list (str label ": no measurement in this run")))
    ((some r)
     (cond
       ((not r.ok) (list (str label ": measurement failed: " r.note)))
       ((withinTolerance base tol r.value) (list))
       (else (list (str label ": " (fmt2 r.value) " exceeds baseline " (fmt2 base)
                         " x (1+" (fmt2 tol) ") = " (fmt2 (maxAllowed base tol))))))))

fn evaluate baseline: Baseline benchRows: (List MeasureRow) compileRows: (List MeasureRow) -> (List String)
  (let [(benchDefects (fold (fn [(acc (List String)) (b BenchBase)] -> (List String)
                              (listAppend acc (evalOne (str "bench " b.name) b.ratio baseline.tolerance (findRow benchRows b.name))))
                            (list) baseline.benches))
        (compileDefects (fold (fn [(acc (List String)) (c CompileBase)] -> (List String)
                                (listAppend acc (evalOne (str "compile " c.name) (int64ToFloat64 c.userMs) baseline.tolerance (findRow compileRows c.name))))
                              (list) baseline.compiles))]
    (listAppend benchDefects compileDefects))

fn benchLine? l: String -> Bool
  (stringStartsWith? l "(:bench ")

fn rowFromFields name: String errField: (Option rd/SExpr) sameField: (Option rd/SExpr) ratioField: (Option rd/SExpr) -> MeasureRow
  (cond
    ((some? errField) (MeasureRow :name name :ok false :value 0.0 :note (textOf (optionOr errField (rd/makeAtom "")))))
    ((none? ratioField) (MeasureRow :name name :ok false :value 0.0 :note "no :ratio field"))
    ((and (some? sameField) (!= (atomText (optionOr sameField (rd/makeAtom ""))) "true"))
     (MeasureRow :name name :ok false :value (optionOr (floatOf ratioField) 0.0) :note "output mismatch (:same false)"))
    (else (MeasureRow :name name :ok true :value (optionOr (floatOf ratioField) 0.0) :note "")))

fn rowFromTop top: rd/SExpr -> MeasureRow
  (let [(items (itemsOf top))
        (name (textOf (optionOr (listGet items 1) (rd/makeAtom "?"))))]
    (rowFromFields name (kvGet items ":error") (kvGet items ":same") (kvGet items ":ratio")))

fn parseBenchLine line: String -> MeasureRow
  (match (parseForms line)
    ((err e) (MeasureRow :name "?" :ok false :value 0.0 :note (str "bench line does not read: " e)))
    ((ok forms)
     (match (listHead forms)
       ((none) (MeasureRow :name "?" :ok false :value 0.0 :note "empty bench line"))
       ((some top) (rowFromTop top)))))

fn benchRowsFromText text: String -> (List MeasureRow)
  (map parseBenchLine (filter benchLine? (stringLines text)))

; (:m :ref HL-FIXWAVE :do "both spawns here used to hardcode asl/host/out/asl-host, the stage-0 interpreter HL-DELETE retired for good; bin/asl (the native CLI launcher, self-building from the asl1 seed) is what runs bench/native/run.asl and asl1.asl now")
fn ! runBenchMeasurements runs: Int64 names: (List String) -> (List MeasureRow)
  (let [(work (str ".asl/cache/perfGate/" (procSelf)))
        (_ (dirCreate work))
        (lockPath (str work "/benchLock.asn"))
        (_ (pathRemove lockPath))
        (argv (listAppend (list "bin/asl" "run" "bench/native/run.asl" "--runs" (stringFromInt64 runs) "--lock" lockPath) names))
        (_ (nt/runProc argv (none)))
        (text (resultOr (fileReadString lockPath) ""))
        (_ (pathRemove lockPath))]
    (benchRowsFromText text))

fn ! osFlag -> String
  (if (stringContains? (nt/runProc (list "uname" "-s") (none)).stdout "Darwin") "-l" "-v")

fn userMsOf text: String -> Int64
  (let [(lines (stringLines text))
        (macLine (listHead (filter (fn [(l String)] -> Bool (stringContains? l " user")) lines)))
        (gnuLine (listHead (filter (fn [(l String)] -> Bool (stringContains? l "User time (seconds):")) lines)))]
    (match macLine
      ((some l)
       (let [(before (optionOr (listHead (stringSplit l " user")) ""))
             (toks (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit before " ")))]
         (optionOr (float64ToInt64 (* (optionOr (stringToFloat64 (optionOr (listGet toks (- (listLength toks) 1)) "")) -0.001) 1000.0)) -1)))
      ((none)
       (match gnuLine
         ((some l) (optionOr (float64ToInt64 (* (optionOr (stringToFloat64 (stringTrim (optionOr (listGet (stringSplit l ":") 1) ""))) -0.001) 1000.0)) -1))
         ((none) -1)))))

fn ! compileWorkloadRow -> MeasureRow
  (let [(name "tools/corpusNativeMain.asl")
        (work (str ".asl/cache/perfGate/" (procSelf)))
        (_ (dirCreate work))
        (ll (str work "/corpusNativeMain.ll"))
        (argv (list "/usr/bin/time" (osFlag) "nice" "-n" "15" "bin/asl" "run"
                    "asl/packages/asl-compiler/src/asl1.asl" "build" name "-o" ll))
        (out (nt/runProc argv (none)))
        (_ (pathRemove ll))]
    (if (!= out.exitCode 0)
      (MeasureRow :name name :ok false :value 0.0 :note (str "cold build failed (exit " out.exitCode "): " (stringTrim out.stderr)))
      (let [(u (userMsOf out.stderr))]
        (if (< u 0)
          (MeasureRow :name name :ok false :value 0.0 :note (str "could not parse /usr/bin/time output: " (stringTrim out.stderr)))
          (MeasureRow :name name :ok true :value (int64ToFloat64 u) :note "")))))

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
  (str "bench/native/run.asl: clang -O2 C vs asl/tools/nativeTest native ASL (clang -O2 over emitted LLVM IR), "
       "same argv size, best of N wall-clock runs per binary, ratio = asl/c (ratio is load-robust: both sides "
       "share the same ambient load back to back); compile = /usr/bin/time user seconds for a cold asl1 build "
       "of tools/corpusNativeMain.asl to LLVM IR (direct asl1 CLI invocation, no clang link, no nativeTest "
       "module cache, so it is always a cold compile); gate fails when a bench ratio or the compile user time "
       "exceeds baseline * (1 + tolerance)")

fn ! defaultBaselinePath -> String
  (str (optionOr (envGet "ASL_ROOT") ".") "/.asl/mem/bench/perfBaseline.asn")

fn optValue args: (List String) flag: String -> (Option String)
  (match (listHead args)
    ((none) (none))
    ((some a) (if (= a flag) (listGet args 1) (optValue (optionOr (listTail args) (list)) flag))))

fn flagTakesValue? flag: String -> Bool
  (listContains? (list "--baseline" "--runs" "--tolerance") flag)

fn positional args: (List String) acc: (List String) -> (List String)
  (match (listHead args)
    ((none) (listReverse acc))
    ((some a) (if (stringStartsWith? a "--")
                (positional (listDrop args (if (flagTakesValue? a) 2 1)) acc)
                (positional (listDrop args 1) (cons a acc)))))

fn ! recordRun baselinePath: String runs: Int64 names: (List String) tolArg: (Option String) -> (Result Int64 String)
  (let [(benchRows (runBenchMeasurements runs names))
        (compileRows (list (compileWorkloadRow)))
        (prior (loadBaseline baselinePath))
        (tol (match tolArg
               ((some s) (optionOr (stringToFloat64 s) 0.35))
               ((none) (match prior ((ok b) b.tolerance) ((err _) 0.35)))))
        (okBenches (filter (fn [(r MeasureRow)] -> Bool r.ok) benchRows))
        (okCompiles (filter (fn [(r MeasureRow)] -> Bool r.ok) compileRows))
        (failed (listAppend (filter (fn [(r MeasureRow)] -> Bool (not r.ok)) benchRows)
                             (filter (fn [(r MeasureRow)] -> Bool (not r.ok)) compileRows)))
        (newBaseline (Baseline :id "nativePerfGate" :date (civilDate (nowNs)) :host (hostLine) :method (methodText)
                                :tolerance tol :toleranceLabel "adopted"
                                :benches (map (fn [(r MeasureRow)] -> BenchBase (BenchBase :name r.name :ratio r.value)) okBenches)
                                :compiles (map (fn [(r MeasureRow)] -> CompileBase (CompileBase :name r.name :userMs (optionOr (float64ToInt64 r.value) 0))) okCompiles)
                                :gcPolicy (match prior ((ok b) b.gcPolicy) ((err _) (list)))))]
    (do
      (fold (fn [(acc Unit) (r MeasureRow)] -> Unit (do (eprintln (str "perfGate: " r.name " did not measure: " r.note)) acc)) () failed)
      (match (dirCreate (str (optionOr (envGet "ASL_ROOT") ".") "/.asl/mem/bench"))
        ((err _) ())
        ((ok _) ()))
      (match (fileWrite baselinePath (renderBaseline newBaseline))
        ((err e) (err (str "perfGate: cannot write " baselinePath ": " e)))
        ((ok _) (do (println (renderBaseline newBaseline)) (ok 0))))))

fn ! checkRun baselinePath: String runs: Int64 names: (List String) -> (Result Int64 String)
  (match (loadBaseline baselinePath)
    ((err e) (err e))
    ((ok baseline)
     (let [(benchRows (runBenchMeasurements runs names))
           (compileRows (list (compileWorkloadRow)))
           (defects (evaluate baseline benchRows compileRows))]
       (do (fold (fn [(acc Unit) (d String)] -> Unit (do (eprintln (str "perfGate: " d)) acc)) () defects)
           (ok (if (listEmpty? defects) 0 1))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(record (listContains? args "--record"))
        (baselinePath (optionOr (optValue args "--baseline") (defaultBaselinePath)))
        (runs (optionOr (stringToInt64 (optionOr (optValue args "--runs") "3")) 3))
        (tolArg (optValue args "--tolerance"))
        (names (positional args (list)))]
    (if record
      (recordRun baselinePath runs names tolArg)
      (checkRun baselinePath runs names)))
