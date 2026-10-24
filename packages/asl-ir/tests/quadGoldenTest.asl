(module asl-ir/tests/quadGoldenTest
  :x [entries goldenDigests linkedText runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/printer :a prn)
      (asl-ir/link :a lk)])

fn entries -> (List String)
  (list "asl/packages/asl-forms/tests/checkSemanticTest.asl")

; (:m :ref NATIVE-LOWER-GAPS :do "repinned: fused list matches test @listHeadEmpty? or @listTailEmpty? and build the Option on the miss path; assert and refute carry their call site")
; (:m :ref PERF-MAPRANK :do "repinned: the prelude treap rank changed (FNV byte step), then PERF-MONO-MAPKEY ran treap key tests as opsrt.keyCmp (now the LLVM-only ssaOpt nativePrelude body of prelude.preludeKeyOrder) and PERF-FREECHAIN added allocation-free has and getOr walks, so linked IR of the prelude and of map literals moved; measured by this file's own goldenDigests printer")
; (:m :ref HLLOWSMERGE :do "repinned on merge main into sh/HLLOWS: checkSemanticTest.asl's linked-IR digest shifted with the merged tree's own asl-forms/checkSemanticTest.asl content; measured on the merged tree by this file's own goldenDigests printer, never hand-written")
; (:m :ref PERF-REALPATH-CACHE :do "repinned: checkSemanticTest links asl-checker/resolve, whose walk, importer cache and loadModuleDepsIx! changed its linked IR; measured by this file's own goldenDigests printer")
; (:m :ref WAVE1-REDS :do "repinned: COMPILEHOT 5ac2c6a68 rewrote asl-checker/resolve isEffectfulBuiltin? (name chain) and checkSemanticTest links resolve, so its linked IR is 10274 bytes longer; the main-tree pin 3518356563441014170:4946123 predates it; measured by this file's own goldenDigests printer")
; (:m :ref WAVE2 :do "repinned on the integrated tree: unboxed record fields (UFIR UFEMIT), hashRt and loop closure clones changed the linked IR of checkSemanticTest; measured by this file own goldenDigests printer")
fn goldenDigests -> (List (Pair String String))
  (list (pair "asl/packages/asl-forms/tests/checkSemanticTest.asl" "4212955357428612866:4961500")
        (pair "lowerSourceWith" "6806003338108627551:8856"))

fn diagLine d: ty/IrDiag -> String
  (str d.code " " d.message " @ " d.locus)

fn resultText res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (match res
    ((ok m) (str "(ok)\n" (prn/printSsa m)))
    ((err ds) (str "(err)\n" (stringJoin (map diagLine ds) "\n"))))

fn ! linkedText entry: String -> String
  (str (match (lk/loadClosure! entry)
         ((ok units) (stringJoin (map (fn [(u lk/LinkUnit)] -> String (str u.path " " u.name " " (str u.imports))) units) "\n"))
         ((err ds) (stringJoin (map diagLine ds) "\n")))
       "\n"
       (resultText (lk/linkEntry! entry)))

fn sourceCases -> (List String)
  (list "(module q/a :x [main])\n\nfn main -> Int64\n  (listLength (listAppend (list 1 2 3) (map (fn [(x Int64)] -> Int64 (* x 2)) (list 4 5))))\n"
        "(module q/b :x [main])\n\nfn main -> Int64\n  (noSuchFunction 1 2)\n"
        "(module q/c :x [main])\n\n(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\"))\n\nfn area s: Shape -> Int64\n  (match s ((circle r) (* r r)) ((rect w h) (* w h)))\n\nfn main -> Int64\n  (+ (area (circle 2)) (optionOr (listGet (list 1 2 3) 1) 0))\n")

fn ! sourceText -> String
  (match (fileReadString (lk/preludePath))
    ((err _) "(unreadable prelude)")
    ((ok preludeSrc) (stringJoin (map (fn [(src String)] -> String (resultText (lk/lowerSourceWith src preludeSrc))) (sourceCases)) "\n----\n")))

fn ! rootRelative text: String -> String
  (match (realPath ".")
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
