(module asl-checker/checkCached
  :x [Cache emptyCache stampCacheAt stampedCache! stampKeyIn! Verdict countsText checkFileCached! checkFileCachedIn! checkSourceCachedIn!]
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

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "what a body verdict reads besides its source and resolved imports: the :pure flag of the nearest manifest.asn (rule 12, resolve packagePure!), so it is in both stamp keys; builtin signatures and the prelude are compiled into the checker and covered by its id; .asl.config.asn, manifest :dependencies and ~/.asl/pkgs only steer resolution, covered by the resolved paths in the key; hints change diagnostic text only and only clean bodies are stamped")
fn ! pureMark path: String -> String
  (if (r/packagePure! path) " pure" "")

fn ! stampKey! checkerId: String paths: (List String) -> (Option String)
  (stampKeyIn! (resultOr (realPath ".") ".") checkerId paths)

; (:m :ref LEONSERVE-COLD-START :do "a dependency inside the base (the workspace the run starts in) is named in the stamp key by its path from the base, with its content digest: a worktree at another path with the same sources reuses the clean-closure stamps instead of checking the whole closure again (leonServe: about 400 s in a fresh worktree); a file outside the base keeps its absolute path")
fn ! stampKeyIn! base: String checkerId: String paths: (List String) -> (Option String)
  (let [(lines (map (fn [(p String)] -> String (match (fileReadBytes p) ((ok b) (str (stampLabel base p) "=" (bytesSha256 b) (pureMark p))) ((err _) ""))) (listSort paths)))]
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

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "a body checked clean is also stamped on its own, in stampDir/modules apart from the closure stamps: its key is this checker, its path from the base with its content digest, and the interface keys of the modules it imports; a closure whose stamp misses after one edit checks only the edited module and the importers whose view of it changed, and a second root with that closure checks none of them")
; (:m :ref CHECKER-IFACE-KEY :do "a body verdict reads its imports only through their ModuleSummary (resolve collectSummary, effects refined over the closure), so an import enters the key by its interface key, not its bytes: a body-only edit of a widely imported module rechecks that module alone (cardTest: 273 bodies on one edit before)")
(schema KeyMemo (:f keys (Map String String)) (:f ifaces (Map String String)) (:f mods (Map String r/ModuleSummary)) (:f index r/ModIndex))

fn modStampDir dir: String -> String
  (str dir "/modules")

fn setKeys m: KeyMemo p: String k: String i: String -> KeyMemo
  (KeyMemo :keys (mapSet m.keys p k) :ifaces (mapSet m.ifaces p i) :mods m.mods :index m.index)

fn anyEmpty? xs: (List String) -> Bool
  (listAny? (fn [(x String)] -> Bool (stringEmpty? x)) xs)

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "a module of the closure load already carries its imports resolved to real paths (resolve loadModule!, alias to path), so its direct dependencies are read from that summary without parsing or resolving again; an import left unresolved there is not a loaded path and yields no key; a module outside the load is parsed and resolved here")
fn ! parsedDeps! dep: String roots: (List String) known: (Map String r/ModuleSummary) ix: r/ModIndex -> (Pair (Option (List String)) r/ModIndex)
  (match (fileReadString dep)
    ((err _) (pair (none) ix))
    ((ok src)
      (match (a/parseForTypeCheck src)
        ((err _) (pair (none) ix))
        ((ok forms)
          (let [(summary (r/collectSummary forms dep))
                (imports (filter (fn [(i String)] -> Bool (!= i "sys")) (r/mapValuesList summary.imports)))
                (cl (r/loadModuleDepsFrom! (cons (r/parentDirOf dep) roots) imports known ix))
                (found (map (fn [(i String)] -> String (match (mapGet cl.deps i) ((some s) s.path) ((none) ""))) imports))]
            (match (classify cl)
              ((err _) (pair (none) cl.index))
              ((ok _) (pair (if (anyEmpty? found) (none) (some found)) cl.index))))))))

fn ! directDeps! dep: String roots: (List String) known: (Map String r/ModuleSummary) ix: r/ModIndex -> (Pair (Option (List String)) r/ModIndex)
  (match (mapGet known dep)
    ((none) (parsedDeps! dep roots known ix))
    ((some s)
      (let [(paths (filter (fn [(p String)] -> Bool (!= p "sys")) (r/mapValuesList s.imports)))]
        (pair (if (listAll? (fn [(p String)] -> Bool (mapHas? known p)) paths) (some paths) (none)) ix))))

; (:m :ref CHECKER-IFACE-KEY :do "effects are refined once over the whole closure, as checkModule does per body (resolve refineEffects): the effect flag and witness an importer reads are the refined ones, and a function's refined effect follows only its callees, so the closure of any root gives the same flags as the module's own closure")
fn refinedMods known: (Map String r/ModuleSummary) -> (Map String r/ModuleSummary)
  (let [(ix (pairSecond (r/refineEffects (r/emptyModuleSummary) (r/depScanOf known))))] ix.deps)

fn flag b: Bool -> String
  (if b "1" "0")

fn pairsText ps: (List (Pair String String)) -> String
  (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) ": " (pairSecond p))) ps) " ")

fn funIfaceLine f: r/FunSummary -> String
  (str "fn " f.name " effect=" (flag f.effect) " witness=" f.witness " doc=" (flag f.hasDoc) " tvars=[" (stringJoin f.typevars " ") "] [" (pairsText f.params) "] -> " f.ret)

fn schemaIfaceLine s: r/SchemaSummary -> String
  (str "schema " s.name " tvars=[" (stringJoin s.typevars " ") "] " (stringJoin (map (fn [(f r/FieldSummary)] -> String (str "(:f " f.name " " f.type (if f.hasDefault " :default" "") ")")) s.fields) " "))

fn enumIfaceLine e: r/EnumSummary -> String
  (str "enum " e.name " tvars=[" (stringJoin e.typevars " ") "] " (stringJoin (map (fn [(c r/CaseSummary)] -> String (str "(" c.name " " (pairsText c.params) ")")) e.cases) " "))

fn mapLines label: String m: (Map String String) -> (List String)
  (map (fn [(k String)] -> String (str label " " k "=" (optionOr (mapGet m k) ""))) (listSort (mapKeys m)))

; (:m :ref CHECKER-IFACE-KEY :do "what an importer's check reads of a dependency, from resolve and check: its name, header and doc marks, exports and exported types, its imports by alias (signature types resolve in its scope); every function a qualified name may reach (exported, or a Pascal name exported as a type) with params, typevars, the signature return text (an omitted one reads :inferredUnit, never the body), the refined effect and witness; every schema with typevars and fields with types and defaults and every enum with its cases, private ones too (a qualified constructor accepts a private schema, case lookups read caseOwner); caseOwner, exportedCases and exportedFields, the last including the curly keys of its bodies (collectAllFieldNames); bodies, private signatures and call lists stay out, call lists only through the refined effects")
fn ifaceText base: String s: r/ModuleSummary -> String
  (let [(funs (map funIfaceLine (filter (fn [(f r/FunSummary)] -> Bool (or (listContains? s.exports f.name) (listContains? s.exportedTypes f.name))) (mapValues s.funs))))
        (lines (listAppend (list (str "name " s.name) (str "header=" (flag s.hasHeader) " doc=" (flag s.hasDoc)) (str "exports [" (stringJoin s.exports " ") "]") (str "types [" (stringJoin s.exportedTypes " ") "]"))
                 (listAppend (listSort (map (fn [(al String)] -> String (str "import " al " " (stampLabel base (optionOr (mapGet s.imports al) "")))) (mapKeys s.imports)))
                   (listAppend (listSort funs)
                     (listAppend (listSort (map schemaIfaceLine (mapValues s.schemas)))
                       (listAppend (listSort (map enumIfaceLine (mapValues s.enums)))
                         (listAppend (mapLines "caseOwner" s.caseOwner)
                           (listAppend (mapLines "exportedCase" s.exportedCases)
                             (list (str "fields [" (stringJoin (listSort (mapKeys s.exportedFields)) " ") "]"))))))))))]
    (stringJoin lines "\n"))

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "an empty key marks a module in progress or without a key, so an import cycle or an unreadable or unresolved dependency yields no key and that body is checked as before")
; (:m :ref CHECKER-IFACE-KEY :do "two keys per module: the check key (its bytes and pure mark, and each import's interface key) stamps its body; the interface key (its interface text and each import's interface key) is what its importers chain on, so an interface change two imports away still re-keys them; a non-ASL file keys on its bytes for both; a module without a loaded summary gives its importers no key")
fn ! modKey! base: String id: String roots: (List String) known: (Map String r/ModuleSummary) path: String memo: KeyMemo -> KeyMemo
  (match (mapGet memo.keys path)
    ((some _) memo)
    ((none)
      (match (fileReadBytes path)
        ((err _) (setKeys memo path "" ""))
        ((ok b)
          (let [(own (str "aslModStamp 2\n" id "\n" (stampLabel base path) "=" (bytesSha256 b) (pureMark path)))]
            (if (not (stringEndsWith? path ".asl"))
              (let [(k (bytesSha256 (stringToBytes own)))] (setKeys memo path k k))
              (let [(dd (directDeps! path roots known memo.index))
                    (m1 (setKeys (KeyMemo :keys memo.keys :ifaces memo.ifaces :mods memo.mods :index (pairSecond dd)) path "" ""))]
                (match (pairFirst dd)
                  ((none) m1)
                  ((some ps)
                    (let [(m2 (fold (fn [(m KeyMemo) (p String)] -> KeyMemo (modKey! base id roots known p m)) m1 ps))
                          (lines (map (fn [(p String)] -> String (let [(i (optionOr (mapGet m2.ifaces p) ""))] (if (stringEmpty? i) "" (str (stampLabel base p) " " i)))) ps))
                          (deps (stringJoin (listSort lines) "\n"))
                          (k (if (anyEmpty? lines) "" (bytesSha256 (stringToBytes (str own "\n" deps)))))
                          (i (match (mapGet memo.mods path)
                               ((none) "")
                               ((some s) (if (anyEmpty? lines) "" (bytesSha256 (stringToBytes (str "aslIface 1\n" id "\n" (stampLabel base path) "\n" (ifaceText base s) "\n" deps)))))))]
                      (setKeys m2 path k i)))))))))))

fn ! modKeysOf! base: String id: String roots: (List String) known: (Map String r/ModuleSummary) paths: (List String) ix: r/ModIndex -> KeyMemo
  (fold (fn [(m KeyMemo) (p String)] -> KeyMemo (modKey! base id roots known p m)) (KeyMemo :keys (mapEmpty) :ifaces (mapEmpty) :mods (refinedMods known) :index ix) paths)

fn modKeyOf memo: KeyMemo p: String -> String
  (optionOr (mapGet memo.keys p) "")

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "a stamp is written only when the key taken again after the check equals the key taken before it, so a source or dependency edited while its body was checked is not stamped under the old key")
fn ! modStampsWrite! dir: String mods: KeyMemo post: KeyMemo hits: (List String) bodies: (Map String (List ty/Diagnostic)) paths: (List String) -> Int64
  (fold (fn [(n Int64) (p String)] -> Int64
          (let [(k (modKeyOf mods p))
                (same (= k (modKeyOf post p)))
                (clean (match (mapGet bodies p) ((some ds) (listEmpty? ds)) ((none) false)))]
            (if (and (not (stringEmpty? k)) (and clean (and same (and (not (listContains? hits p)) (stampWrite! dir k))))) (+ n 1) n)))
        0 paths)

; (:m :ref CHECK-IMPORTS-HONEST :do "a closure stamped clean under this checker and these dependency digests is summarised without checking its bodies; a clean check writes the stamp, also when this run had every body already, a dirty one never does")
fn ! closureVerdict! base: String path: String src: String forms: (List a/TopForm) roots: (List String) cl: r/ModuleClosure deps: (Map String r/ModuleSummary) cache: Cache -> (Pair (Result Verdict String) Cache)
  (let [(self (resultOr (realPath path) path))
        (own (chk/checkModuleSource forms deps path src))
        (depPaths (filter (fn [(p String)] -> Bool (and (!= p self) (stringEndsWith? p ".asl"))) cl.paths))
        (fresh (filter (fn [(p String)] -> Bool (not (mapHas? cache.bodies p))) depPaths))
        (key (if (or (listEmpty? depPaths) (stringEmpty? cache.checkerId)) (none) (stampKeyIn! base cache.checkerId depPaths)))
        (start (Cache :index cl.index :bodies (mapSet cache.bodies self own) :stampDir cache.stampDir :checkerId cache.checkerId))]
    (if (and (not (listEmpty? fresh)) (match key ((some k) (stampHit! cache.stampDir k)) ((none) false)))
      (pair (ok (Verdict :diags own :checked 1 :summarised (listLength depPaths))) start)
      (let [(known (realDeps cl))
            (mods (if (or (listEmpty? fresh) (stringEmpty? cache.checkerId)) (KeyMemo :keys (mapEmpty) :ifaces (mapEmpty) :mods (mapEmpty) :index cl.index) (modKeysOf! base cache.checkerId roots known fresh cl.index)))
            (mDir (modStampDir cache.stampDir))
            (hits (filter (fn [(p String)] -> Bool (let [(k (modKeyOf mods p))] (and (not (stringEmpty? k)) (stampHit! mDir k)))) fresh))
            (seeded (Cache :index mods.index :bodies (fold (fn [(acc (Map String (List ty/Diagnostic))) (p String)] -> (Map String (List ty/Diagnostic)) (mapSet acc p (list))) start.bodies hits) :stampDir cache.stampDir :checkerId cache.checkerId))
            (t (bodyStep! depPaths roots known (Tally :diags own :checked 1 :summarised 0 :cache seeded)))
            (written (filter (fn [(p String)] -> Bool (and (not (listContains? hits p)) (match (mapGet t.cache.bodies p) ((some ds) (listEmpty? ds)) ((none) false)))) fresh))
            (post (if (or (listEmpty? written) (stringEmpty? cache.checkerId)) (KeyMemo :keys (mapEmpty) :ifaces (mapEmpty) :mods (mapEmpty) :index t.cache.index) (modKeysOf! base cache.checkerId roots known written t.cache.index)))
            (modsWritten (modStampsWrite! mDir mods post hits t.cache.bodies written))
            (clean (= (listLength t.diags) (listLength own)))
            (stamped (match key ((some k) (and clean (stampWrite! cache.stampDir k))) ((none) false)))]
        (pair (ok (Verdict :diags t.diags :checked t.checked :summarised t.summarised)) t.cache))))

fn ! checkFileCached! path: String roots: (List String) cache: Cache -> (Pair (Result Verdict String) Cache)
  (checkFileCachedIn! (resultOr (realPath ".") ".") path roots cache)

; (:m :ref RELAY-FORMS-SLOW :do "base is the tree stampKeyIn! labels the closure's deps from; a check of a byte-identical copy (asl-forms' staged overlay) passes the copy's root, so its deps match the workspace stamp instead of being labelled by their absolute copy paths and re-checked")
fn ! checkSourceCachedIn! base: String path: String src: String roots: (List String) cache: Cache -> (Pair (Result Verdict String) Cache)
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
          ((ok deps) (closureVerdict! base path src forms allRoots cl deps cache))))))

fn ! checkFileCachedIn! base: String path: String roots: (List String) cache: Cache -> (Pair (Result Verdict String) Cache)
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
              ((ok deps) (closureVerdict! base path src forms allRoots cl deps cache))))))))
