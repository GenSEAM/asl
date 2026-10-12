(module asl-checker/checkCached
  :x [Cache emptyCache Verdict checkFileCached!]
  :i [(types :a ty) (resolve :a r) (ast :a a) (check :a chk)])

(schema Cache (:f index r/ModIndex))

(schema Verdict (:f diags (List ty/Diagnostic)) (:f moduleCount Int64))

fn emptyCache -> Cache
  (Cache :index (r/emptyModIndex))

fn parseErrDiag pe: a/ParseError path: String -> (List ty/Diagnostic)
  (list (ty/Diagnostic :code "parse" :message pe.msg :msg pe.msg :line pe.line :col pe.col :path path))

fn classify cl: r/ModuleClosure -> (Result (Map String r/ModuleSummary) IoError)
  (cond
    ((not (listEmpty? cl.unresolved)) (err (notFound)))
    ((not (listEmpty? cl.errors)) (err (other)))
    (else (ok cl.deps)))

fn ! checkFileCached! path: String roots: (List String) cache: Cache -> (Pair (Result Verdict IoError) Cache)
  (mt (fileRead path)
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
              ((err ioErr2) (pair (err ioErr2) nextCache))
              ((ok deps) (pair (ok (Verdict :diags (chk/checkModuleSource forms deps path src) :moduleCount (+ 1 (listLength (mapKeys deps))))) nextCache))))))))
