(module asl-compiler/asl1 :x [main usage] :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/check :a chk) (asl-checker/types :a ty) (asl-compiler/compiler :a comp)])

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

fn ! check entry: String -> (Result Int64 String)
  (mt (fileRead entry)
    ((err _) (report (list (str entry ": [ERR_IO] cannot read the entry"))))
    ((ok src) (mt (a/parse src)
                ((err pe) (report (list (str entry ":" pe.line ":" pe.col ": [parse-error] " pe.msg))))
                ((ok forms) (let [(summary (r/collectSummary forms entry))]
                              (mt (r/loadModuleDeps! (cons (r/parentDirOf entry) (roots)) (r/mapValuesList summary.imports))
                                ((err _) (report (list (str entry ": [ERR_LOAD] its imports do not load"))))
                                ((ok deps) (let [(diags (chk/checkModule forms deps entry))]
                                             (if (listEmpty? diags)
                                               (ok 0)
                                               (report (map comp/formatDiagnostic diags)))))))))))

fn distinctSorted xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (listHead acc) (some x)) acc (cons x acc))) (list) (listSort xs)))

fn ! deps entry: String -> (Result Int64 String)
  (mt (fileRead entry)
    ((err _) (report (list (str entry ": [ERR_IO] cannot read the entry"))))
    ((ok src) (mt (a/parse src)
                ((err pe) (report (list (str entry ":" pe.line ":" pe.col ": [parse-error] " pe.msg))))
                ((ok forms) (mt (r/loadModuleDeps! (cons (r/parentDirOf entry) (roots)) (r/mapValuesList (r/collectSummary forms entry).imports))
                              ((err _) (report (list (str entry ": [ERR_LOAD] its imports do not load"))))
                              ((ok closure) (do (println (stringJoin (distinctSorted (filter (fn [(k String)] -> Bool (stringStartsWith? k "/")) (mapKeys closure))) "\n"))
                                                (ok 0))))))))

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
