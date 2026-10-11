(module asl-checker/tests/importSweepTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/types :a ty)
      (asl-syntax/tests/asl/layoutCorpusLib :a cl)])

fn ! isUnimportedAlias? d: ty/Diagnostic -> Bool
  (and (= d.code "rule-9") (stringContains? d.message "is not imported"))

fn ! hitsInFile! path: String -> (List String)
  (mt (fileReadString path)
    ((err _) (list))
    ((ok src)
     (mt (a/parse src)
       ((err _) (list))
       ((ok forms)
        (let [(mod (r/collectSummary forms path))
              (ds (r/resolveModule mod forms (mapEmpty)))]
          (map (fn [(d ty/Diagnostic)] -> String d.message) (filter isUnimportedAlias? ds)))))))

fn ! checkOneFile! path: String n: Int64 -> Int64
  (let [(hits (hitsInFile! path))]
    (do
      (assert (listEmpty? hits) (str path ": uses a qualified name whose alias is never imported (" (stringJoin hits "; ") ")"))
      (+ n 1)))

fn ! checkAllFiles! paths: (List String) n: Int64 -> Int64
  (mt (listHead paths)
    ((none) n)
    ((some p) (checkAllFiles! (optionOr (listTail paths) (list)) (checkOneFile! p n))))

fn ! runTests -> Bool
  (mt (cl/allCorpusFiles!)
    ((err e) (do (assert false (str "git ls-files failed: " e)) false))
    ((ok files)
     (let [(n (checkAllFiles! files 0))]
       (do
         (assert (> n 2000) (str "import sweep checked a realistic corpus size, got " (stringFromInt64 n)))
         true))))
