(module asl-checker/checkCached
  :x [Cache emptyCache Verdict checkFileCached!]
  :i [(types :a ty) (resolve :a r) (ast :a a) (check :a chk)])

(schema Cache (:f index r/ModIndex))

(schema Verdict (:f diags (List ty/Diagnostic)) (:f moduleCount Int64))

fn emptyCache -> Cache
  (Cache :index (r/emptyModIndex))

fn parseErrDiag pe: a/ParseError path: String -> (List ty/Diagnostic)
  (list (ty/Diagnostic :code "parse" :message pe.msg :msg pe.msg :line pe.line :col pe.col :path path))

fn classify cl: r/ModuleClosure -> (Result (Map String r/ModuleSummary) String)
  (cond
    ((not (listEmpty? cl.unresolved)) (err "notFound"))
    ((not (listEmpty? cl.errors)) (err "other"))
    (else (ok cl.deps)))

fn loadLineDiag path: String line: String -> ty/Diagnostic
  (let [(at (optionOr (stringIndexOf line ": ERR_") -1))
        (rest (if (< at 0) line (optionOr (stringSlice line (+ at 2) (stringLength line)) line)))
        (sp (optionOr (stringIndexOf rest " ") (stringLength rest)))
        (code (if (< at 0) "ERR_IO" (optionOr (stringSlice rest 0 sp) "ERR_IO")))
        (msg (if (< at 0) line (stringTrim (optionOr (stringSlice rest sp (stringLength rest)) ""))))]
    (ty/Diagnostic :code code :message msg :msg msg :line 0 :col 0 :path path))

fn closureDiags path: String cl: r/ModuleClosure -> (List ty/Diagnostic)
  (map (fn [(l String)] -> ty/Diagnostic (loadLineDiag path l)) (listAppend cl.unresolved cl.errors))

fn ! checkFileCached! path: String roots: (List String) cache: Cache -> (Pair (Result Verdict String) Cache)
  (mt (fileReadString path)
    ((err ioErr) (pair (err ioErr) cache))
    ((ok src)
      (mt (a/parseForTypeCheck src)
        ((err pe) (pair (ok (Verdict :diags (parseErrDiag pe path) :moduleCount 1)) cache))
        ((ok forms)
          (let [(summary (r/collectSummary forms path))
                (importPaths (r/mapValuesList summary.imports))
                (allRoots (cons (r/parentDirOf path) roots))
                (cl (r/loadModuleDepsFrom! allRoots importPaths (mapEmpty) cache.index))
                (nextCache (Cache :index cl.index))]
            (mt (classify cl)
              ((err _) (pair (ok (Verdict :diags (closureDiags path cl) :moduleCount (+ 1 (listLength (mapKeys cl.deps))))) nextCache))
              ((ok deps) (pair (ok (Verdict :diags (chk/checkModuleSource forms deps path src) :moduleCount (+ 1 (listLength (mapKeys deps))))) nextCache))))))))
