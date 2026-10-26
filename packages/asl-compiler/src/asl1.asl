(module asl-compiler/asl1 :x [main usage] :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/check :a chk) (asl-checker/types :a ty) (asl-compiler/compiler :a comp) (asl-compiler/checkCache :a cc)])

fn usage -> String
  "usage: asl1 build ENTRY -o OUT.ll [--rc 0|1|asan|notrace] [--target linux-aarch64|linux-x86_64|darwin-arm64] | asl1 check ENTRY | asl1 deps ENTRY"

fn roots -> (List String)
  (list ".")

fn ! report diags: (List String) -> (Result Int64 String)
  (match (listHead diags)
    ((none) (ok 1))
    ((some d) (do (eprintln d)
                  (report (optionOr (listTail diags) (list))))))

fn ! build entry: String out: String rcMode: String target: String -> (Result Int64 String)
  (match (comp/compilePackageToLlvmFor! entry (roots) rcMode target)
    ((err e) (report (list e)))
    ((ok cr) (if cr.ok
               (match (fileWrite out cr.code)
                 ((err _) (report (list (str out ": [ERR_IO] cannot write the LLVM IR"))))
                 ((ok _) (ok 0)))
               (report cr.diagnostics))))

fn diagBody diags: (List String) -> String
  (stringJoin (map (fn [(d String)] -> String (str d "\n")) diags) "")

fn failed diags: (List String) -> (Option cc/Verdict)
  (some (cc/Verdict :exitCode 1 :body (diagBody diags)))

fn checkRoots -> (List String)
  (list "." "asl/packages" "asl")

fn ! verdictOf entry: String -> (Option cc/Verdict)
  (match (fileReadString entry)
    ((err _) (failed (list (str entry ": [ERR_IO] cannot read the entry"))))
    ((ok _) (match (chk/checkFile! entry (checkRoots))
              ((err _) (none))
              ((ok diags) (if (listEmpty? diags)
                            (some (cc/Verdict :exitCode 0 :body ""))
                            (failed (map comp/formatDiagnostic diags)))))))

fn ! remember key: (Option String) v: cc/Verdict -> Unit
  (match key
    ((none) ())
    ((some k) (match (cc/store! k v)
      ((ok _) ())
      ((err e) (do (eprintln (str "asl1: [cache] verdict not stored: " e)) ())))))

fn ! check entry: String -> (Result Int64 String)
  (let [(key (cc/verdictKey! entry))]
    (match (match key ((some k) (cc/lookup! k)) ((none) (none)))
      ((some v) (cc/replay! v))
      ((none) (match (verdictOf entry)
        ((none) (report (list (str entry ": [ERR_LOAD] its imports do not load"))))
        ((some v) (let [(out (cc/replay! v))] (do (remember key v) out)))))))

fn distinctSorted xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (listHead acc) (some x)) acc (cons x acc))) (list) (listSort xs)))

fn rootRelative root: String p: String -> String
  (let [(prefix (str root "/"))]
    (if (stringStartsWith? p prefix) (optionOr (stringSlice p (stringLength prefix) (stringLength p)) p) p))

fn ! deps entry: String -> (Result Int64 String)
  (match (fileReadString entry)
    ((err _) (report (list (str entry ": [ERR_IO] cannot read the entry"))))
    ((ok src) (match (a/parse src)
                ((err pe) (report (list (str entry ":" pe.line ":" pe.col ": [parse-error] " pe.msg))))
                ((ok forms) (let [(summary (r/collectSummary forms entry))]
                              (match (r/loadModuleDeps! (cons (r/parentDirOf entry) (roots)) (r/mapValuesList summary.imports))
                                ((err _) (report (list (str entry ": [ERR_LOAD] its imports do not load"))))
                                ((ok closure) (let [(root (resultOr (realPath ".") ""))
                                                     (absPaths (filter (fn [(k String)] -> Bool (stringStartsWith? k "/")) (mapKeys closure)))
                                                     (relPaths (map (fn [(p String)] -> String (rootRelative root p)) absPaths))]
                                                (do (println (stringJoin (distinctSorted relPaths) "\n"))
                                                    (ok 0))))))))))

; (:m :ref RV1 :do "build flags after -o OUT come in --rc MODE and --target TRIPLE pairs in any order, a later pair overriding an earlier one; an unknown flag or a flag without its value is a usage error")
fn buildFlags rest: (List String) rcMode: String target: String -> (Option (Pair String String))
  (match (listHead rest)
    ((none) (some (pair rcMode target)))
    ((some flag) (match (listGet rest 1)
                   ((none) (none))
                   ((some v) (cond
                               ((= flag "--rc") (buildFlags (listDrop rest 2) v target))
                               ((= flag "--target") (buildFlags (listDrop rest 2) rcMode v))
                               (else (none)))))))

fn ! usageError -> (Result Int64 String)
  (do (eprintln (usage))
      (ok 2))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listGet args 0) ""))
        (entry (optionOr (listGet args 1) ""))]
    (cond
      ((and (= cmd "build") (and (>= (listLength args) 4) (= (optionOr (listGet args 2) "") "-o")))
       (match (buildFlags (listDrop args 4) "0" "")
         ((none) (usageError))
         ((some p) (build entry (optionOr (listGet args 3) "") (pairFirst p) (pairSecond p)))))
      ((and (= cmd "check") (= (listLength args) 2)) (check entry))
      ((and (= cmd "deps") (= (listLength args) 2)) (deps entry))
      (else (usageError))))
