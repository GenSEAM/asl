(module asl-ir/tests/checkLowerParityTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/printer :a prn)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-parser/ast :a ast)
      (asl-checker/types :a cty)
      (asl-checker/resolve :a r)
      (asl-checker/check :a c)])

; (:m :ref MATCH-PARITY :do "the gate asl-checker/tests/lowerCtorParityTest cannot be, since asl-ir depends on asl-checker and not the reverse: each row is a consumer module with its imports, checked (the consumer and every module it imports, as asl check does) and lowered (lowerLinked) in one process; a row the checker accepts must lower, and its lowered text must hold the constructor, switch or builtin the source means; a row the checker rejects names the diagnostic that says why")
(schema Row (:f name String) (:f imports (List (Pair String String))) (:f body String) (:f accept Bool) (:f want String) (:f never String))

fn depSources -> (Map String String)
  (mapFromPairs (list
    (pair "depA" "(module depA :x [Sig spot dash] :i []) (enum Sig (:c spot [] \"s\") (:c dash [] \"d\"))")
    (pair "depB" "(module depB :x [Mark spot blot] :i []) (enum Mark (:c spot [] \"s\") (:c blot [] \"b\"))")
    (pair "depC" "(module depC :x [width] :i []) (enum Hidden (:c spot [] \"s\") (:c blank [] \"b\")) (fn width [] -> Int64 3)")
    (pair "depD" "(module depD :x [One Two alpha beta] :i []) (enum One (:c alpha [(s Int64)] \"a\") (:c gamma [(s Int64)] \"g\")) (enum Two (:c beta [(s Int64)] \"b\") (:c gamma [(s Int64)] \"g2\"))")
    (pair "depE" "(module depE :x [Wrap some ok take stringLength plain] :i []) (enum Wrap (:c some [(n Int64)] \"s\") (:c ok [(n Int64)] \"o\") (:c take [(n Int64)] \"t\") (:c stringLength [(n Int64)] \"l\") (:c plain [(n Int64)] \"p\"))")
    (pair "depP" "(module depP :x [ProcessError notFound timeout] :i []) (enum ProcessError (:c notFound [] \"n\") (:c timeout [] \"t\"))")))

fn depPath name: String -> String
  (str "/path/to/" name ".asl")

fn formsOf src: String -> (List ast/TopForm)
  (match (ast/parse src) ((ok forms) forms) ((err _) (list)))

fn checkerDeps -> (Map String r/ModuleSummary)
  (fold (fn [(m (Map String r/ModuleSummary)) (name String)] -> (Map String r/ModuleSummary)
          (mapSet m (depPath name) (r/collectSummary (formsOf (optionOr (mapGet (depSources) name) "")) (depPath name))))
        (mapEmpty) (mapKeys (depSources)))

fn program row: Row -> String
  (str "(module consumer\n  :x [f]\n  :i ["
       (stringJoin (map (fn [(a (Pair String String))] -> String (str "(" (pairSecond a) " :a " (pairFirst a) ")")) row.imports) " ")
       "])\n\n" row.body "\n")

fn diagLines src: String path: String -> (List String)
  (match (ast/parseForTypeCheck src)
    ((err e) (list (str path ": parse " e.msg)))
    ((ok forms) (map (fn [(d cty/Diagnostic)] -> String (str path ": " d.code " " d.message)) (c/checkModuleSource forms (checkerDeps) path src))))

fn checkText row: Row -> String
  (stringJoin (fold (fn [(acc (List String)) (a (Pair String String))] -> (List String)
                      (listAppend acc (diagLines (optionOr (mapGet (depSources) (pairSecond a)) "") (depPath (pairSecond a)))))
                    (diagLines (program row) "consumer.asl") row.imports)
              " | ")

; (:m :ref MATCH-BY-SCRUTINEE :do "the consumer's forms as the linker hands them to the lowering: asl-ir/link#elaborateUnits over the consumer and its imports, with the imports resolved to their paths, writes the case the matched enum names into the patterns")
fn linkedForms forms: (List ast/TopForm) row: Row -> (List ast/TopForm)
  (let [(deps (map (fn [(a (Pair String String))] -> lk/LinkUnit (lk/LinkUnit :path (depPath (pairSecond a)) :name (pairSecond a) :forms (formsOf (optionOr (mapGet (depSources) (pairSecond a)) "")) :positions (mapEmpty) :imports (list))) row.imports))
        (consumer (lk/LinkUnit :path "consumer.asl" :name "consumer" :forms forms :positions (mapEmpty) :imports (map (fn [(a (Pair String String))] -> (Pair String String) (pair (pairFirst a) (depPath (pairSecond a)))) row.imports)))]
    (match (listHead (lk/elaborateUnits (cons consumer deps)))
      ((some u) u.forms)
      ((none) forms)))

fn lowerText row: Row -> String
  (let [(src (program row))
        (imports (fold (fn [(m (Map String (List ast/TopForm))) (a (Pair String String))] -> (Map String (List ast/TopForm))
                         (mapSet m (pairFirst a) (formsOf (optionOr (mapGet (depSources) (pairSecond a)) ""))))
                       (mapEmpty) row.imports))]
    (match (ast/parse src)
      ((err e) (str "lowering failed: parse " e.msg))
      ((ok parsed) (match (low/lowerLinked (linkedForms parsed row) (low/declPositions src) (low/LinkScope :path "consumer.asl" :imports imports :prelude (list) :strings (list) :only (none)))
                    ((ok m) (prn/printSsa m))
                    ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")))))))

; (:m :ref MATCH-PARITY :do "what a row breaks, one line per broken claim; empty when the row holds. A red run names every broken row of the table in its first failing assert, so one run of a mutant shows all it breaks")
fn rowFailures row: Row -> (List String)
  (let [(checked (checkText row))
        (lowered (lowerText row))
        (checkOk (stringEmpty? checked))
        (lowerOk (not (stringStartsWith? lowered "lowering failed: ")))
        (seen (str " {check [" checked "] lowered " lowered "}"))
        (claims (list (pair (or (not checkOk) lowerOk) "a program the checker accepts lowers")
                      (pair (= checkOk row.accept) (str "the checker " (if row.accept "accepts" "rejects") " the program"))
                      (pair (stringContains? (if row.accept lowered checked) row.want) (str (if row.accept "the lowered module holds " "the diagnostics say ") row.want))
                      (pair (or (stringEmpty? row.never) (not (stringContains? lowered row.never))) (str "the lowered module never holds " row.never))))]
    (map (fn [(c (Pair Bool String))] -> String (str row.name ": " (pairSecond c) seen))
         (filter (fn [(c (Pair Bool String))] -> Bool (not (pairFirst c))) claims)))

fn rowHolds row: Row broken: String -> Bool
  (let [(failures (rowFailures row))]
    (do (assert (listEmpty? failures) (str (stringJoin failures "\n") "\nbroken rows of the table: " broken))
        true))

fn sigMatch -> String
  "fn f s: da/Sig -> Int64\n  (match s (spot 1) (dash 2))"

fn ownSig -> String
  "(enum Sig (:c spot [] \"s\") (:c dash [] \"d\"))\n\nfn f s: Sig -> Int64\n  (match s (spot 1) (dash 2))"

fn atomRows -> (List Row)
  (let [(ab (list (pair "da" "depA") (pair "db" "depB")))
        (a (list (pair "da" "depA")))]
    (list (Row :name "atomTwoImports" :imports ab :body (sigMatch) :accept true :want "(switch s depA.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "")
          (Row :name "atomHiddenTwin" :imports (list (pair "da" "depA") (pair "dc" "depC")) :body (sigMatch) :accept true :want "(switch s depA.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "")
          (Row :name "atomOneImport" :imports a :body (sigMatch) :accept true :want "(switch s depA.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "")
          (Row :name "atomTwoImportsOtherEnum" :imports ab :body "fn f s: db/Mark -> Int64\n  (match s (blot 1) (spot 2))" :accept true :want "(switch s depB.Mark (blot (arm0.0)) (spot (arm0.1)))" :never "default")
          (Row :name "atomOfAnotherEnumBinds" :imports ab :body "fn f s: db/Mark -> Int64\n  (match s (blot 1) (dash 2))" :accept true :want "(switch s depB.Mark (blot (arm0.0)) (default (arm0.1)))" :never "")
          (Row :name "atomOfTwoOtherEnumsBinds" :imports ab :body "(enum Own (:c here [] \"h\") (:c there [] \"t\"))\n\nfn f o: Own -> Int64\n  (match o (here 1) (spot 2))" :accept true :want "(switch o consumer.Own (here (arm0.0)) (default (arm0.1)))" :never "")
          (Row :name "atomQualified" :imports ab :body "fn f s: da/Sig -> Int64\n  (match s (da/spot 1) (da/dash 2))" :accept true :want "(switch s depA.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "")
          (Row :name "atomOwn" :imports (list) :body (ownSig) :accept true :want "(switch s consumer.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "")
          (Row :name "atomOwnOverImports" :imports ab :body (ownSig) :accept true :want "(switch s consumer.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "depA.Sig")
          (Row :name "atomName" :imports ab :body "fn f s: da/Sig -> Int64\n  (match s (dash 2) (rest 1))" :accept true :want "(switch s depA.Sig (dash (arm0.0)) (default (arm0.1)))" :never "")))

fn sameModuleRows -> (List Row)
  (list (Row :name "importTwoEnumsOneCase" :imports (list (pair "dd" "depD")) :body "fn f s: dd/Two -> Int64\n  (match s ((dd/beta r) r) ((gamma q) q))" :accept false :want "ERR_DUPLICATE_CASE case gamma is declared by enums One and Two of this module" :never "")
        (Row :name "ownTwoEnumsOneCase" :imports (list) :body "(enum One (:c alpha [(s Int64)] \"a\") (:c gamma [(s Int64)] \"g\"))\n\n(enum Two (:c beta [(s Int64)] \"b\") (:c gamma [(s Int64)] \"g2\"))\n\nfn f n: Int64 -> Two\n  (gamma n)" :accept false :want "consumer.asl: ERR_DUPLICATE_CASE case gamma is declared by enums One and Two of this module" :never ""))

fn ownCaseRow name: String -> Row
  (Row :name (str "ownCase-" name) :imports (list)
       :body (str "(enum Op (:c " name " [(n Int64)] \"c\") (:c halt [] \"h\"))\n\nfn g o: Op -> Int64\n  (match o ((" name " k) k) ((halt) 0))\n\nfn f n: Int64 -> Int64\n  (g (" name " n))")
       :accept true :want (str "(construct consumer.Op " name " ") :never "listTake")

fn importRows -> (List Row)
  (let [(e (list (pair "de" "depE")))]
    (list (Row :name "preludeSomeOverImport" :imports e :body "fn f n: Int64 -> (Option Int64)\n  (some n)" :accept true :want "(construct Option some " :never "depE.Wrap")
          (Row :name "preludeOkPatternOverImport" :imports e :body "fn f w: (Result Int64 String) -> Int64\n  (match w ((ok n) n) ((err _) 0))" :accept true :want "(switch w Result (ok (arm0.0)) (err (arm0.1)))" :never "depE.Wrap")
          (Row :name "importSomeNeedsAlias" :imports e :body "fn f n: Int64 -> de/Wrap\n  (some n)" :accept false :want "expected de/Wrap, found (Option Int64)" :never "")
          (Row :name "importSomeQualified" :imports e :body "fn f n: Int64 -> de/Wrap\n  (de/some n)" :accept true :want "(construct depE.Wrap some " :never "Option")
          (Row :name "builtinOverImport" :imports e :body "fn f s: String -> Int64\n  (stringLength s)" :accept true :want "stringLength" :never "construct")
          (Row :name "importBuiltinNamePattern" :imports e :body "fn f w: de/Wrap -> Int64\n  (match w ((take n) n) (_ 0))" :accept true :want "(switch w depE.Wrap (take (arm0.0))" :never "listTake")
          (Row :name "importBuiltinNameQualified" :imports e :body "fn f w: de/Wrap -> Int64\n  (match w ((de/take n) n) (_ 0))" :accept true :want "(switch w depE.Wrap (take (arm0.0))" :never "")
          (Row :name "importPlainBare" :imports e :body "fn f n: Int64 -> Int64\n  (match (plain n) ((plain k) k) (_ 0))" :accept true :want "(construct depE.Wrap plain " :never "")))

; (:m :ref MATCH-BY-SCRUTINEE :do "a bare case name in a pattern is first a case of the enum inferred for its position, in the check and in what the linker lowers: the scrutinee's enum at the top, the field's enum one level down; a name the matched enum lacks, or a position with no known enum, keeps the name-scope rule")
fn scrutineeRows -> (List Row)
  (let [(a (list (pair "da" "depA")))
        (ab (list (pair "da" "depA") (pair "db" "depB")))
        (p (list (pair "dp" "depP")))
        (e (list (pair "de" "depE")))
        (nested "fn f o: (Option da/Sig) -> Int64\n  (match o ((some (spot)) 1) ((some (dash)) 2) ((none) 0))")
        (col "(enum Col (:c red [] \"r\") (:c blue [] \"b\"))\n\n")]
    (list (Row :name "preludeCaseOfImportedEnum" :imports p :body "fn f e: dp/ProcessError -> Int64\n  (match e ((notFound) 0) ((timeout) 1))" :accept true :want "(switch e depP.ProcessError (notFound (arm0.0)) (timeout (arm0.1)))" :never "IoError")
          (Row :name "preludeAtomOfImportedEnum" :imports p :body "fn f e: dp/ProcessError -> Int64\n  (match e (notFound 0) (timeout 1))" :accept true :want "(switch e depP.ProcessError (notFound (arm0.0)) (timeout (arm0.1)))" :never "default")
          (Row :name "preludeCaseNoEnumHint" :imports p :body "fn f e: Int64 -> Int64\n  (match e ((notFound) 0) ((timeout) 1))" :accept false :want "qualify it: dp/notFound" :never "")
          (Row :name "importCasesNamedLikePrelude" :imports e :body "fn f w: de/Wrap -> Int64\n  (match w ((some n) n) ((ok n) n) ((take n) n) ((stringLength n) n) ((plain n) n))" :accept true :want "(switch w depE.Wrap (some (arm0.0)) (ok (arm0.1)) (take (arm0.2)) (stringLength (arm0.3)) (plain (arm0.4)))" :never "")
          (Row :name "atomNoEnumStaysAmbiguous" :imports ab :body "fn f s: Int64 -> Int64\n  (match s (spot 1) (_ 2))" :accept false :want "qualify it: da/spot or db/spot" :never "")
          (Row :name "atomLocalNamedLikeCase" :imports ab :body "fn f s: da/Sig spot: Int64 -> Int64\n  (match s (spot spot) (dash 2))" :accept true :want "(switch s depA.Sig (spot (arm0.0)) (dash (arm0.1)))" :never "default")
          (Row :name "atomOwnLocalNamedLikeCase" :imports (list) :body (str col "fn f c: Col blue: Int64 -> Int64\n  (match c (red 1) (blue blue))") :accept true :want "(switch c consumer.Col (red (arm0.0)) (blue (arm0.1)))" :never "default")
          (Row :name "nestedImportCases" :imports a :body nested :accept true :want "depA.Sig (spot (arm" :never "")
          (Row :name "nestedTwoImportCases" :imports ab :body nested :accept true :want "depA.Sig (spot (arm" :never "depB")
          (Row :name "nestedOwnCases" :imports (list) :body (str col "fn f o: (Option Col) -> Int64\n  (match o ((some (red)) 1) ((some (blue)) 2) ((none) 0))") :accept true :want "consumer.Col (red (arm" :never "")
          (Row :name "nestedOwnAtomRefused" :imports (list) :body (str col "fn f o: (Option Col) -> Int64\n  (match o ((some red) 1) ((none) 0))") :accept false :want "ERR_NESTED_CASE_ATOM nested pattern red names the zero-field case red of Col, which a bare name does not test: write (red) to test for the case, or rename the binder, e.g. redValue, to bind the value" :never "")
          (Row :name "nestedPreludeAtomRefused" :imports (list) :body "fn f r: (Result Int64 IoError) -> Int64\n  (match r ((ok v) v) ((err other) 7))" :accept false :want "ERR_NESTED_CASE_ATOM nested pattern other names the zero-field case other of IoError, which a bare name does not test: write (other) to test for the case, or rename the binder, e.g. otherValue, to bind the value" :never "")
          (Row :name "nestedImportAtomRefused" :imports a :body "fn f o: (Option da/Sig) -> Int64\n  (match o ((some spot) 1) ((none) 0))" :accept false :want "ERR_NESTED_CASE_ATOM nested pattern spot names the zero-field case da/spot of Sig, which a bare name does not test: write (da/spot) to test for the case, or rename the binder, e.g. spotValue, to bind the value" :never "")
          (Row :name "nestedRepeatedCase" :imports a :body "fn f o: (Option da/Sig) -> Int64\n  (match o ((some (spot)) 1) ((some (spot)) 2) ((none) 0))" :accept false :want "ERR_UNREACHABLE_ARM mt arm (some (spot)) is unreachable: the earlier arm (some (spot)) already matches" :never "")
          (Row :name "nestedRepeatedBinder" :imports (list) :body "fn f o: (Option Int64) -> Int64\n  (match o ((some x) x) ((some y) y) ((none) 0))" :accept false :want "ERR_UNREACHABLE_ARM mt arm (some y) is unreachable: the earlier arm (some x) already matches" :never "")
          (Row :name "atomThenListCase" :imports (list) :body (str col "fn f c: Col -> Int64\n  (match c (red 1) ((red) 2) ((blue) 3))") :accept false :want "ERR_UNREACHABLE_ARM mt arm (red) is unreachable: the earlier arm red already matches" :never "")
          (Row :name "listThenAtomCase" :imports (list) :body (str col "fn f c: Col -> Int64\n  (match c ((red) 1) (red 2) (blue 3))") :accept false :want "ERR_UNREACHABLE_ARM mt arm red is unreachable: the earlier arm (red) already matches" :never "")
          (Row :name "nestedNameOfNoCaseBinds" :imports a :body "fn f o: (Option da/Sig) -> Int64\n  (match o ((some sig) 1) ((none) 0))" :accept true :want "(switch o Option" :never "depA.Sig (")
          (Row :name "nestedBinderNamedLikeFieldedCaseBinds" :imports (list) :body "(enum Box (:c box [(n Int64)] \"b\"))\n\nfn f o: (Option Box) -> Int64\n  (match o ((some box) (match box ((box n) n))) ((none) 0))" :accept true :want "(switch o Option" :never "")
          (Row :name "nestedAtomOtherEnumBinds" :imports ab :body (str col "fn f o: (Option Col) -> Int64\n  (match o ((some spot) 1) ((none) 0))") :accept true :want "(switch o Option" :never "Sig")))

fn allRows -> (List Row)
  (listAppend (atomRows) (listAppend (sameModuleRows) (listAppend (map ownCaseRow (list "take" "drop" "map" "filter" "first" "rest" "dot" "some" "ok")) (listAppend (importRows) (scrutineeRows)))))

fn runTests -> Bool
  (let [(rows (allRows))
        (broken (stringJoin (map (fn [(r Row)] -> String r.name) (filter (fn [(r Row)] -> Bool (not (listEmpty? (rowFailures r)))) rows)) ", "))]
    (do (assert (listContains? (map (fn [(r Row)] -> String r.name) rows) "atomTwoImports") "the table holds the two-import atom row")
        (assert (listAll? (fn [(r Row)] -> Bool (rowHolds r broken)) rows) "every row holds")
        true))
