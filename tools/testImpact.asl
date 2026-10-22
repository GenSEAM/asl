(module asl-tools/testImpact
  :x [main ProcessOutput runProc moduleCacheKey cacheEntryMatches? selectFiles reasonsForFiles readModuleSource processExitCode saveCacheAt checkedStdout changedFromGit changedFromOutputs changedFromArgs loadCachedModulesAt impactReport headerOf headerImports packageOf packageSuites selectFilesIn listUnique]
  :i [])

(schema ModuleInfo
  (:f path String)
  (:f moduleName String)
  (:f imports (List String))
  (:f headerHash String)
  (:f source String))

(schema ProcessOutput
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn moduleHeaderEnd source: String index: Int64 depth: Int64 inString: Bool escaped: Bool -> Int64
  (if (>= index (stringLength source)) index
    (let [(ch (optionOr (stringSlice source index (+ index 1)) ""))]
      (if inString
        (if escaped (moduleHeaderEnd source (+ index 1) depth true false)
          (if (= ch "\\") (moduleHeaderEnd source (+ index 1) depth true true)
            (moduleHeaderEnd source (+ index 1) depth (!= ch "\"") false)))
        (if (= ch "\"") (moduleHeaderEnd source (+ index 1) depth true false)
          (if (= ch "(") (moduleHeaderEnd source (+ index 1) (+ depth 1) false false)
            (if (= ch ")")
              (if (= depth 1) (+ index 1) (moduleHeaderEnd source (+ index 1) (- depth 1) false false))
              (moduleHeaderEnd source (+ index 1) depth false false)))))))

fn headerOf source: String -> String
  (optionOr (stringSlice source 0 (moduleHeaderEnd source 0 0 false false)) source)

fn moduleNameOf header: String -> String
  (let [(line (optionOr (listHead (filter (fn [(line String)] -> Bool
                                  (and (not (stringEmpty? (stringTrim line))) (not (stringStartsWith? (stringTrim line) ";")))) (stringLines header))) ""))
        (words (stringSplit (stringTrim line) " "))]
    (if (and (>= (listLength words) 2) (= (optionOr (listGet words 0) "") "(module"))
      (optionOr (listGet words 1) "") ""))

fn findImportField header: String index: Int64 depth: Int64 inString: Bool escaped: Bool -> Int64
  (if (>= index (stringLength header)) -1
    (let [(ch (optionOr (stringSlice header index (+ index 1)) ""))]
      (if inString
        (if escaped (findImportField header (+ index 1) depth true false)
          (if (= ch "\\") (findImportField header (+ index 1) depth true true)
            (findImportField header (+ index 1) depth (!= ch "\"") false)))
        (if (= ch "\"") (findImportField header (+ index 1) depth true false)
          (if (= ch "(") (findImportField header (+ index 1) (+ depth 1) false false)
            (if (= ch ")") (findImportField header (+ index 1) (- depth 1) false false)
              (if (and (= depth 1) (= (optionOr (stringSlice header index (+ index 4)) "") ":i [")) index
                (findImportField header (+ index 1) depth false false))))))))

fn headerImports header: String -> (List String)
  (let [(end (findImportField header 0 0 false false))]
    (if (< end 0) (list)
      (let [(rest (optionOr (stringSlice header (+ end 4) (stringLength header)) ""))
            (listText (optionOr (listHead (stringSplit rest "]")) ""))
            (items (optionOr (listTail (stringSplit listText "(")) (list)))]
        (filter (fn [(name String)] -> Bool (not (stringEmpty? name)))
          (map (fn [(item String)] -> String
                 (let [(flat (stringTrim (stringReplace (stringReplace item "\n" " ") "\t" " ")))
                       (words (stringSplit flat " "))]
                   (stringReplace (optionOr (listHead words) "") ")" ""))) items)))))

fn moduleCacheKey source: String -> String
  (bytesSha256 (stringToBytes (headerOf source)))

fn cacheEntryMatches? entry: String path: String source: String -> Bool
  (let [(fields (stringSplit entry "\t"))]
    (and (>= (listLength fields) 4)
      (and (= (optionOr (listGet fields 0) "") path)
        (= (optionOr (listGet fields 1) "") (moduleCacheKey source)))))

fn ! runProc argv: (List String) -> ProcessOutput
  (match (procSpawnv argv (none) (none))
    ((err e) (ProcessOutput :exitCode 127 :stdout "" :stderr e))
    ((ok process)
      (let [(_ (fdClose process.stdin))
            (_ (fdNonBlocking process.stdout true))
            (_ (fdNonBlocking process.stderr true))]
        (collectOutput process.stdout process.stderr "" "" true true process.pid))))

fn ! collectOutput outFd: Int64 errFd: Int64 outText: String errText: String outOpen: Bool errOpen: Bool pid: Int64 -> ProcessOutput
  (if (and (not outOpen) (not errOpen))
    (match (procWaitPid pid false)
      ((ok status) (ProcessOutput :exitCode (processExitCode status) :stdout outText :stderr errText))
      ((err e) (ProcessOutput :exitCode 1 :stdout outText :stderr e)))
    (let [(outRead (if outOpen (fdRead outFd 65536) (err "closed")))
          (outMore (match outRead
            ((ok text) (if (stringEmpty? text) false true))
            ((err _) false)))
          (outTextNext (match outRead ((ok text) (str outText text)) ((err _) outText)))
          (outOpenNext (if outOpen (match outRead
            ((ok text) (if (stringEmpty? text) (let [(_ (fdClose outFd))] false) true))
            ((err _) true)) false))
          (errRead (if errOpen (fdRead errFd 65536) (err "closed")))
          (errMore (match errRead
            ((ok text) (if (stringEmpty? text) false true))
            ((err _) false)))
          (errTextNext (match errRead ((ok text) (str errText text)) ((err _) errText)))
          (errOpenNext (if errOpen (match errRead
            ((ok text) (if (stringEmpty? text) (let [(_ (fdClose errFd))] false) true))
            ((err _) true)) false))]
      (if (and (not outMore) (not errMore) (or outOpenNext errOpenNext))
        (fdPoll (if (and outOpenNext errOpenNext) (list (pair outFd 1) (pair errFd 1))
                  (if outOpenNext (list (pair outFd 1)) (list (pair errFd 1)))) 50)
        ())
      (collectOutput outFd errFd outTextNext errTextNext outOpenNext errOpenNext pid)))

fn processExitCode status: (Option Int64) -> Int64
  (match status ((none) 1) ((some code) code))

fn ! readModuleSource path: String -> (Result String String)
  (fileReadString path)

fn ! saveCacheAt dir: String cachePath: String contents: String -> (Result Unit String)
  (match (dirCreate dir)
    ((err e) (err (str "testImpact: cache directory " dir ": " e)))
    ((ok _) (fileWrite cachePath contents)))

fn checkedStdout operation: String result: ProcessOutput -> (Result String String)
  (if (= result.exitCode 0) (ok result.stdout)
    (err (str "testImpact: " operation " failed (exit " (stringFromInt64 result.exitCode) "): " result.stderr)))

fn ! cachedModule path: String source: String sourceRead: Bool cache: (Map String String) -> ModuleInfo
  (let [(header (headerOf source))
        (digest (bytesSha256 (stringToBytes header)))
        (row (mapGet cache path))
        (fields (match row ((none) (list)) ((some line) (stringSplit line "\t"))))
        (matches (and (>= (listLength fields) 4)
                      (or (not sourceRead) (cacheEntryMatches? (optionOr row "") path source))))
        (name (if matches (optionOr (listGet fields 2) "") (moduleNameOf header)))
        (importsText (if matches (optionOr (listGet fields 3) "") (stringJoin (headerImports header) "\u001f")))
        (imports (if (stringEmpty? importsText) (list) (stringSplit importsText "\u001f")))]
    (ModuleInfo :path path :moduleName name :imports imports
                :headerHash (if matches (optionOr (listGet fields 1) "") digest) :source source))

fn ! loadModules paths: (List String) idx: Int64 acc: (List ModuleInfo) cache: (Map String String) changed: (List String) fixturesChanged: Bool -> (Result (List ModuleInfo) String)
  (if (>= idx (listLength paths)) (ok (listReverse acc))
    (let [(path (optionOr (listGet paths idx) ""))
          (cached (some? (mapGet cache path)))
          (mustRead (or (not cached) (listContains? changed path)))
          (readBody (and fixturesChanged (isTest path)))
          (sourceRead (or mustRead readBody))
          (sourceResult (if sourceRead (readModuleSource path) (ok "")))]
      (match sourceResult
        ((err e) (err (str "testImpact: reading module " path ": " e)))
        ((ok source)
          (let [(node (cachedModule path source sourceRead cache))]
            (loadModules paths (+ idx 1) (if (stringEmpty? node.moduleName) acc (cons node acc)) cache changed fixturesChanged))))))

; (:m :ref TRAIN :do "selection and reasons were list scans: resolveModule filtered the module list per lookup, expandAffected re-scanned every module per fixpoint round, and reaches? re-walked the graph per path without a visited set (exponential on shared imports; the whole-repo run did not finish in 900 s); the same answers now come from name and reverse indexes and a breadth-first walk with a visited map")
fn ! nameIndex modules: (List ModuleInfo) -> (Map String ModuleInfo)
  (fold (fn [(m (Map String ModuleInfo)) (node ModuleInfo)] -> (Map String ModuleInfo)
          (if (mapHas? m node.moduleName) m (mapSet m node.moduleName node)))
        (mapEmpty) modules)

fn ! resolveModule modules: (List ModuleInfo) name: String -> (Option ModuleInfo)
  (mapGet (nameIndex modules) name)

fn ! moduleAtPath modules: (List ModuleInfo) path: String -> (Option ModuleInfo)
  (listHead (filter (fn [(node ModuleInfo)] -> Bool (= node.path path)) modules))

fn ! reachAvoiding names: (Map String ModuleInfo) frontier: (List String) seen: (Map String Bool) -> (Map String Bool)
  (match (listHead frontier)
    ((none) seen)
    ((some current) (let [(rest (optionOr (listTail frontier) (list)))]
      (if (mapHas? seen current) (reachAvoiding names rest seen)
        (let [(next (match (mapGet names current) ((none) (list)) ((some node) node.imports)))]
          (reachAvoiding names (listAppend next rest) (mapSet seen current true)))))))

fn ! reachesIn? names: (Map String ModuleInfo) current: String target: String avoid: (List String) -> Bool
  (if (= current target) true
    (if (listContains? avoid current) false
      (let [(blocked (fold (fn [(m (Map String Bool)) (n String)] -> (Map String Bool) (if (= n target) m (mapSet m n true))) (mapEmpty) avoid))
            (start (match (mapGet names current) ((none) (list)) ((some node) node.imports)))
            (reached (reachAvoiding names start (mapSet blocked current true)))]
        (mapHas? reached target))))

fn ! reaches? modules: (List ModuleInfo) current: String target: String seen: (List String) -> Bool
  (reachesIn? (nameIndex modules) current target seen)

fn ! isTest path: String -> Bool
  (stringEndsWith? path "Test.asl")

fn ! testMentions? source: String changed: String -> Bool
  (and (not (stringEndsWith? changed ".asl")) (stringContains? source changed))

fn ! testAffected? test: ModuleInfo changed: (List String) affected: (Map String Bool) -> Bool
  (or (listContains? changed test.path)
    (or (some? (listHead (filter (fn [(path String)] -> Bool (testMentions? test.source path)) changed)))
      (mapHas? affected test.moduleName)))

fn ! importersIndex modules: (List ModuleInfo) -> (Map String (List String))
  (fold (fn [(m (Map String (List String))) (node ModuleInfo)] -> (Map String (List String))
          (fold (fn [(m2 (Map String (List String))) (dependency String)] -> (Map String (List String))
                  (mapSet m2 dependency (cons node.moduleName (optionOr (mapGet m2 dependency) (list)))))
                m node.imports))
        (mapEmpty) modules)

fn ! expandFrom importers: (Map String (List String)) frontier: (List String) seen: (Map String Bool) -> (Map String Bool)
  (match (listHead frontier)
    ((none) seen)
    ((some name) (let [(rest (optionOr (listTail frontier) (list)))]
      (if (mapHas? seen name) (expandFrom importers rest seen)
        (expandFrom importers (listAppend (optionOr (mapGet importers name) (list)) rest) (mapSet seen name true))))))

fn ! moduleNameFromPath path: String -> String
  (if (and (>= (stringLength path) 4) (stringEndsWith? path ".asl"))
    (optionOr (stringSlice path 0 (- (stringLength path) 4)) "") "")

fn ! selectedFor modules: (List ModuleInfo) changed: (List String) -> (List ModuleInfo)
  (let [(changedSet (fold (fn [(m (Map String Bool)) (p String)] -> (Map String Bool) (mapSet m p true)) (mapEmpty) changed))
        (paths (fold (fn [(m (Map String Bool)) (node ModuleInfo)] -> (Map String Bool) (mapSet m node.path true)) (mapEmpty) modules))
        (targets (map (fn [(node ModuleInfo)] -> String node.moduleName)
                      (filter (fn [(node ModuleInfo)] -> Bool (mapHas? changedSet node.path)) modules)))
        (deletedTargets (map moduleNameFromPath
          (filter (fn [(path String)] -> Bool
            (and (not (mapHas? paths path)) (stringEndsWith? path ".asl"))) changed)))
        (affected (expandFrom (importersIndex modules) (listAppend targets deletedTargets) (mapEmpty)))]
    (filter (fn [(node ModuleInfo)] -> Bool
              (and (isTest node.path) (testAffected? node changed affected))) modules))

fn ! chainIn names: (Map String ModuleInfo) current: String target: String seen: (List String) -> (List String)
  (if (= current target) (list current)
    (if (listContains? seen current) (list)
      (match (mapGet names current)
        ((none) (list))
        ((some node)
          (let [(path (listAppend seen (list current)))]
            (match (listHead (filter (fn [(dependency String)] -> Bool (reachesIn? names dependency target path)) node.imports))
              ((none) (list))
              ((some dependency) (listAppend (list current) (chainIn names dependency target path)))))))))

fn ! chainTo modules: (List ModuleInfo) current: String target: String seen: (List String) -> (List String)
  (chainIn (nameIndex modules) current target seen)

fn ! reasonChain modules: (List ModuleInfo) test: ModuleInfo changed: (List String) -> (List String)
  (let [(names (nameIndex modules))
        (sameTest (listHead (filter (fn [(path String)] -> Bool (= path test.path)) changed)))
        (fixture (listHead (filter (fn [(path String)] -> Bool (testMentions? test.source path)) changed)))
        (target (listHead (filter (fn [(path String)] -> Bool
          (match (moduleAtPath modules path)
            ((none) false)
            ((some node) (reachesIn? names test.moduleName node.moduleName (list))))) changed)))]
    (match sameTest
      ((some _) (list test.moduleName))
      ((none) (match fixture
        ((some path) (list (str "fixture:" path)))
        ((none) (match target
          ((none) (list))
          ((some path) (match (moduleAtPath modules path)
            ((none) (list))
            ((some node) (chainIn names test.moduleName node.moduleName (list)))))))))))

fn ! reasonsText modules: (List ModuleInfo) picked: (List ModuleInfo) changed: (List String) -> String
  (str "(" (stringJoin (map (fn [(test ModuleInfo)] -> String
        (str "(\"" test.path "\" ("
          (stringJoin (map (fn [(name String)] -> String (str "\"" name "\"")) (reasonChain modules test changed)) " ") "))")) picked) " ") ")")

fn ! reasonsForFiles paths: (List String) changed: (List String) -> (Result String String)
  (resultMap (loadModules paths 0 (list) (mapEmpty) changed true)
    (fn [(modules (List ModuleInfo))] -> String
      (let [(picked (selectedFor modules changed))]
        (reasonsText modules picked changed))))

fn ! selectFiles paths: (List String) changed: (List String) -> (Result (List String) String)
  (resultMap (loadModules paths 0 (list) (mapEmpty) changed true)
    (fn [(modules (List ModuleInfo))] -> (List String)
      (let [(picked (selectedFor modules changed))]
        (map (fn [(node ModuleInfo)] -> String node.path) picked))))

fn ! cacheText modules: (List ModuleInfo) -> String
  (str (stringJoin (map (fn [(node ModuleInfo)] -> String
          (str node.path "\t" node.headerHash "\t" node.moduleName "\t" (stringJoin node.imports "\u001f"))) modules) "\n") "\n")

fn ! cacheMap rows: (List String) -> (Map String String)
  (fold (fn [(acc (Map String String)) (line String)] -> (Map String String)
          (let [(fields (stringSplit line "\t"))]
            (if (>= (listLength fields) 4) (mapSet acc (optionOr (listGet fields 0) "") line) acc)))
        (mapEmpty) rows)

fn ! loadCachedModulesAt paths: (List String) changed: (List String) cacheDir: String cachePath: String -> (Result (List ModuleInfo) String)
  (let [
        (cache (match (fileReadString cachePath) ((ok text) (stringLines text)) ((err _) (list))))
        (fixturesChanged (some? (listHead (filter (fn [(path String)] -> Bool (not (stringEndsWith? path ".asl"))) changed))))]
    (match (loadModules paths 0 (list) (cacheMap cache) changed fixturesChanged)
      ((err e) (err e))
      ((ok modules) (resultMap (saveCacheAt cacheDir cachePath (cacheText modules)) (fn [_] -> (List ModuleInfo) modules)))))

fn ! loadCachedModules paths: (List String) changed: (List String) -> (Result (List ModuleInfo) String)
  (loadCachedModulesAt paths changed ".asl/cache/testImpact" ".asl/cache/testImpact/graph.tsv")

fn ! filesFromGit -> (Result (List String) String)
  (let [(result (runProc (list "git" "ls-files" "--cached" "--others" "--exclude-standard" "*.asl")))]
    (resultMap (checkedStdout "git ls-files --cached --others --exclude-standard '*.asl'" result)
      (fn [(output String)] -> (List String)
        (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines output)))))

fn ! changedFromGit base: String -> (Result (List String) String)
  (let [(diff (runProc (list "git" "diff" "--name-only" base "--")))
        (untracked (runProc (list "git" "ls-files" "--others" "--exclude-standard")))
        (staged (runProc (list "git" "diff" "--cached" "--name-only" base "--")))]
    (changedFromOutputs diff untracked staged))

fn ! changedFromOutputs diff: ProcessOutput untracked: ProcessOutput staged: ProcessOutput -> (Result (List String) String)
    (match (checkedStdout "git diff --name-only" diff)
      ((err e) (err e))
      ((ok diffOutput)
        (match (checkedStdout "git ls-files --others --exclude-standard" untracked)
          ((err e) (err e))
          ((ok untrackedOutput)
            (resultMap (checkedStdout "git diff --cached --name-only" staged)
              (fn [(stagedOutput String)] -> (List String)
                (listUnique (listAppend (stringLines diffOutput)
                  (listAppend (stringLines stagedOutput) (stringLines untrackedOutput))))))))))

fn ! changedArgsAt args: (List String) index: Int64 acc: (List String) seen: Bool -> (Option (List String))
  (if (>= index (listLength args))
    (if seen (some (listUnique acc)) (none))
    (let [(arg (optionOr (listGet args index) ""))]
      (if (stringStartsWith? arg "--changed=")
        (changedArgsAt args (+ index 1)
          (listAppend acc (list (optionOr (stringSlice arg 10 (stringLength arg)) ""))) true)
        (if (= arg "--changed")
          (match (listGet args (+ index 1))
            ((none) (some (listUnique acc)))
            ((some path) (changedArgsAt args (+ index 2) (listAppend acc (list path)) true)))
          (changedArgsAt args (+ index 1) acc seen)))))

fn ! changedFromArgs args: (List String) -> (Option (List String))
  (changedArgsAt args 0 (list) false)


fn ! listUnique values: (List String) -> (List String)
  (fold (fn [(acc (List String)) (value String)] -> (List String)
          (if (or (stringEmpty? value) (listContains? acc value)) acc (listAppend acc (list value))))
        (list) values)

fn impactReport base: String changed: (List String) selected: (List String) skipped: Int64 reasons: String warm: Bool -> String
  (str "(:impact :base \"" base "\" :changed ("
       (stringJoin (map (fn [(p String)] -> String (str "\"" p "\"")) changed) " ")
       ") :selected (" (stringJoin (map (fn [(p String)] -> String (str "\"" p "\"")) selected) " ")
       ") :skipped " skipped " :reasons " reasons
       " :cache :" (if warm "warm" "cold") ")")

fn ! finishSelection base: String changed: (List String) allAsl: (List String) modules: (List ModuleInfo) -> (Result Int64 String)
  (let [(warm (fileExists? ".asl/cache/testImpact/graph.tsv"))
        (picked (selectedFor modules changed))
        (paths (map (fn [(node ModuleInfo)] -> String node.path) picked))
        (report (impactReport base changed paths
                  (- (listLength (filter isTest allAsl)) (listLength paths))
                  (reasonsText modules picked changed) warm))]
    (do (println report)
        (ok 0)))

fn ! mainAtBase args: (List String) base: String -> (Result Int64 String)
  (match (match (changedFromArgs args)
        ((none) (changedFromGit base))
        ((some changed) (ok changed)))
    ((err e) (do (eprintln e) (ok 2)))
    ((ok changed)
      (match (filesFromGit)
        ((err e) (do (eprintln e) (ok 2)))
        ((ok allAsl)
          (match (loadCachedModules allAsl changed)
            ((err e) (do (eprintln e) (ok 2)))
            ((ok modules) (finishSelection base changed allAsl modules)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(baseArg (match (listHead (filter (fn [(arg String)] -> Bool (stringStartsWith? arg "--base=")) args))
                 ((none) "")
                 ((some arg) (optionOr (stringSlice arg 7 (stringLength arg)) ""))))
        (mergeBase (if (stringEmpty? baseArg)
                     (runProc (list "git" "merge-base" "main" "HEAD"))
                     (ProcessOutput :exitCode 0 :stdout baseArg :stderr "")))
        (base (stringTrim mergeBase.stdout))]
    (if (listContains? args "--run")
      (do (eprintln "testImpact: --run is deferred to a later unit") (ok 2))
      (if (!= mergeBase.exitCode 0)
        (do (eprintln (str "testImpact: git merge-base main HEAD failed: " mergeBase.stderr)) (ok 2))
        (mainAtBase args base))))

fn packageOf path: String -> (Option String)
  (let [(parts (stringSplit path "/"))]
    (if (and (>= (listLength parts) 3) (and (= (listGet parts 0) (some "asl")) (= (listGet parts 1) (some "packages"))))
      (listGet parts 2)
      (none)))

fn ! packageSuites paths: (List String) changed: (List String) -> (List String)
  (let [(pkgs (listUnique (fold (fn [(acc (List String)) (p String)] -> (List String)
                                  (match (packageOf p) ((none) acc) ((some name) (listAppend acc (list name)))))
                                (list) changed)))]
    (filter (fn [(p String)] -> Bool
              (and (isTest p) (match (packageOf p) ((none) false) ((some name) (listContains? pkgs name)))))
            paths))

fn ! selectFilesIn root: String paths: (List String) changed: (List String) -> (Result (List String) String)
  (let [(prefix (str root "/"))
        (rooted (fn [(p String)] -> String (str prefix p)))
        (unrooted (fn [(p String)] -> String (if (stringStartsWith? p prefix) (optionOr (stringSlice p (stringLength prefix) (stringLength p)) p) p)))]
    (resultMap (selectFiles (map rooted paths) (listAppend (map rooted changed) (filter (fn [(p String)] -> Bool (not (stringEndsWith? p ".asl"))) changed)))
      (fn [(picked (List String))] -> (List String) (map unrooted picked))))
