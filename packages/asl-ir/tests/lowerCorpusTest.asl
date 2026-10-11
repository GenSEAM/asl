(module asl-ir/tests/lowerCorpusTest
  :x [startingTable remainingTable runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)])

fn entryPath -> String
  "asl/packages/asl-compiler/src/compiler.asl"

fn startingTable -> (List (Pair String Int64))
  (list (pair "ERR_LOWER_UNSUPPORTED" 448) (pair "ERR_LOWER_ARITY" 139) (pair "ERR_LOWER_MISSING_FIELD" 11)
        (pair "ERR_LOWER_UNKNOWN_CONSTRUCTOR" 6) (pair "ERR_LOWER_UNKNOWN_SYMBOL" 2))

fn remainingTable -> (List (Pair String Int64))
  (list (pair "preludePairEnum" 86) (pair "predicateTry" 85) (pair "schemaFieldsOmitted" 14)
        (pair "fnTypedParams" 6) (pair "braceInString" 2))

fn firstQuoted text: String -> String
  (optionOr (listGet (stringSplit text "'") 1) "")

fn ! sourcesOf units: (List lk/LinkUnit) -> (Map String String)
  (fold (fn [(acc (Map String String)) (u lk/LinkUnit)] -> (Map String String) (mt (fileRead u.path) ((ok src) (mapSet acc u.path src)) ((err _) acc)))
        (mapEmpty) units)

fn distinctPathsOf units: (List lk/LinkUnit) -> (List String)
  (mapKeys (fold (fn [(acc (Map String Bool)) (u lk/LinkUnit)] -> (Map String Bool) (mapSet acc u.path true)) (mapEmpty) units))

fn locusPath locus: String -> String
  (let [(file (optionOr (listGet (stringSplit locus "@") 1) ""))
        (parts (stringSplit file ":"))]
    (stringJoin (optionOr (listSlice parts 0 (- (listLength parts) 2)) (list)) ":"))

fn blockerOf sources: (Map String String) d: ty/IrDiag -> String
  (let [(quoted (firstQuoted d.message))
        (src (optionOr (mapGet sources (locusPath d.locus)) ""))]
    (cond
      ((= d.code "ERR_LOWER_MISSING_FIELD") "schemaFieldsOmitted")
      ((and (= d.code "ERR_LOWER_UNSUPPORTED") (= quoted "pair")) "preludePairEnum")
      ((and (= d.code "ERR_LOWER_ARITY") (stringContains? d.message "'listAny?' takes 1 argument(s), got 2")) "fnTypedParams")
      ((and (= d.code "ERR_LOWER_UNKNOWN_SYMBOL") (= quoted "i64, i1")) "braceInString")
      ((and (= d.code "ERR_LOWER_UNKNOWN_SYMBOL") (stringContains? src (str quoted "?"))) "predicateTry")
      (else (str "lowerer " d.code " " d.locus ": " d.message))))

fn countOf blockers: (List String) key: String -> Int64
  (listLength (filter (fn [(b String)] -> Bool (= b key)) blockers))

fn ! testCorpus -> Bool
  (let [(res (lk/linkEntry! (entryPath)))
        (units (optionOr (resultToOption (lk/loadClosure! (entryPath))) (list)))
        (prelude (optionOr (resultToOption (lk/loadClosure! (lk/preludePath))) (list)))
        (sources (sourcesOf (listAppend units prelude)))
        (diags (mt res ((ok _) (list)) ((err ds) ds)))
        (blockers (map (fn [(d ty/IrDiag)] -> String (blockerOf sources d)) diags))
        (known (map (fn [(p (Pair String Int64))] -> String (pairFirst p)) (remainingTable)))
        (unknown (filter (fn [(b String)] -> Bool (not (listContains? known b))) blockers))
        (starting (fold (fn [(acc Int64) (p (Pair String Int64))] -> Int64 (+ acc (pairSecond p))) 0 (startingTable)))
        (ratchet (fold (fn [(acc Int64) (p (Pair String Int64))] -> Int64 (+ acc (pairSecond p))) 0 (remainingTable)))]
    (do
      (assert (= (listLength units) 46) (str "the closure loads 46 modules, got " (listLength units)))
      (assert (= (listLength (mapKeys sources)) (listLength (distinctPathsOf (listAppend units prelude))))
              (str "every closure and prelude source is readable, got " (listLength (mapKeys sources)) " of " (listLength (distinctPathsOf (listAppend units prelude)))))
      (assert (listEmpty? unknown) (str "every remaining diagnostic has a blocker outside the lowerer: " (stringJoin unknown "\n")))
      (assert (fold (fn [(acc Bool) (p (Pair String Int64))] -> Bool (and acc (<= (countOf blockers (pairFirst p)) (pairSecond p)))) true (remainingTable))
              (str "no blocker grows past its ratchet: " (stringJoin (map (fn [(p (Pair String Int64))] -> String (str (pairFirst p) " " (countOf blockers (pairFirst p)) "/" (pairSecond p))) (remainingTable)) ", ")))
      (assert (<= (listLength diags) ratchet) (str "at most " ratchet " diagnostics remain, got " (listLength diags)))
      (assert (< ratchet starting) (str "the ratchet " ratchet " is below the starting " starting))
      true))

fn ! runTests -> Bool
  (do (assert (testCorpus) "testCorpus")
      true)
