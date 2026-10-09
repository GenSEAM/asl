(module asl-ir/tests/irDocsTest
  :x [runTests]
  :i [(asl-parser/ast :a a)])

fn srcDir -> String
  "asl/packages/asl-ir/src"

fn ! sourceFiles -> (List String)
  (mt (dirList (srcDir))
    ((err _) (list))
    ((ok names) (map (fn [(n String)] -> String (str (srcDir) "/" n)) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) names))))

fn ledgerPath -> String
  "asl/packages/asl-ir/doc.asn"

fn rowDoc line: String -> (List (Pair String String))
  (if (stringStartsWith? line "(:doc :symbol \"")
    (let [(parts (stringSplit line "\" :text \""))
          (symbol (optionOr (stringSlice (optionOr (listGet parts 0) "") 15 (stringLength (optionOr (listGet parts 0) ""))) ""))
          (text (optionOr (listGet parts 1) ""))]
      (list (pair symbol (optionOr (stringSlice text 0 (- (stringLength text) 2)) ""))))
    (list))

fn ! ledgerDocs -> (List (Pair String String))
  (mt (fileReadString (ledgerPath))
    ((err _) (list))
    ((ok t) (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String)) (listAppend acc (rowDoc line))) (list) (stringSplit t "\n"))))

fn documented? docs: (List (Pair String String)) symbol: String -> Bool
  (listAny? (fn [(d (Pair String String))] -> Bool (and (= (pairFirst d) symbol) (> (stringLength (stringTrim (pairSecond d))) 2))) docs)

fn undocumented docs: (List (Pair String String)) path: String t: a/TopForm -> (List String)
  (mt t
    ((a/topDefun d) (if (and d.isExported (not (documented? docs (str path "#" d.name)))) (list (str path ": " d.name)) (list)))
    (_ (list)))

fn ! missingIn docs: (List (Pair String String)) path: String -> (List String)
  (mt (fileRead path)
    ((err _) (list (str path ": unreadable")))
    ((ok src) (mt (a/parse src)
                ((err pe) (list (str path ":" pe.line ":" pe.col ": parse error: " pe.msg)))
                ((ok forms) (fold (fn [(acc (List String)) (t a/TopForm)] -> (List String) (listAppend acc (undocumented docs path t))) (list) forms)))))

fn ! exportedCount path: String -> Int64
  (mt (fileRead path)
    ((err _) 0)
    ((ok src) (mt (a/parse src)
                ((err _) 0)
                ((ok forms) (listLength (filter (fn [(t a/TopForm)] -> Bool (mt t ((a/topDefun d) d.isExported) (_ false))) forms))))))

fn ! runTests -> Bool
  (let [(files (sourceFiles))
        (docs (ledgerDocs))
        (missing (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (missingIn docs p))) (list) files))
        (exported (fold (fn [(acc Int64) (p String)] -> Int64 (+ acc (exportedCount p))) 0 files))]
    (do
      (assert (= (listLength files) 10) (str "asl-ir/src holds 10 modules, got " (listLength files)))
      (assert (> exported 80) (str "the modules export their functions, got " exported))
      (assert (> (listLength docs) 80) (str "asl-ir/doc.asn holds the package's doc rows, got " (listLength docs)))
      (assert (listEmpty? missing) (str "every exported fn has a doc.asn row; missing: " (stringJoin missing "; ")))
      true))
