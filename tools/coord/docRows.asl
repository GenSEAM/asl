(module asl-tools/coord/docRows
  :x [Missing relevantPath? relevant? parseRows addedNames charged moduleFile docFileOf rowText message maxListed]
  :i [(asl-tools/coord/gateGuard :a gg)])

; (:m :ref GATE-DOC-ROWS :do "pure parts of the gate stage's early copy of knowCardsTest's doc assertion: which diff paths make the check worth running, the rows `asl know missing` prints parsed into symbols, the names a diff adds, and the message that tells a cheap writer which doc.asn row to add; the impure caller (git, the child run) lives in conductor.asl")
(schema Missing
  (:f card String)
  (:f module String)
  (:f name String)
  (:f kind String))

fn maxListed -> Int64
  20

; (:m :ref GATE-DOC-ROWS :do "a package source file or a doc.asn: the only paths whose change can add an exported symbol without its contract")
fn relevantPath? p: String -> Bool
  (or (and (stringStartsWith? p "asl/packages/") (and (stringContains? p "/src/") (stringEndsWith? p ".asl")))
      (and (stringStartsWith? p "asl/packages/") (stringEndsWith? p "/doc.asn")))

fn relevant? paths: (List String) -> Bool
  (listAny? relevantPath? paths)

; (:m :ref GATE-DOC-ROWS :do "one row of `asl know missing` is CARD#MODULE/NAME nodoc|nodecl; a line of any other shape (the count header, noise) is not a row")
fn parseRow line: String -> (Option Missing)
  (let [(t (stringTrim line))
        (parts (stringSplit t " "))
        (kind (optionOr (listGet parts 1) ""))
        (sym (optionOr (listGet parts 0) ""))
        (hash (stringSplit sym "#"))
        (path (stringSplit (optionOr (listGet hash 1) "") "/"))]
    (if (and (= (listLength parts) 2) (and (= (listLength hash) 2) (and (or (= kind "nodoc") (= kind "nodecl")) (> (listLength path) 1))))
      (some (Missing :card (optionOr (listGet hash 0) "") :module (stringJoin (listTake path (- (listLength path) 1)) "/") :name (optionOr (listLast path) "") :kind kind))
      (none)))

fn parseRows out: String -> (List Missing)
  (listFlatMap (fn [(l String)] -> (List Missing) (match (parseRow l) ((some m) (list m)) ((none) (list)))) (stringLines out))

fn tokensOf line: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
    (stringSplit (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace line "[" " ") "]" " ") "(" " ") ")" " ") "\"" " ") " "))

fn diffSide diff: String mark: String other: String -> (List String)
  (listFlatMap (fn [(l String)] -> (List String)
                 (if (and (stringStartsWith? l mark) (not (stringStartsWith? l other)))
                   (tokensOf (optionOr (stringSlice l 1 (stringLength l)) ""))
                   (list)))
               (stringLines diff))

; (:m :ref GATE-DOC-ROWS :do "the tokens a -U0 diff adds that it does not also remove: an edited :x line re-adds every name on it, and only the names it did not already have are the unit's")
fn addedNames diff: String -> (List String)
  (let [(removed (diffSide diff "-" "---"))]
    (filter (fn [(t String)] -> Bool (not (listContains? removed t))) (diffSide diff "+" "+++")))

; (:m :ref GATE-DOC-ROWS :do "only a symbol whose name the diff adds is the unit's; a miss the base already had is left to the train's own base attribution")
fn charged rows: (List Missing) added: (List String) -> (List Missing)
  (filter (fn [(m Missing)] -> Bool (listContains? added m.name)) rows)

; (:m :ref GATE-DOC-ROWS :do "the touched file that declares module M, empty when none does")
fn moduleFile files: (List (Pair String String)) module: String -> String
  (match (listFind (fn [(f (Pair String String))] -> Bool (= (gg/moduleName (pairSecond f)) module)) files)
    ((some f) (pairFirst f))
    ((none) ""))

fn packageDirOf file: String card: String -> String
  (let [(cut (stringSplit file "/src/"))]
    (if (and (> (listLength cut) 1) (stringStartsWith? file "asl/packages/")) (optionOr (listHead cut) "") (str "asl/packages/" card)))

fn docFileOf file: String card: String -> String
  (str (packageDirOf file card) "/doc.asn")

fn rowText file: String name: String -> String
  (str "(:doc :symbol \"" (if (stringEmpty? file) "PATH-OF-THE-FILE-THAT-DEFINES-THE-MODULE.asl" file) "#" name "\" :text \"one sentence: what it returns and when it fails\")")

fn lineOf m: Missing file: String -> String
  (if (= m.kind "nodoc")
    (str m.module "/" m.name " has no contract row: add to " (docFileOf file m.card) " the line " (rowText file m.name))
    (str m.module "/" m.name " is exported in :x but has no declaration: declare it in the module or drop it from :x"))

; (:m :ref GATE-DOC-ROWS :do "the red message: one sentence per symbol with the file and the literal row to add, at most maxListed symbols and a count of the rest, on one line")
fn message ms: (List Missing) files: (List (Pair String String)) -> String
  (let [(shown (listTake ms (maxListed)))
        (rest (- (listLength ms) (listLength shown)))]
    (str "docRows: " (stringFromInt64 (listLength ms)) " new exported symbols without a doc.asn contract row, knowCardsTest would fail on them in the train; "
         (stringJoin (map (fn [(m Missing)] -> String (lineOf m (moduleFile files m.module))) shown) "; ")
         (if (> rest 0) (str "; and " (stringFromInt64 rest) " more") "")))
