(module asl-compiler/asl1 :x [main usage] :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/check :a chk) (asl-checker/types :a ty) (asl-compiler/compiler :a comp) (asl-compiler/checkCache :a cc)])

fn usage -> String
  "usage: asl1 build ENTRY -o OUT.ll | asl1 check ENTRY | asl1 deps ENTRY"

fn roots -> (List String)
  (list ".")

fn ! report diags: (List String) -> (Result Int64 String)
  (mt (listHead diags)
    ((none) (ok 1))
    ((some d) (do (eprintln d)
                  (report (optionOr (listTail diags) (list))))))

fn ! build entry: String out: String -> (Result Int64 String)
  (mt (comp/compilePackageToLlvm! entry (roots))
    ((err e) (report (list e)))
    ((ok cr) (if cr.ok
               (mt (fileWrite out cr.code)
                 ((err _) (report (list (str out ": [ERR_IO] cannot write the LLVM IR"))))
                 ((ok _) (ok 0)))
               (report cr.diagnostics))))

fn diagBody diags: (List String) -> String
  (stringJoin (map (fn [(d String)] -> String (str d "\n")) diags) "")

fn failed diags: (List String) -> (Option cc/Verdict)
  (some (cc/Verdict :exitCode 1 :body (diagBody diags)))

fn ! verdictOf entry: String -> (Option cc/Verdict)
  (mt (fileRead entry)
    ((err _) (failed (list (str entry ": [ERR_IO] cannot read the entry"))))
    ((ok src) (mt (a/parse src)
                ((err pe) (failed (list (str entry ":" pe.line ":" pe.col ": [parse-error] " pe.msg))))
                ((ok forms) (let [(summary (r/collectSummary forms entry))]
                              (mt (r/loadModuleDeps! (cons (r/parentDirOf entry) (roots)) (r/mapValuesList summary.imports))
                                ((err _) (none))
                                ((ok deps) (let [(diags (chk/checkModule forms deps entry))]
                                             (if (listEmpty? diags)
                                               (some (cc/Verdict :exitCode 0 :body ""))
                                               (failed (map comp/formatDiagnostic diags)))))))))))

fn ! remember key: (Option String) v: cc/Verdict -> Unit
  (mt key
    ((none) ())
    ((some k) (mt (cc/store! k v)
      ((ok _) ())
      ((err e) (do (eprintln (str "asl1: [cache] verdict not stored: " e)) ())))))

fn ! check entry: String -> (Result Int64 String)
  (let [(key (cc/verdictKey! entry))]
    (mt (mt key ((some k) (cc/lookup! k)) ((none) (none)))
      ((some v) (cc/replay! v))
      ((none) (mt (verdictOf entry)
        ((none) (report (list (str entry ": [ERR_LOAD] its imports do not load"))))
        ((some v) (let [(out (cc/replay! v))] (do (remember key v) out)))))))

fn distinctSorted xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (listHead acc) (some x)) acc (cons x acc))) (list) (listSort xs)))

fn rootRelative root: String p: String -> String
  (let [(prefix (str root "/"))]
    (if (stringStartsWith? p prefix) (optionOr (stringSlice p (stringLength prefix) (stringLength p)) p) p))

fn ! deps entry: String -> (Result Int64 String)
  (mt (fileRead entry)
    ((err _) (report (list (str entry ": [ERR_IO] cannot read the entry"))))
    ((ok src) (mt (a/parse src)
                ((err pe) (report (list (str entry ":" pe.line ":" pe.col ": [parse-error] " pe.msg))))
                ((ok forms) (let [(summary (r/collectSummary forms entry))]
                              (mt (r/loadModuleDeps! (cons (r/parentDirOf entry) (roots)) (r/mapValuesList summary.imports))
                                ((err _) (report (list (str entry ": [ERR_LOAD] its imports do not load"))))
                                ((ok closure) (let [(root (resultOr (pathCanonicalize ".") ""))
                                                     (absPaths (filter (fn [(k String)] -> Bool (stringStartsWith? k "/")) (mapKeys closure)))
                                                     (relPaths (map (fn [(p String)] -> String (rootRelative root p)) absPaths))]
                                                (do (println (stringJoin (distinctSorted relPaths) "\n"))
                                                    (ok 0))))))))))

fn ! usageError -> (Result Int64 String)
  (do (eprintln (usage))
      (ok 2))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listGet args 0) ""))
        (entry (optionOr (listGet args 1) ""))]
    (cond
      ((and (= cmd "build") (and (= (listLength args) 4) (= (optionOr (listGet args 2) "") "-o"))) (build entry (optionOr (listGet args 3) "")))
      ((and (= cmd "check") (= (listLength args) 2)) (check entry))
      ((and (= cmd "deps") (= (listLength args) 2)) (deps entry))
      (else (usageError))))
