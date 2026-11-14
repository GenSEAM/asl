(module asl-checker/tests/lowerCtorParityTest
  :x [runTests]
  :i [(types :a ty) (ast :a a) (resolve :a r) (check :a c)])

; (:m :ref CHECK-LOWER-CONSTRUCTOR :do "every pattern head the lowering rejects with ERR_LOWER_UNKNOWN_CONSTRUCTOR is an ERR_UNKNOWN_CONSTRUCTOR of the checker, naming the constructor at its own line and column; the spelling the lowering accepts for the same intent checks clean")
fn summaryOf src: String path: String -> r/ModuleSummary
  (r/collectSummary (match (a/parse src) ((ok forms) forms) ((err _) (list))) path)

fn deps -> (Map String r/ModuleSummary)
  (let [(depA "(module depA :x [Shape circle square] :i []) (enum Shape (:c circle [(r Int64)] \"round\") (:c square [(s Int64)] \"box\"))")
        (depB "(module depB :x [Tile square hex] :i []) (enum Tile (:c square [(s Int64)] \"box\") (:c hex [(s Int64)] \"hex\"))")
        (depC "(module depC :x [width] :i []) (enum Hidden (:c square [(s Int64)] \"box\") (:c blank [] \"blank\")) (fn width [] -> Int64 3)")]
    (mapSet (mapSet (mapSet (mapEmpty) "/path/to/depA.asl" (summaryOf depA "/path/to/depA.asl")) "/path/to/depB.asl" (summaryOf depB "/path/to/depB.asl")) "/path/to/depC.asl" (summaryOf depC "/path/to/depC.asl")))

fn diagsOf src: String -> (List ty/Diagnostic)
  (match (a/parseForTypeCheck src)
    ((err _) (list (ty/Diagnostic :path "consumer.asl" :line 0 :col 0 :code "parse" :message "parse" :msg "parse")))
    ((ok forms) (c/checkModuleSource forms (deps) "consumer.asl" src)))

fn program imports: String decl: String body: String -> String
  (str "(module consumer\n  :x [f]\n  :i [" imports "])\n\n" decl "\n  " body "\n")

fn overList body: String -> String
  (program "" "fn f xs: (List Int64) -> Int64" body)

fn overShape imports: String body: String -> String
  (program imports "fn f s: da/Shape -> Int64" body)

fn render ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.line ":" d.col " " d.code " " d.message)) ds) " | ")

fn unknownCtorAt? ds: (List ty/Diagnostic) quoted: String line: Int64 col: Int64 -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool
              (and (= d.code "ERR_UNKNOWN_CONSTRUCTOR")
                   (and (stringStartsWith? d.message (str "unknown constructor '" quoted "' in a match pattern"))
                        (and (= d.line line) (= d.col col)))))
            ds)

fn says? ds: (List ty/Diagnostic) text: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "ERR_UNKNOWN_CONSTRUCTOR") (stringContains? d.message text))) ds)

fn testListPatterns -> Bool
  (let [(emptyList (diagsOf (overList "(match xs ((list) 0) (_ 1))")))
        (consCell (diagsOf (overList "(match xs ((cons h t) h) (_ 0))")))
        (bracket (diagsOf (overList "(match xs ([h] h) (_ 0))")))
        (splitLines (diagsOf (overList "(match xs\n    (_ 0)\n    ((cons h t) h))")))
        (viaHead (diagsOf (overList "(match (listHead xs) ((some h) h) ((none) 0))")))
        (viaEmpty (diagsOf (overList "(if (listEmpty? xs) 0 (listLength xs))")))]
    (do (assert (unknownCtorAt? emptyList "list" 6 15) (str "(list) as a pattern is the lowering's unknown constructor 'list', at the constructor: " (render emptyList)))
        (assert (unknownCtorAt? consCell "cons" 6 15) (str "(cons h t) as a pattern is the lowering's unknown constructor 'cons', at the constructor: " (render consCell)))
        (assert (unknownCtorAt? bracket "list" 6 14) (str "[h] as a pattern is the lowering's (list h), reported at the bracket: " (render bracket)))
        (assert (says? bracket "(list h) is a list pattern") (str "the bracket pattern is named as the lowering reads it: " (render bracket)))
        (assert (says? consCell "listHead") (str "the diagnostic names the forms that do lower: " (render consCell)))
        (assert (unknownCtorAt? splitLines "cons" 8 7) (str "the position is the pattern's own line, not the match's: " (render splitLines)))
        (assert (listEmpty? viaHead) (str "matching (listHead xs) on some and none checks clean: " (render viaHead)))
        (assert (listEmpty? viaEmpty) (str "listEmpty? and listLength check clean: " (render viaEmpty)))
        true))

fn testNestedListPatterns -> Bool
  (let [(decl "fn f o: (Option (List Int64)) -> Int64")
        (bracket (diagsOf (program "" decl "(match o ((some [a b]) a) (_ 0))")))
        (consCell (diagsOf (program "" decl "(match o ((some (cons h t)) h) (_ 0))")))
        (inPair (diagsOf (program "" "fn f p: (Pair Int64 (List Int64)) -> Int64" "(match p ((pair a (list b)) (+ a b)) (_ 0))")))
        (named (diagsOf (program "" decl "(match o ((some xs) (listLength xs)) ((none) 0))")))]
    (do (assert (unknownCtorAt? bracket "list" 6 19) (str "a bracket pattern in a payload position is reported there: " (render bracket)))
        (assert (unknownCtorAt? consCell "cons" 6 20) (str "a cons pattern in a payload position is reported there: " (render consCell)))
        (assert (unknownCtorAt? inPair "list" 6 22) (str "a list pattern inside a pair pattern is reported there: " (render inPair)))
        (assert (listEmpty? named) (str "binding the payload by name checks clean: " (render named)))
        true))

fn testOwnCasesNamedLikeLists -> Bool
  (let [(own (diagsOf (program "" "(enum Op (:c cons [(n Int64)] \"c\") (:c list [] \"l\"))\n\nfn f o: Op -> Int64" "(match o ((cons n) n) ((list) 0))")))]
    (do (assert (listEmpty? own) (str "a module's own cases named cons and list are constructors of its enum, as in the lowering: " (render own)))
        true))

fn testAmbiguousImportedCase -> Bool
  (let [(both "(depA :a da) (depB :a db)")
        (bare (diagsOf (overShape both "(match s ((da/circle r) r) ((square q) q))")))
        (hiddenTwin (diagsOf (overShape "(depA :a da) (depC :a dc)" "(match s ((da/circle r) r) ((square q) q))")))
        (qualified (diagsOf (overShape both "(match s ((da/circle r) r) ((da/square q) q))")))
        (single (diagsOf (overShape "(depA :a da)" "(match s ((circle r) r) ((square q) q))")))
        (unrelated (diagsOf (overShape both "(match s ((circle r) r) ((da/square q) q))")))]
    (do (assert (unknownCtorAt? bare "square" 6 32) (str "a bare case two imports declare is the lowering's unknown constructor, at the constructor: " (render bare)))
        (assert (says? bare "da/square or db/square") (str "the diagnostic offers both qualified spellings: " (render bare)))
        (assert (says? bare "depA, depB") (str "the diagnostic names the declaring modules: " (render bare)))
        (assert (unknownCtorAt? hiddenTwin "square" 6 32) (str "an unexported enum of another import declaring the same case counts, as it does in the lowering: " (render hiddenTwin)))
        (assert (listEmpty? qualified) (str "the qualified case checks clean with both imports: " (render qualified)))
        (assert (listEmpty? single) (str "a bare case only one import declares checks clean: " (render single)))
        (assert (listEmpty? unrelated) (str "a bare case of one import is not ambiguous because another case is: " (render unrelated)))
        true))

; (:m :ref CHECK-LOWER-CONSTRUCTOR :do "runs the list-pattern, nested, own-case and ambiguous-import groups")
fn runTests -> Bool
  (do (assert (testListPatterns) "list patterns")
      (assert (testNestedListPatterns) "nested list patterns")
      (assert (testOwnCasesNamedLikeLists) "own cases named cons and list")
      (assert (testAmbiguousImportedCase) "ambiguous imported case")
      true)
