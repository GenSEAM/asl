(module asl-checker/tests/checkDepIndexTest
  :x [runTests main]
  :i [(types :a ty) (ast :a a) (resolve :a r) (check :a c)])

fn funOf name: String ret: String -> r/FunSummary
  (r/FunSummary :name name :params (list) :ret ret :typevars (list) :hasDoc true :effect false)

fn depSummary k: Int64 gRet: String -> r/ModuleSummary
  (with (r/emptyModuleSummary)
    :name (str "pkg/mod" (stringFromInt64 k)) :path (str "/x/pkg/src/mod" (stringFromInt64 k) ".asl") :hasHeader true :hasDoc true
    :exports (list "f" "g") :funs (mapSet (mapSet (mapEmpty) "f" (funOf "f" "Int64")) "g" (funOf "g" gRet)))

fn synthDeps d: Int64 -> (Map String r/ModuleSummary)
  (fold (fn [(m (Map String r/ModuleSummary)) (k Int64)] -> (Map String r/ModuleSummary) (mapSet m (str "pkg/mod" (stringFromInt64 k)) (depSummary k "Int64"))) (mapEmpty) (range 0 d))

fn synthDepsWithout d: Int64 skip: Int64 -> (Map String r/ModuleSummary)
  (fold (fn [(m (Map String r/ModuleSummary)) (k Int64)] -> (Map String r/ModuleSummary) (if (= k skip) m (mapSet m (str "pkg/mod" (stringFromInt64 k)) (depSummary k "Int64")))) (mapEmpty) (range 0 d))

fn synthSource d: Int64 q: Int64 tail: String -> String
  (str "(module syn :x [h] :i [" (stringJoin (map (fn [(k Int64)] -> String (str "(pkg/mod" (stringFromInt64 k) " :a m" (stringFromInt64 k) ")")) (range 0 d)) " ") "])\nfn h -> Int64\n  (do "
       (stringJoin (map (fn [(i Int64)] -> String (str "(m" (stringFromInt64 (mod i d)) "/f)")) (range 0 q)) " ") " " tail ")\n")

fn parsed src: String -> (List a/TopForm)
  (mt (a/parse src) ((ok forms) forms) ((err _) (list)))

fn texts ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn typeDiags ds: (List ty/Diagnostic) -> (List ty/Diagnostic)
  (filter (fn [(d ty/Diagnostic)] -> Bool (or (= d.code "type") (= d.code "rule-6"))) ds)

fn testCheckerReadsTheIndex -> Bool
  (let [(deps (synthDeps 12))
        (forms (parsed (synthSource 12 40 "(m1/g)")))
        (forged (r/DepIndex :deps (synthDepsWithout 12 1) :indexed true :byKey (mapSet (mapEmpty) "pkg/mod1" (list (depSummary 1 "String")))))
        (viaForged (typeDiags (c/checkModuleIn forms forged "syn.asl")))
        (viaIndex (c/checkModuleIn forms (r/depIndexOf deps) "syn.asl"))
        (viaModule (c/checkModule forms deps "syn.asl"))]
    (do (assert (not (listEmpty? forms)) "the synthetic source parses")
        (assert (listEmpty? viaIndex) (str "a real index types (m1/g) from the map, where g returns Int64: " (texts viaIndex)))
        (assert (= (listLength viaForged) 1) (str "the forged bucket types (m1/g) as String, one mismatch: " (texts viaForged)))
        (assert (listAll? (fn [(d ty/Diagnostic)] -> Bool (and (stringContains? d.message "Int64") (stringContains? d.message "String"))) viaForged) (str "the mismatch names Int64 against String: " (texts viaForged)))
        (assert (= (texts viaModule) (texts viaIndex)) "checkModule over a deps map reports what checkModuleIn over depIndexOf reports")
        true))

fn testCheckSourceDiagnostics -> Bool
  (let [(clean (c/checkSource (synthSource 12 40 "") (synthDeps 12) "syn.asl"))
        (badDeps (mapSet (synthDeps 12) "pkg/mod3" (depSummary 3 "String")))
        (bad (typeDiags (c/checkSource (synthSource 12 40 "(m3/g)") badDeps "syn.asl")))]
    (do (assert (listEmpty? clean) (str "qualified calls into imported signatures type-check: " (texts clean)))
        (assert (= (listLength bad) 1) (str "a String-returning import used as Int64 is one mismatch: " (texts bad)))
        true))

fn ! runTests -> Bool
  (do (assert (testCheckerReadsTheIndex) "the checker reads typed dep lookups from the index it is given")
      (assert (testCheckSourceDiagnostics) "checkSource over a deps map keeps its diagnostics")
      true)

fn ! main args: (List String) -> (Result Int64 String)
  (let [(d (optionOr (mt (listHead args) ((some s) (stringToInt64 s)) ((none) (none))) 50))]
    (do (println (str "diags " (stringFromInt64 (listLength (c/checkSource (synthSource d 2000 "") (synthDeps d) "syn.asl"))))) (ok 0)))
