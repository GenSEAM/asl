(module asl-cli/cliClosure
  :x [Reach closureOf! reachFrom testEntry testCuts testGates fnKey]
  :i [(asl-checker/resolve :a r) (asl-parser/ast :a a)])

; (:m :ref PERF-CLI-REBUILD :do "the files whose code a verb of the native CLI can run: a walk over the checker's per-function reference atoms (FunSummary.calls, params and return types) from root functions of the entry module; every reference atom counts, call heads and values alike (a function stored in a map or list, passed as an argument or called inside a lambda), so a qualified alias/name follows the import to its module and a bare name a function of the same module; ASL has no call by string name, so a string-keyed table still names its functions as atoms; a reached module also pulls in the modules its schema and enum types name; cut names are not followed, and a cut referenced from a reached function outside the gates makes the walk an error, so a new call into a cut handler can never shrink the set")
(schema Reach (:f files (Map String Bool)) (:f seen (Map String Bool)) (:f bad (List String)))

fn fnKey path: String name: String -> String
  (str path " :: " name)

fn testEntry -> String
  "asl/packages/asl-cli/src/native.asl"

; (:m :ref PERF-CLI-REBUILD :do "asl test FILE... reaches main, the native gate, entry!, localEntry!, dispatch! and test!; the handlers of the other verbs, the hosted path through cmd/dispatch! (taken only for --trace, --compare, bare --native or a non-root cwd without plain files) and the re-exec at the root (a new bin/asl that decides again) are cut, and only the dispatchers in testGates may name them")
fn testCuts -> (List String)
  (list "forms!" "intel!" "run!" "parse!" "eval!" "launch!" "pkg!" "check!" "runInline!" "stdinEntry!" "fileEntry!" "runPath!"
        "changedTest!" "sweepTest!" "reexecTestAtRoot!" "allWithPaths!" "cmd/dispatch!")

fn testGates -> (List String)
  (list "main" "entry!" "localEntry!" "dispatch!" "dispatchRaw!" "test!")

fn qualified? s: String -> Bool
  (and (not (stringStartsWith? s "/")) (stringContains? s "/"))

fn splitQual s: String -> (Pair String String)
  (match (stringIndexOf s "/")
    ((some i) (pair (optionOr (stringSlice s 0 i) "") (optionOr (stringSlice s (+ i 1) (stringLength s)) "")))
    ((none) (pair "" s)))

fn identChar? c: String -> Bool
  (not (listContains? (list "(" ")" "[" "]" "{" "}" " " "\t" "\n" "," "\"") c))

; (:m :ref PERF-CLI-REBUILD :do "a type string such as (List sys/Context) or (Map String u/Row) yields its qualified words")
fn typeWords t: String -> (List String)
  (filter (fn [(w String)] -> Bool (qualified? w))
          (stringSplit (stringJoin (map (fn [(c String)] -> String (if (identChar? c) c " ")) (stringChars t)) "") " "))

fn ! modOf mods: (Map String r/ModuleSummary) path: String -> r/ModuleSummary
  (optionOr (mapGet mods path) (r/emptyModuleSummary))

fn targetOf m: r/ModuleSummary word: String -> (Option String)
  (if (qualified? word)
    (mapGet m.imports (pairFirst (splitQual word)))
    (none))

fn typeFilesOf m: r/ModuleSummary -> (List String)
  (let [(fieldTypes (fold (fn [(acc (List String)) (s r/SchemaSummary)] -> (List String) (listAppend acc (map (fn [(f r/FieldSummary)] -> String f.type) s.fields))) (list) (mapValues m.schemas)))
        (caseTypes (fold (fn [(acc (List String)) (e r/EnumSummary)] -> (List String) (fold (fn [(a2 (List String)) (c r/CaseSummary)] -> (List String) (listAppend a2 (map pairSecond c.params))) acc e.cases)) (list) (mapValues m.enums)))]
    (fold (fn [(acc (List String)) (t String)] -> (List String) (fold (fn [(a2 (List String)) (w String)] -> (List String) (match (targetOf m w) ((some p) (cons p a2)) ((none) a2))) acc (typeWords t)))
          (list) (listAppend fieldTypes caseTypes)))

fn ! addFile mods: (Map String r/ModuleSummary) st: Reach path: String -> Reach
  (if (mapHas? st.files path)
    st
    (fold (fn [(acc Reach) (p String)] -> Reach (addFile mods acc p))
          (with st :files (mapSet st.files path true))
          (typeFilesOf (modOf mods path))))

fn cutHit? cuts: (List String) word: String -> Bool
  (listContains? cuts word)

; (:m :ref PERF-CLI-REBUILD :do "one reference of a reached function: a cut name is recorded as bad unless the caller is a gate of the entry module; otherwise the target module is reached and, when the name is one of its functions, that function is queued")
fn refTargets mods: (Map String r/ModuleSummary) m: r/ModuleSummary word: String -> (List (Pair String String))
  (cond
    ((mapHas? m.funs word) (list (pair m.path word)))
    ((qualified? word)
      (match (targetOf m word)
        ((some p) (list (pair p (pairSecond (splitQual word)))))
        ((none) (list))))
    (else (list)))

fn ! visit mods: (Map String r/ModuleSummary) entryPath: String cuts: (List String) gates: (List String) queue: (List (Pair String String)) st: Reach -> Reach
  (match (listHead queue)
    ((none) st)
    ((some job)
      (let [(path (pairFirst job))
            (name (pairSecond job))
            (key (fnKey path name))
            (rest (optionOr (listTail queue) (list)))]
        (if (mapHas? st.seen key)
          (visit mods entryPath cuts gates rest st)
          (let [(m (modOf mods path))
                (st1 (addFile mods (with st :seen (mapSet st.seen key true)) path))]
            (match (mapGet m.funs name)
              ((none) (visit mods entryPath cuts gates rest st1))
              ((some f)
                (let [(gate (and (= path entryPath) (listContains? gates name)))
                      (words (listAppend f.calls (fold (fn [(acc (List String)) (t String)] -> (List String) (listAppend acc (typeWords t))) (list) (cons f.ret (map pairSecond f.params)))))
                      (cutWords (filter (fn [(w String)] -> Bool (and (= path entryPath) (cutHit? cuts w))) words))
                      (bad (if (or gate (listEmpty? cutWords)) st1.bad (cons (str name " -> " (stringJoin cutWords " ")) st1.bad)))
                      (live (filter (fn [(w String)] -> Bool (not (and (= path entryPath) (cutHit? cuts w)))) words))
                      (targets (fold (fn [(acc (List (Pair String String))) (w String)] -> (List (Pair String String)) (listAppend acc (refTargets mods m w))) (list) live))
                      (st2 (fold (fn [(acc Reach) (t (Pair String String))] -> Reach (addFile mods acc (pairFirst t))) (with st1 :bad bad) targets))]
                  (visit mods entryPath cuts gates (listAppend targets rest) st2)))))))))

fn reachFrom mods: (Map String r/ModuleSummary) entryPath: String roots: (List String) cuts: (List String) gates: (List String) -> Reach
  (visit mods entryPath cuts gates (map (fn [(n String)] -> (Pair String String) (pair entryPath n)) roots)
         (Reach :files (mapEmpty) :seen (mapEmpty) :bad (list)))

fn ! resolvedImports m: r/ModuleSummary deps: (Map String r/ModuleSummary) -> (Result (Map String String) String)
  (fold (fn [(acc (Result (Map String String) String)) (alias String)] -> (Result (Map String String) String)
          (match acc
            ((err e) (err e))
            ((ok got) (match (r/resolveDepTarget (optionOr (mapGet m.imports alias) "") deps)
                        ((err e) (err (str "import " alias ": " e)))
                        ((ok t) (ok (mapSet got alias t.path)))))))
        (ok (mapEmpty)) (mapKeys m.imports))

; (:m :ref PERF-CLI-REBUILD :do "closureOf! loads the entry's module closure with bodies (the checker's loader, the same resolution a compile uses), summarizes the entry itself, and walks from roots; the answer is the absolute paths of every reached file, or an error naming an unresolved import, a parse failure or a cut reached outside the gates")
fn ! closureOf! entry: String roots: (List String) cuts: (List String) gates: (List String) -> (Result (List String) String)
  (match (realPath entry)
    ((err e) (err (str "cannot resolve " entry ": " e)))
    ((ok real)
      (match (fileReadString real)
        ((err e) (err (str "cannot read " real ": " e)))
        ((ok src)
          (match (a/parse src)
            ((err pe) (err (str "cannot parse " real ":" (stringFromInt64 pe.line) ": " pe.msg)))
            ((ok forms)
              (let [(cl (r/loadModuleClosure! real true))]
                (cond
                  ((not (listEmpty? cl.unresolved)) (err (str "unresolved: " (stringJoin cl.unresolved "; "))))
                  ((not (listEmpty? cl.errors)) (err (str "closure errors: " (stringJoin cl.errors "; "))))
                  (else
                    (let [(own (r/collectSummary forms real))]
                      (match (resolvedImports own cl.deps)
                        ((err e) (err e))
                        ((ok imports)
                          (let [(mods (mapSet cl.deps real (with own :path real :imports imports)))
                                (st (reachFrom mods real roots cuts gates))]
                            (if (listEmpty? st.bad)
                              (ok (listSort (mapKeys st.files)))
                              (err (str "a cut handler is reached outside the gates: " (stringJoin st.bad "; ")))))))))))))))))
