(module asl-ir/tests/lowerScaleTest
  :x [depSource mainSource chainFunction main runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/verify :a vfy)
      (asl-ir/link :a lk)
      (asl-ir/printer :a pr)
      (asl-parser/ast :a ast)
      (tools/fleet/run :a run)
      (tools/nativeTest :a nt)])

fn thisFile -> String
  "asl/packages/asl-ir/tests/lowerScaleTest.asl"

fn depDecl i: Int64 -> String
  (str "(enum E" i " (:c a" i " [(x Int64)] \"a\") (:c b" i " [] \"b\"))\n"
       "(schema S" i " (:f x Int64) (:f y Int64 :default " i "))\n"
       "fn d" i " e: E" i " -> Int64\n  (mt e ((a" i " x) x) ((b" i ") " i "))\n\n")

fn depSource n: Int64 -> String
  (str "(module q/dep :x [" (stringJoin (map (fn [(i Int64)] -> String (str "E" i " S" i " d" i)) (range 0 n)) " ") "] :i [])\n\n"
       (stringJoin (map depDecl (range 0 n)) ""))

fn mainDecl i: Int64 -> String
  (str "(enum M" i " (:c m" i " [(x Int64)] \"m\") (:c n" i " [] \"n\"))\n"
       "(schema T" i " (:f x Int64) (:f z Int64 :default " i "))\n"
       "fn u" i " -> Int64\n  (+ (dep/d" i " (a" i " " i ")) (mt (m" i " " i ") ((m" i " x) (+ x (T" i " :x 1).z)) ((n" i ") 0)))\n\n")

fn mainSource n: Int64 -> String
  (str "(module q/main :x [" (stringJoin (map (fn [(i Int64)] -> String (str "u" i)) (range 0 n)) " ") "] :i [(q/dep :a dep)])\n\n"
       (stringJoin (map mainDecl (range 0 n)) ""))

fn parsed src: String -> (List ast/TopForm)
  (mt (ast/parse src) ((ok forms) forms) ((err _) (list)))

fn ! lowerOnce n: Int64 mode: String -> (Result Int64 String)
  (let [(depForms (parsed (depSource n)))
        (mainSrc (mainSource n))
        (mainForms (parsed mainSrc))
        (positions (low/declPositions mainSrc))
        (parsedSize (+ (listLength depForms) (+ (listLength mainForms) (listLength (mapKeys positions)))))]
    (if (= mode "build")
      (ok parsedSize)
      (mt (low/lowerLinked mainForms positions (low/LinkScope :path "q/main.asl" :imports (mapSet (mapEmpty) "dep" depForms) :prelude (list) :strings (list) :only (none)))
        ((ok m) (ok (+ (listLength m.functions) (listLength m.types))))
        ((err ds) (err (str (listLength ds) " diag(s), first " (optionOr (listHead (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " @ " d.locus)) ds)) "")))))))

fn chainFunction n: Int64 -> ty/SsaFunction
  (let [(arm (fn [(label String) (join String)] -> ty/SsaBlock (ty/ssaBlock label (list) (list) (ty/termJump (ty/ssaEdge join (list))))))
        (fork (fn [(i Int64)] -> ty/SsaTerm (ty/termBranch "c" (ty/ssaEdge (str "t" i) (list)) (ty/ssaEdge (str "f" i) (list)))))
        (diamond (fn [(i Int64)] -> (List ty/SsaBlock)
                   (list (arm (str "t" i) (str "j" i)) (arm (str "f" i) (str "j" i))
                         (ty/ssaBlock (str "j" i) (list) (list) (if (= i (- n 1)) (ty/termReturn "x") (fork (+ i 1)))))))]
    (ty/ssaFunction "chain" (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal)
                    (cons (ty/ssaBlock "entry" (list) (list (ty/ssaInstr "c" (ty/tyVal) (ty/opConst (ty/constBool true)))) (if (> n 0) (fork 0) (ty/termReturn "x")))
                          (fold (fn [(acc (List ty/SsaBlock)) (i Int64)] -> (List ty/SsaBlock) (listAppend (diamond i) acc)) (list) (listReverse (range 0 n))))))

fn chainModule n: Int64 -> ty/SsaModule
  (ty/ssaModule "q/chain" (list) (list) (list) (list) (list) (list (chainFunction n)))

fn ! verifyOnce n: Int64 mode: String -> (Result Int64 String)
  (let [(m (chainModule n))
        (blocks (fold (fn [(acc Int64) (f ty/SsaFunction)] -> Int64 (+ acc (listLength f.blocks))) 0 m.functions))]
    (if (= mode "chainBuild")
      (ok blocks)
      (let [(diags (vfy/verifySsaDiags m))]
        (if (listEmpty? diags) (ok blocks) (err (str (listLength diags) " verify diag(s), first " (optionOr (listHead (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " @ " d.locus)) diags)) "")))))))

fn ! runMode mode: String n: Int64 -> (Result Int64 String)
  (if (or (= mode "build") (= mode "lower")) (lowerOnce n mode) (verifyOnce n mode))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listGet args 0) "lower"))
        (n (optionOr (stringToInt64 (optionOr (listGet args 1) "")) -1))]
    (if (or (< n 0) (not (listContains? (list "build" "lower" "chainBuild" "chainVerify") mode)))
      (err "usage: lowerScaleTest build|lower|chainBuild|chainVerify N")
      (mt (runMode mode n)
        ((ok size) (do (println (str "(lowerScale :mode " mode " :n " n " :size " size ")")) (ok 0)))
        ((err e) (err e)))))

fn bytesAllocated text: String -> Int64
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcStats ")) (stringSplit text "\n"))) ""))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens ":bytesAllocated")
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! childBytes mode: String n: Int64 -> Int64
  (let [(built (nt/prepareRun (thisFile) (nt/fingerprint)))]
    (mt built.binary
      ((none) (do (assert false (str "lowerScaleTest builds natively: " built.reason)) -1))
      ((some bin)
       (let [(done (run/runOneLimited (run/job (list bin mode (stringFromInt64 n)) "." (run/childEnv (list "ASL_GC_STATS=1"))) (run/limits 300 4)))]
         (do (assert (and (= done.exit 0) (stringContains? done.out (str "(lowerScale :mode " mode " :n " n " "))) (str mode " " n " child exits 0 (" done.verdict "): " done.out))
             (bytesAllocated done.out))))))

fn ! deltaBytes base: String work: String n: Int64 -> Int64
  (let [(built (childBytes base n)) (done (childBytes work n))]
    (do (println (str "(lowerScale :work " work " :n " n " :baseBytes " built " :workBytes " done " :delta " (- done built) ")"))
        (assert (and (> built 0) (> done built)) (str "both children report bytesAllocated and " work " allocates"))
        (- done built)))

fn ! loweringBytes n: Int64 -> Int64
  (deltaBytes "build" "lower" n)

fn ! lowerModuleDigest n: Int64 -> (Result String String)
  (let [(depForms (parsed (depSource n)))
        (mainSrc (mainSource n))
        (mainForms (parsed mainSrc))
        (positions (low/declPositions mainSrc))]
    (mt (low/lowerLinked mainForms positions (low/LinkScope :path "q/main.asl" :imports (mapSet (mapEmpty) "dep" depForms) :prelude (list) :strings (list) :only (none)))
      ((ok m) (ok (stringFromInt64 (zstdAslXxhHash (stringToBytes (pr/printSsa m))))))
      ((err ds) (err (str (listLength ds) " diag(s), first " (optionOr (listHead (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " @ " d.locus)) ds)) ""))))))

fn ! testShape -> Bool
  (mt (lowerOnce 3 "lower")
    ((err e) (do (assert false (str "the 3-wide synthetic module lowers: " e)) false))
    ((ok size) (do (assert (> size 6) (str "the lowered module has functions and types: " size)) true)))

fn ! testLowerIsLinear -> Bool
  (let [(small (loweringBytes 400))
        (large (loweringBytes 800))
        (digestRes (lowerModuleDigest 2))]
    (do (assert (<= (* large 100) (* small 215))
                (str "lowerLinked of a module with n enums, schemas and functions importing a module of n more allocates linearly: 2n "
                     large " bytes vs n " small ", above 2.15x"))
        (mt digestRes
          ((ok d) (do (assert (= d "-6406126751201197738") (str "lowered module of n=2 digest " d " matches recorded")) true))
          ((err e) (do (assert false (str "lowerModuleDigest 2 failed: " e)) false)))))

fn refSuccessorMap blocks: (List ty/SsaBlock) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (b ty/SsaBlock)] -> (Map String (List String))
          (mapSet acc b.label (listAppend (optionOr (mapGet acc b.label) (list)) (map (fn [(e ty/SsaEdge)] -> String e.target) (ty/termEdges b.term)))))
        (mapEmpty) blocks)

fn refReachable work: (List String) seen: (Map String Bool) succs: (Map String (List String)) -> (Map String Bool)
  (mt (listHead work)
    ((none) seen)
    ((some b) (let [(rest (optionOr (listTail work) (list)))]
                (if (mapHas? seen b)
                  (refReachable rest seen succs)
                  (refReachable (listAppend (optionOr (mapGet succs b) (list)) rest) (mapSet seen b true) succs)))))

fn refPredecessorMap succs: (Map String (List String)) reach: (Map String Bool) -> (Map String (List String))
  (let [(rev (fold (fn [(acc (Map String (List String))) (b String)] -> (Map String (List String))
          (if (mapHas? reach b)
            (fold (fn [(inner (Map String (List String))) (s String)] -> (Map String (List String)) (mapSet inner s (cons b (optionOr (mapGet inner s) (list)))))
                  acc (optionOr (mapGet succs b) (list)))
            acc))
        (mapEmpty) (mapKeys succs)))]
    (fold (fn [(m (Map String (List String))) (k String)] -> (Map String (List String)) (mapSet m k (listReverse (optionOr (mapGet m k) (list))))) rev (mapKeys rev)))

fn refLabelSet labels: (List String) -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (l String)] -> (Map String Bool) (mapSet m l true)) (mapEmpty) labels)

fn refDomRound labels: (List String) entry: String preds: (Map String (List String)) reach: (Map String Bool) doms: (Map String (List String)) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (b String)] -> (Map String (List String))
          (if (or (= b entry) (not (mapHas? reach b)))
            acc
            (let [(sets (map (fn [(p String)] -> (Map String Bool) (refLabelSet (optionOr (mapGet acc p) labels))) (optionOr (mapGet preds b) (list))))
                  (common (filter (fn [(l String)] -> Bool (fold (fn [(inAll Bool) (s (Map String Bool))] -> Bool (and inAll (mapHas? s l))) true sets)) labels))]
              (mapSet acc b (if (listContains? common b) common (listAppend common (list b)))))))
        doms labels)

fn refDomFix labels: (List String) entry: String preds: (Map String (List String)) reach: (Map String Bool) doms: (Map String (List String)) rounds: Int64 -> (Map String (List String))
  (let [(updated (refDomRound labels entry preds reach doms))]
    (if (or (<= rounds 0) (= (mapValues updated) (mapValues doms)))
      updated
      (refDomFix labels entry preds reach updated (- rounds 1))))

fn refDominators labels: (List String) entry: String preds: (Map String (List String)) reach: (Map String Bool) -> (Map String (List String))
  (let [(initial (fold (fn [(acc (Map String (List String))) (l String)] -> (Map String (List String))
                         (if (= l entry) (mapSet acc l (list l)) (mapSet acc l labels)))
                       (mapEmpty) labels))
        (n (listLength labels))]
    (refDomFix labels entry preds reach initial (+ (* n n) 2)))

fn sameSets? a: (List String) b: (List String) -> Bool
  (and (listAll? (fn [(x String)] -> Bool (listContains? b x)) a) (listAll? (fn [(x String)] -> Bool (listContains? a x)) b))

fn referenceSets f: ty/SsaFunction -> (Map String (List String))
  (mt (listHead f.blocks)
    ((none) (mapEmpty))
    ((some e) (let [(labels (map (fn [(b ty/SsaBlock)] -> String b.label) f.blocks))
                    (succs (refSuccessorMap f.blocks))
                    (reach (refReachable (list e.label) (mapEmpty) succs))]
                (refDominators labels e.label (refPredecessorMap succs reach) reach))))

fn mismatches f: ty/SsaFunction -> (List String)
  (let [(got (vfy/dominatorSets f)) (want (referenceSets f))]
    (filter (fn [(l String)] -> Bool (not (sameSets? (optionOr (mapGet got l) (list "?")) (optionOr (mapGet want l) (list "!")))))
            (listAppend (mapKeys want) (mapKeys got))))

fn ! testDominatorsMatchReference -> Bool
  (let [(shapes (list (chainFunction 0) (chainFunction 1) (chainFunction 5)
                      (ty/ssaFunction "loop" (list) (list) (ty/tyVal)
                                      (list (ty/ssaBlock "entry" (list) (list) (ty/termJump (ty/ssaEdge "head" (list))))
                                            (ty/ssaBlock "head" (list) (list) (ty/termBranch "c" (ty/ssaEdge "body" (list)) (ty/ssaEdge "exit" (list))))
                                            (ty/ssaBlock "body" (list) (list) (ty/termBranch "c" (ty/ssaEdge "head" (list)) (ty/ssaEdge "exit" (list))))
                                            (ty/ssaBlock "dead" (list) (list) (ty/termJump (ty/ssaEdge "exit" (list))))
                                            (ty/ssaBlock "exit" (list) (list) (ty/termReturn "c"))))))
        (corpus (mt (lk/linkEntry! "asl/packages/asl-forms/tests/checkSemanticTest.asl") ((ok m) m.functions) ((err _) (list))))
        (all (listAppend shapes corpus))
        (bad (filter (fn [(f ty/SsaFunction)] -> Bool (not (listEmpty? (mismatches f)))) all))
        (loopSets (vfy/dominatorSets (optionOr (listGet shapes 3) (chainFunction 0))))]
    (do (assert (> (listLength corpus) 100) (str "the quadGoldenTest corpus (checkSemanticTest closure) links: " (listLength corpus) " functions"))
        (assert (listEmpty? bad) (str "dominator sets equal the iterative reference on every function of " (listLength all) "; first mismatch "
                                      (optionOr (listHead (map (fn [(f ty/SsaFunction)] -> String (str f.name " " (mismatches f))) bad)) "")))
        (assert (sameSets? (optionOr (mapGet loopSets "exit") (list)) (list "entry" "head" "exit")) (str "a loop exit is dominated by entry and head only: " loopSets))
        (assert (sameSets? (optionOr (mapGet loopSets "dead") (list)) (list "entry" "head" "body" "dead" "exit")) (str "an unreachable block keeps every label: " loopSets))
        true))

fn ! testVerifyIsLinear -> Bool
  (let [(small (deltaBytes "chainBuild" "chainVerify" 500))
        (large (deltaBytes "chainBuild" "chainVerify" 1000))]
    (do (assert (<= (* large 10) (* small 23))
                (str "verifying a function of b blocks allocates linearly: 2b " large " bytes vs b " small ", above 2.3x"))
        true))

fn ! runTests -> Bool
  (do (assert (testShape) "testShape")
      (assert (testLowerIsLinear) "testLowerIsLinear")
      (assert (testDominatorsMatchReference) "testDominatorsMatchReference")
      (assert (testVerifyIsLinear) "testVerifyIsLinear")
      true)
