(module asl-checker/checkCached
  :x [Cache emptyCache stampCacheAt stampedCache! stampKeyIn! Verdict countsText checkFileCached!]
  :i [(types :a ty) (resolve :a r) (ast :a a) (check :a chk)])

; (:m :ref CHECK-IMPORTS-HONEST :do "bodies maps the real path of each module whose body this process checked to its diagnostics, so a sweep checks a shared dependency once and every later importer counts it as summarised")
; (:m :ref CHECK-IMPORTS-HONEST :do "stampDir and checkerId name where a clean dependency closure is stamped across runs; an empty checkerId keeps the stamps off")
(schema Cache (:f index r/ModIndex) (:f bodies (Map String (List ty/Diagnostic))) (:f stampDir String) (:f checkerId String))

(schema Verdict (:f diags (List ty/Diagnostic)) (:f checked Int64) (:f summarised Int64))

(schema Tally (:f diags (List ty/Diagnostic)) (:f checked Int64) (:f summarised Int64) (:f cache Cache))

fn emptyCache -> Cache
  (Cache :index (r/emptyModIndex) :bodies (mapEmpty) :stampDir "" :checkerId "")

fn stampCacheAt dir: String checkerId: String -> Cache
  (Cache :index (r/emptyModIndex) :bodies (mapEmpty) :stampDir dir :checkerId checkerId)

; (:m :ref CHECK-IMPORTS-HONEST :do "the launcher names the running native CLI by the digest of its build inputs (cli-<sha256>), so that name keys the stamps; any other name keeps them off")
fn ! stampedCache! -> Cache
  (let [(id (optionOr (listLast (stringSplit (optionOr (envGet "ASL_NATIVE_CLI_DIR") "") "/")) ""))
        (configured (optionOr (envGet "ASL_CHECK_CACHE") ""))
        (dir (if (stringEmpty? configured) (str (optionOr (envGet "HOME") ".") "/.asl/cache/check") configured))]
    (if (and (stringStartsWith? id "cli-") (= (stringLength id) 68)) (stampCacheAt dir id) (emptyCache)))

fn stampText key: String -> String
  (str "aslBodyStamp 1\n" key "\n")

fn stampLabel base: String p: String -> String
  (if (stringStartsWith? p (str base "/")) (optionOr (stringSlice p (+ (stringLength base) 1) (stringLength p)) p) p)

fn ! stampKey! checkerId: String paths: (List String) -> (Option String)
  (stampKeyIn! (resultOr (realPath ".") ".") checkerId paths)

; (:m :ref LEONSERVE-COLD-START :do "a dependency inside the base (the workspace the run starts in) is named in the stamp key by its path from the base, with its content digest: a worktree at another path with the same sources reuses the clean-closure stamps instead of checking the whole closure again (leonServe: about 400 s in a fresh worktree); a file outside the base keeps its absolute path")
fn ! stampKeyIn! base: String checkerId: String paths: (List String) -> (Option String)
  (let [(lines (map (fn [(p String)] -> String (match (fileReadBytes p) ((ok b) (str (stampLabel base p) "=" (bytesSha256 b))) ((err _) ""))) (listSort paths)))]
    (if (listAny? (fn [(l String)] -> Bool (stringEmpty? l)) lines)
      (none)
      (some (bytesSha256 (stringToBytes (str (stampText checkerId) (stringJoin lines "\n")))))))

fn ! stampHit! dir: String key: String -> Bool
  (= (resultOr (fileReadString (str dir "/" key ".verdict")) "") (stampText key))

fn ! stampWrite! dir: String key: String -> Bool
  (let [(final (str dir "/" key ".verdict"))
        (tmp (str final ".tmp." (stringFromInt64 (procSelf))))]
    (and (ok? (dirCreate dir)) (and (ok? (fileWrite tmp (stampText key))) (ok? (pathRename tmp final)))))

fn countsText v: Verdict -> String
  (str "(:checked " (stringFromInt64 v.checked) " :summarised " (stringFromInt64 v.summarised) ")")

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

fn realDeps cl: r/ModuleClosure -> (Map String r/ModuleSummary)
  (fold (fn [(acc (Map String r/ModuleSummary)) (p String)] -> (Map String r/ModuleSummary) (match (mapGet cl.deps p) ((some m) (mapSet acc p m)) ((none) acc))) (mapEmpty) cl.paths)

fn ! bodyDiags! dep: String roots: (List String) known: (Map String r/ModuleSummary) ix: r/ModIndex -> (Pair (List ty/Diagnostic) r/ModIndex)
  (match (fileReadString dep)
    ((err e) (pair (list (ty/Diagnostic :code "ERR_IO" :message e :msg e :line 0 :col 0 :path dep)) ix))
    ((ok src)
      (match (a/parseForTypeCheck src)
        ((err pe) (pair (parseErrDiag pe dep) ix))
        ((ok forms)
          (let [(summary (r/collectSummary forms dep))
                (cl (r/loadModuleDepsFrom! (cons (r/parentDirOf dep) roots) (r/mapValuesList summary.imports) known ix))]
            (match (classify cl)
              ((err _) (pair (closureDiags dep cl) cl.index))
              ((ok deps) (pair (chk/checkModuleSource forms deps dep src) cl.index))))))))

; (:m :ref CHECK-IMPORTS-HONEST :do "an importer is ok only when every module of its closure checks: a body this process has not checked is checked now, one it has is summarised and its diagnostics carried over")
fn ! bodyStep! paths: (List String) roots: (List String) known: (Map String r/ModuleSummary) t: Tally -> Tally
  (match (listHead paths)
    ((none) t)
    ((some p)
      (let [(rest (optionOr (listTail paths) (list)))]
        (cond
          ((not (stringEndsWith? p ".asl")) (bodyStep! rest roots known t))
          (else
            (match (mapGet t.cache.bodies p)
              ((some ds) (bodyStep! rest roots known (Tally :diags (listAppend t.diags ds) :checked t.checked :summarised (+ t.summarised 1) :cache t.cache)))
              ((none)
                (let [(r (bodyDiags! p roots known t.cache.index))
                      (ds (pairFirst r))]
                  (bodyStep! rest roots known (Tally :diags (listAppend t.diags ds) :checked (+ t.checked 1) :summarised t.summarised :cache (Cache :index (pairSecond r) :bodies (mapSet t.cache.bodies p ds) :stampDir t.cache.stampDir :checkerId t.cache.checkerId)))))))))))

; (:m :ref CHECK-IMPORTS-HONEST :do "a closure stamped clean under this checker and these dependency digests is summarised without checking its bodies; a clean check writes the stamp, also when this run had every body already, a dirty one never does")
fn ! closureVerdict! path: String src: String forms: (List a/TopForm) roots: (List String) cl: r/ModuleClosure deps: (Map String r/ModuleSummary) cache: Cache -> (Pair (Result Verdict String) Cache)
  (let [(self (resultOr (realPath path) path))
        (own (chk/checkModuleSource forms deps path src))
        (depPaths (filter (fn [(p String)] -> Bool (and (!= p self) (stringEndsWith? p ".asl"))) cl.paths))
        (fresh (filter (fn [(p String)] -> Bool (not (mapHas? cache.bodies p))) depPaths))
        (key (if (or (listEmpty? depPaths) (stringEmpty? cache.checkerId)) (none) (stampKey! cache.checkerId depPaths)))
        (start (Cache :index cl.index :bodies (mapSet cache.bodies self own) :stampDir cache.stampDir :checkerId cache.checkerId))]
    (if (and (not (listEmpty? fresh)) (match key ((some k) (stampHit! cache.stampDir k)) ((none) false)))
      (pair (ok (Verdict :diags own :checked 1 :summarised (listLength depPaths))) start)
      (let [(t (bodyStep! depPaths roots (realDeps cl) (Tally :diags own :checked 1 :summarised 0 :cache start)))
            (clean (= (listLength t.diags) (listLength own)))
            (stamped (match key ((some k) (and clean (stampWrite! cache.stampDir k))) ((none) false)))]
        (pair (ok (Verdict :diags t.diags :checked t.checked :summarised t.summarised)) t.cache))))

fn ! checkFileCached! path: String roots: (List String) cache: Cache -> (Pair (Result Verdict String) Cache)
  (match (fileReadString path)
    ((err ioErr) (pair (err ioErr) cache))
    ((ok src)
      (match (a/parseForTypeCheck src)
        ((err pe) (pair (ok (Verdict :diags (parseErrDiag pe path) :checked 1 :summarised 0)) cache))
        ((ok forms)
          (let [(summary (r/collectSummary forms path))
                (importPaths (r/mapValuesList summary.imports))
                (allRoots (cons (r/parentDirOf path) roots))
                (cl (r/loadModuleDepsFrom! allRoots importPaths (mapEmpty) cache.index))
                (nextCache (with cache :index cl.index))]
            (match (classify cl)
              ((err _) (pair (ok (Verdict :diags (closureDiags path cl) :checked 1 :summarised 0)) nextCache))
              ((ok deps) (closureVerdict! path src forms allRoots cl deps cache))))))))
