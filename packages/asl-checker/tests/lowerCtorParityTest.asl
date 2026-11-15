(module asl-checker/tests/lowerCtorParityTest
  :x [runTests]
  :i [(types :a ty) (ast :a a) (resolve :a r) (check :a c)])

; (:m :ref CHECK-LOWER-CONSTRUCTOR :do "every pattern head the lowering rejects with ERR_LOWER_UNKNOWN_CONSTRUCTOR is an ERR_UNKNOWN_CONSTRUCTOR of the checker, naming the constructor at its own line and column; the spelling the lowering accepts for the same intent checks clean")
fn summaryOf src: String path: String -> r/ModuleSummary
  (r/collectSummary (match (a/parse src) ((ok forms) forms) ((err _) (list))) path)

fn deps -> (Map String r/ModuleSummary)
  (let [(depA "(module depA :x [Shape circle square] :i []) (enum Shape (:c circle [(r Int64)] \"round\") (:c square [(s Int64)] \"box\"))")
        (depB "(module depB :x [Tile square hex] :i []) (enum Tile (:c square [(s Int64)] \"box\") (:c hex [(s Int64)] \"hex\"))")
        (depC "(module depC :x [width] :i []) (enum Hidden (:c square [(s Int64)] \"box\") (:c blank [] \"blank\")) (fn width [] -> Int64 3)")
        (base (mapSet (mapSet (mapSet (mapEmpty) "/path/to/depA.asl" (summaryOf depA "/path/to/depA.asl")) "/path/to/depB.asl" (summaryOf depB "/path/to/depB.asl")) "/path/to/depC.asl" (summaryOf depC "/path/to/depC.asl")))]
    (fold (fn [(m (Map String r/ModuleSummary)) (d (Pair String String))] -> (Map String r/ModuleSummary)
            (mapSet m (str "/path/to/" (pairFirst d) ".asl") (summaryOf (pairSecond d) (str "/path/to/" (pairFirst d) ".asl"))))
          base (atomDeps)))

; (:m :ref MATCH-PARITY :do "imports for the bare atom and prelude-name groups: two modules exporting a zero-field case spot, one hiding it in an unexported enum, and one whose cases are named like the prelude case ok and the builtin take")
fn atomDeps -> (List (Pair String String))
  (list (pair "depE" "(module depE :x [Sig spot dash] :i []) (enum Sig (:c spot [] \"s\") (:c dash [] \"d\"))")
        (pair "depF" "(module depF :x [Mark spot blot] :i []) (enum Mark (:c spot [] \"s\") (:c blot [] \"b\"))")
        (pair "depH" "(module depH :x [height] :i []) (enum Veiled (:c spot [] \"s\") (:c void [] \"v\")) (fn height [] -> Int64 3)")
        (pair "depG" "(module depG :x [Wrap ok take] :i []) (enum Wrap (:c ok [(n Int64)] \"o\") (:c take [(n Int64)] \"t\"))"))

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
        (itemsNamed (diagsOf (program "" "fn f items: (List Int64) -> Int64" "(match items ((cons h t) h) (_ 0))")))
        (splitLines (diagsOf (overList "(match xs\n    (_ 0)\n    ((cons h t) h))")))
        (viaHead (diagsOf (overList "(match (listHead xs) ((some h) h) ((none) 0))")))
        (viaEmpty (diagsOf (overList "(if (listEmpty? xs) 0 (listLength xs))")))]
    (do (assert (unknownCtorAt? emptyList "list" 6 15) (str "(list) as a pattern is the lowering's unknown constructor 'list', at the constructor: " (render emptyList)))
        (assert (unknownCtorAt? consCell "cons" 6 15) (str "(cons h t) as a pattern is the lowering's unknown constructor 'cons', at the constructor: " (render consCell)))
        (assert (unknownCtorAt? bracket "list" 6 14) (str "[h] as a pattern is the lowering's (list h), reported at the bracket: " (render bracket)))
        (assert (says? bracket "(list h) is a list pattern") (str "the bracket pattern is named as the lowering reads it: " (render bracket)))
        (assert (says? consCell "branch on listEmpty? or listLength of the matched list") (str "the hint names the matched list rather than a variable: " (render consCell)))
        (assert (not (says? itemsNamed "xs")) (str "the hint names no variable when the scrutinee is named items: " (render itemsNamed)))
        (assert (says? itemsNamed "unknown constructor 'cons' in a match pattern") (str "the code and leading words stay unchanged: " (render itemsNamed)))
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

fn codeSays? ds: (List ty/Diagnostic) code: String text: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code code) (stringContains? d.message text))) ds)

; (:m :ref MATCH-PARITY :do "a bare zero-field case two imports declare, written as an atom pattern: the lowering binds it as a name that matches everything, so the checker reports it with the owners and the qualified spellings; the same atom with one import, qualified, or naming this module's own case is a constructor test in both, and a name no import declares stays a binding")
fn testAmbiguousAtomPattern -> Bool
  (let [(both "(depE :a de) (depF :a df)")
        (over (fn [(imports String) (body String)] -> (List ty/Diagnostic) (diagsOf (program imports "fn f s: de/Sig -> Int64" body))))
        (bare (over both "(match s (spot 1) (dash 2))"))
        (hiddenTwin (over "(depE :a de) (depH :a dh)" "(match s (spot 1) (dash 2))"))
        (qualified (over both "(match s (de/spot 1) (de/dash 2))"))
        (single (over "(depE :a de)" "(match s (spot 1) (dash 2))"))
        (binding (over both "(match s (dash 2) (anything 1))"))
        (otherEnum (diagsOf (program both "fn f s: df/Mark -> Int64" "(match s (blot 1) (spot 2))")))
        (foreign (diagsOf (program both "(enum Own (:c here [] \"h\") (:c there [] \"t\"))\n\nfn f o: Own -> Int64" "(match o (here 1) (spot 2))")))
        (own (diagsOf (program both "(enum Sig (:c spot [] \"s\") (:c dash [] \"d\"))\n\nfn f s: Sig -> Int64" "(match s (spot 1) (dash 2))")))]
    (do (assert (unknownCtorAt? bare "spot" 6 13) (str "a bare atom case two imports declare is reported at the atom: " (render bare)))
        (assert (says? bare "de/spot or df/spot") (str "the diagnostic offers both qualified spellings: " (render bare)))
        (assert (says? bare "depE, depF") (str "the diagnostic names the declaring modules: " (render bare)))
        (assert (says? hiddenTwin "depE, depH") (str "an unexported enum of another import declaring the case counts, as in the lowering: " (render hiddenTwin)))
        (assert (says? otherEnum "de/spot or df/spot") (str "the atom is reported too where the first exporter is not the matched enum and the checker itself bound it as a name: " (render otherEnum)))
        (assert (listEmpty? qualified) (str "the qualified atoms check clean with both imports: " (render qualified)))
        (assert (listEmpty? single) (str "a bare atom case only one import declares checks clean: " (render single)))
        (assert (listEmpty? binding) (str "a lower-case atom that names no case stays a binding: " (render binding)))
        (assert (listEmpty? foreign) (str "an atom whose declaring enums are all other than the matched one binds the subject, as in the lowering: " (render foreign)))
        (assert (listEmpty? own) (str "this module's own case wins over the imports: " (render own)))
        true))

; (:m :ref MATCH-PARITY :do "a case name two enums of one module declare has no spelling that selects one of them and is two declarations to the lowering, so the declaring module is the error")
fn testCaseInTwoEnums -> Bool
  (let [(twice (diagsOf (program "" "(enum One (:c alpha [(s Int64)] \"a\") (:c gamma [(s Int64)] \"g\"))\n\n(enum Two (:c beta [(s Int64)] \"b\") (:c gamma [(s Int64)] \"g2\"))\n\nfn f n: Int64 -> Int64" "n")))
        (apart (diagsOf (program "" "(enum One (:c alpha [(s Int64)] \"a\") (:c gamma [(s Int64)] \"g\"))\n\n(enum Two (:c beta [(s Int64)] \"b\") (:c delta [(s Int64)] \"d\"))\n\nfn f n: Int64 -> Int64" "n")))]
    (do (assert (codeSays? twice "ERR_DUPLICATE_CASE" "case gamma is declared by enums One and Two of this module") (str "one case name in two enums of a module is reported with both enums: " (render twice)))
        (assert (listEmpty? apart) (str "two enums with their own case names check clean: " (render apart)))
        true))

; (:m :ref MATCH-PARITY :do "the prelude before a bare imported case, as type inference and the lowering have it: an import declaring ok or take does not change what (ok n) and (take xs 1) mean in the importer, and its own case is written alias/case")
fn testPreludeBeforeImport -> Bool
  (let [(imp "(depG :a dg)")
        (resultMatch (diagsOf (program imp "fn f w: (Result Int64 String) -> Int64" "(match w ((ok n) n) ((err _) 0))")))
        (listTake (diagsOf (program imp "fn f xs: (List Int64) -> (List Int64)" "(take xs 1)")))
        (barePattern (diagsOf (program imp "fn f w: dg/Wrap -> Int64" "(match w ((take n) n) (_ 0))")))
        (qualified (diagsOf (program imp "fn f w: dg/Wrap -> Int64" "(match w ((dg/take n) n) ((dg/ok n) n))")))]
    (do (assert (listEmpty? resultMatch) (str "ok and err over a Result check clean though an import declares a case ok: " (render resultMatch)))
        (assert (listEmpty? listTake) (str "take over a list keeps the builtin arity though an import declares a case take: " (render listTake)))
        (assert (says? barePattern "qualify it: dg/take") (str "a bare pattern headed by a builtin name an import declares is reported with the qualified spelling: " (render barePattern)))
        (assert (listEmpty? qualified) (str "the qualified cases check clean: " (render qualified)))
        true))

; (:m :ref CHECK-LOWER-CONSTRUCTOR :do "runs the list-pattern, nested, own-case and ambiguous-import groups")
fn runTests -> Bool
  (do (assert (testListPatterns) "list patterns")
      (assert (testNestedListPatterns) "nested list patterns")
      (assert (testOwnCasesNamedLikeLists) "own cases named cons and list")
      (assert (testAmbiguousImportedCase) "ambiguous imported case")
      (assert (testAmbiguousAtomPattern) "ambiguous bare atom pattern")
      (assert (testCaseInTwoEnums) "one case name in two enums")
      (assert (testPreludeBeforeImport) "the prelude before a bare imported case")
      true)
