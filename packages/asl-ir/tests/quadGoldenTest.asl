(module asl-ir/tests/quadGoldenTest
  :x [entries goldenDigests linkedText runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/printer :a prn)
      (asl-ir/link :a lk)])

fn entries -> (List String)
  (list "asl/packages/asl-forms/tests/checkSemanticTest.asl")

fn goldenDigests -> (List (Pair String String))
  (list (pair "asl/packages/asl-forms/tests/checkSemanticTest.asl" "-7425021421597155705:3164211")
        (pair "lowerSourceWith" "7145294191011425170:8412"))

fn diagLine d: ty/IrDiag -> String
  (str d.code " " d.message " @ " d.locus)

fn resultText res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res
    ((ok m) (str "(ok)\n" (prn/printSsa m)))
    ((err ds) (str "(err)\n" (stringJoin (map diagLine ds) "\n"))))

fn ! linkedText entry: String -> String
  (str (mt (lk/loadClosure! entry)
         ((ok units) (stringJoin (map (fn [(u lk/LinkUnit)] -> String (str u.path " " u.name " " (str u.imports))) units) "\n"))
         ((err ds) (stringJoin (map diagLine ds) "\n")))
       "\n"
       (resultText (lk/linkEntry! entry)))

fn sourceCases -> (List String)
  (list "(module q/a :x [main])\n\nfn main -> Int64\n  (listLength (listAppend (list 1 2 3) (map (fn [(x Int64)] -> Int64 (* x 2)) (list 4 5))))\n"
        "(module q/b :x [main])\n\nfn main -> Int64\n  (noSuchFunction 1 2)\n"
        "(module q/c :x [main])\n\n(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\"))\n\nfn area s: Shape -> Int64\n  (mt s ((circle r) (* r r)) ((rect w h) (* w h)))\n\nfn main -> Int64\n  (+ (area (circle 2)) (optionOr (listGet (list 1 2 3) 1) 0))\n")

fn ! sourceText -> String
  (mt (fileRead (lk/preludePath))
    ((err _) "(unreadable prelude)")
    ((ok preludeSrc) (stringJoin (map (fn [(src String)] -> String (resultText (lk/lowerSourceWith src preludeSrc))) (sourceCases)) "\n----\n")))

fn ! rootRelative text: String -> String
  (mt (realPath ".")
    ((ok root) (stringReplace text (str root "/") ""))
    ((err _) text))

fn digestOf text: String -> String
  (str (stringFromInt64 (fnv1a64 text)) ":" (stringFromInt64 (stringLength text)))

fn wantOf key: String -> String
  (optionOr (mapGet (fold (fn [(m (Map String String)) (p (Pair String String))] -> (Map String String) (mapSet m (pairFirst p) (pairSecond p))) (mapEmpty) (goldenDigests)) key) "")

fn ! mismatch key: String text: String -> String
  (let [(got (digestOf text))]
    (do (print (str "(quadGolden :entry " key " :digest \"" got "\")"))
        (assert (> (stringLength text) 1000) (str key ": the linked output must not collapse: " (stringLength text)))
        (if (= got (wantOf key)) "" (str key ": want " (wantOf key) ", got " got))))

fn ! runTests -> Bool
  (let [(misses (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
                        (cons (mismatch "lowerSourceWith" (rootRelative (sourceText)))
                              (map (fn [(e String)] -> String (mismatch e (rootRelative (linkedText e)))) (entries)))))]
    (do (assert (listEmpty? misses) (str "linked IR and link diagnostics are byte-identical to the pre-QUAD-LISTGET goldens: " (stringJoin misses "; ")))
        true))
