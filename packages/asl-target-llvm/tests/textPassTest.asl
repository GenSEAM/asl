(module asl-target-llvm/tests/textPassTest
  :x [runTests]
  :i [(asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/rtError :a rterr)
      (asl-target-llvm/sysRoute :a route)
      (asl-target-llvm/rtValue :a valrt)])

; (:m :ref TEXTPASS :do "line-based references of the passes that now cut the module text at their markers instead of at every line; the module is built from every shape the passes read: marker at text start, at end, twice in one run, no trailing newline, no match")
fn refInternalLine wanted: (Map String Bool) line: String -> String
  (if (stringStartsWith? line "define tailcc ")
    (if (mapHas? wanted (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit line "@") 1) "") "(")) ""))
      (stringReplace line "define tailcc " "define internal tailcc ")
      line)
    line)

fn refInternalize names: (List String) text: String -> String
  (let [(wanted (fold (fn [(a (Map String Bool)) (n String)] -> (Map String Bool) (mapSet a (ssa/llvmName n) true)) (mapEmpty) names))]
    (stringJoin (map (fn [(l String)] -> String (refInternalLine wanted l)) (stringSplit text "\n")) "\n"))

fn refPin text: String -> String
  (if (not (stringContains? text "musttail call "))
    text
    (let [(lines (stringSplit text "\n"))
          (targets (fold (fn [(acc (Map String Bool)) (line String)] -> (Map String Bool)
                           (match (listGet (stringSplit line "musttail call ") 1)
                             ((none) acc)
                             ((some rest) (let [(parts (stringSplit rest " @"))]
                                            (match (listGet parts 1)
                                              ((some sym) (if (stringContains? (optionOr (listHead parts) "") "(") acc (mapSet acc (optionOr (listHead (stringSplit sym "(")) "") true)))
                                              ((none) acc))))))
                         (mapEmpty) lines))
          (pinned (fold (fn [(acc (List String)) (line String)] -> (List String)
                          (if (stringStartsWith? line "define internal ")
                            (match (listGet (stringSplit line " @") 1)
                              ((none) acc)
                              ((some rest) (let [(s (optionOr (listHead (stringSplit rest "(")) ""))] (if (mapHas? targets s) (cons (str "ptr @" s) acc) acc))))
                            acc))
                        (list) lines))]
      (if (listEmpty? pinned)
        text
        (str text "\n@llvm.compiler.used = appending global [" (listLength pinned) " x ptr] [" (stringJoin (listReverse pinned) ", ") "], section \"llvm.metadata\"\n")))) 

fn defineLine kind: String name: String i: Int64 -> String
  (str "define " kind "tailcc %Val @" (ssa/llvmName name) "(%Val %a" i ") {")

fn bodyLines i: Int64 callee: String -> String
  (str "entry:\n  %r = musttail call tailcc %Val @" (ssa/llvmName callee) "(%Val %a" i ")\n  ret %Val %r\n}\n  ; define tailcc inside @text\n")

fn fnText kind: String name: String callee: String i: Int64 -> String
  (str (defineLine kind name i) "\n" (bodyLines i callee))

fn names -> (List String)
  (list "f.a" "g-b" "h" "plain" "k$" "m" "n0" "q")

fn sample n: Int64 -> String
  (let [(parts (map (fn [(i Int64)] -> String
                      (let [(nm (optionOr (listGet (names) (mod i (listLength (names)))) "x"))
                            (callee (optionOr (listGet (names) (mod (+ i n) (listLength (names)))) "x"))]
                        (fnText (if (= (mod i 3) 0) "internal " "") nm callee i)))
                    (range 0 n)))]
    (str (if (= (mod n 2) 0) "" "source_filename = \"x\"\n") (stringJoin parts "\n") "declare void @z()"))

fn startsWithDefine -> String
  (str (defineLine "" "f.a" 0) "\nentry:\n  ret %Val undef\n}")

fn cases -> (List String)
  (listAppend (map sample (range 0 14))
              (list "" "define tailcc %Val @h(%Val %a0) {" (startsWithDefine) (str (startsWithDefine) "\n") "no markers at all\n"
                    "\ndefine tailcc %Val @h(%Val %a0)\ndefine tailcc %Val @h(%Val %a0) {\n"
                    "  x = musttail call tailcc %Val @h(%Val %a0)\n"))

fn internalizeOf names: (List String) text: String -> String
  (match (route/internalize (ok text) names)
    ((ok t) t)
    ((err _) "ERR"))

fn testInternalize -> Bool
  (let [(ns (list "f.a" "h" "k$" "q"))]
    (do
      (assert (listAll? (fn [(t String)] -> Bool (= (internalizeOf ns t) (refInternalize ns t))) (cases)) "internalize equals the line-based reference on every sample")
      (assert (listAny? (fn [(t String)] -> Bool (stringContains? (internalizeOf ns t) "define internal tailcc %Val @h(")) (cases)) "some sample really rewrites a wanted define")
      (assert (listAny? (fn [(t String)] -> Bool (and (stringContains? t "define tailcc %Val @plain") (stringContains? (internalizeOf ns t) "define tailcc %Val @plain"))) (cases)) "an unwanted define stays")
      (assert (= (internalizeOf (list) "define tailcc %Val @h(") "define tailcc %Val @h(") "no names leaves the text")
      true))

fn testPin -> Bool
  (do
    (assert (listAll? (fn [(t String)] -> Bool (= (ssa/pinMusttailCallees t) (refPin t))) (cases)) "pinMusttailCallees equals the line-based reference on every sample")
    (assert (listAny? (fn [(t String)] -> Bool (stringContains? (ssa/pinMusttailCallees t) "@llvm.compiler.used")) (cases)) "some sample pins a callee")
    (assert (listAny? (fn [(t String)] -> Bool (and (stringContains? t "musttail call ") (not (stringContains? (ssa/pinMusttailCallees t) "@llvm.compiler.used")))) (cases)) "a sample with musttail but no internal callee is left alone")
    true)

fn keySet keys: (HashMap String Bool) -> (List String)
  (listSort (map pairFirst (hashMapPairs keys)))

fn testKeysMore -> Bool
  (let [(a (list "@x(1) @y,\n@z" "call @w\n@v" "@u"))
        (b (list "\n@p( @q" "@r\n@s"))
        (e "@t(a) @t")
        (whole (rterr/refKeysJoin (hashMapEmpty) (listAppend (listAppend a b) (list e))))
        (grown (rterr/refKeysMore (rterr/refKeysJoin (hashMapEmpty) (listAppend a (list e))) b))]
    (do
      (assert (> (hashMapLength whole) 6) "the chunks carry several keys")
      (assert (= (keySet whole) (keySet grown)) "extending the key map equals scanning all chunks")
      true))

; (:m :ref TEXTPASS :do "headOffsetsText against the per-line headOffsets, usedDeclsKeyed against usedDeclsJoin")
fn offsetsCanon index: (Map String (List Int64)) -> (List String)
  (listSort (map (fn [(p (Pair String (List Int64)))] -> String (str (pairFirst p) "=" (stringJoin (map stringFromInt64 (listSort (pairSecond p))) ","))) (mapPairs index)))

fn headTexts -> (List String)
  (list "" "define void @a(x) {\n}\n@b = global i8 0\ndefine void @a(y) {\n  ret\n}"
        "@b = x\n@c = y\n  @b = not a head\ndefine @c(\n\ndefine @b(\nend\n@b("
        "x\ndefine void @a(x)\n@a\n@a(\ndefine void @a(x)\n"
        "no heads here at all" "\n\n\ndefine @a(\n@a(\n\n")

fn headWanted -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (k String)] -> (Map String Bool) (mapSet m k true)) (mapEmpty) (list "@a(" "@b " "@b(" "@c(" "@c "))

fn testHeadOffsets -> Bool
  (do
    (assert (listAll? (fn [(t String)] -> Bool (= (offsetsCanon (ssa/headOffsetsText t (headWanted))) (offsetsCanon (ssa/headOffsets (stringSplit t "\n") 0 (headWanted) (mapEmpty))))) (headTexts)) "headOffsetsText equals the per-line headOffsets on every text")
    (assert (listAny? (fn [(t String)] -> Bool (> (mapSize (ssa/headOffsetsText t (headWanted))) 1)) (headTexts)) "some text indexes several keys")
    true)

fn testUsedDecls -> Bool
  (let [(decls (list "declare void @fa(i32)" "declare void @fb(i32)" "declare void @fc(i32)"))
        (sets (list (list "x call @fa(1)" "y @fb(" "z @fc(2)") (list "@fa" "@fb(i32) @fc") (list "call @fb(" "none") (list "") (list "@fc(")))]
    (do
      (assert (listAll? (fn [(cs (List String))] -> Bool (= (ssa/usedDeclsKeyed (rterr/refKeysMore (hashMapEmpty) cs) cs decls) (ssa/usedDeclsJoin cs decls))) sets) "usedDeclsKeyed equals usedDeclsJoin")
      (assert (= (listLength (ssa/usedDeclsJoin (optionOr (listGet sets 0) (list)) decls)) 3) "the first set uses all three declarations")
      true))

; (:m :ref HOTSPOT2 :do "the ref-key set against a reference that cuts the text at every @ and ends a key at the first stop byte of the piece; and rtValueDefinedNames against the whole-text search it replaced (rtValueDefines? per present name), on texts with shim headers at the start, after a call, last without a newline, and a header only called")
fn refStopByte? c: String -> Bool
  (listContains? (list "(" ")" "," " " "]" "\n") c)

fn refPieceKey piece: String -> (Option String)
  (let [(stops (filter (fn [(i Int64)] -> Bool (refStopByte? (optionOr (stringSlice piece i (+ i 1)) ""))) (range 0 (stringLength piece))))]
    (match (listHead stops)
      ((some k) (some (str "@" (optionOr (stringSlice piece 0 (+ k 1)) ""))))
      ((none) (none))))

fn refKeysReference text: String -> (List String)
  (listSort (mapKeys (fold (fn [(acc (Map String Bool)) (piece String)] -> (Map String Bool)
                             (match (refPieceKey piece) ((some k) (mapSet acc k true)) ((none) acc)))
                           (mapEmpty) (listDrop (stringSplit text "@") 1))))

fn keyTexts -> (List String)
  (listAppend (cases)
              (list "@a(x) call @b, q@c(z) tail@d" "@@a(@b )@c]@d\n@e@f(" "call @x\n@y(1) @x(2)\n@z" "@" "(@a" "@a(@a(@a("
                    (sample 5) (str (sample 3) "\n@tail")))

fn testRefKeysReference -> Bool
  (do
    (assert (listAll? (fn [(t String)] -> Bool (= (keySet (rterr/refKeys t)) (refKeysReference t))) (keyTexts)) "refKeys equals the cut-at-@ reference on every text")
    (assert (listAny? (fn [(t String)] -> Bool (> (listLength (refKeysReference t)) 3)) (keyTexts)) "some text carries several keys")
    true)

fn shimHeader name: String -> String
  (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) name)) (valrt/shimHeaders))
    ((some p) (pairSecond p))
    ((none) ""))

fn definedTexts -> (List String)
  (let [(h1 (shimHeader "intern")) (h2 (shimHeader "symName")) (h3 (shimHeader "mkCtor")) (body "\n  ret\n}\n")]
    (list (str h1 body) (str "x\n" h1 body "y @mkCtor(\n" h2 body) (str (sample 4) "\n" h3) (str h2 "\n  call @intern(\n") "call @intern( @symName(" ""
          (str (sample 6) "\ndefine internal ptr @symName(i32 %other) {\n}\n") (str h1 "\n" h2 "\n" h3)))

fn definedReference text: String -> (List String)
  (let [(keys (rterr/refKeys text))]
    (filter (fn [(n String)] -> Bool (and (hashMapHas? keys (str "@" n "(")) (valrt/rtValueDefines? text n))) (valrt/valueShimNames)))

fn testDefinedNamesReference -> Bool
  (do
    (assert (listAll? (fn [(t String)] -> Bool (= (valrt/rtValueDefinedNames t (rterr/refKeys t)) (definedReference t))) (definedTexts)) "rtValueDefinedNames equals the whole-text search on every text")
    (assert (listAny? (fn [(t String)] -> Bool (= (listLength (valrt/rtValueDefinedNames t (rterr/refKeys t))) 3)) (definedTexts)) "a text defines three shims")
    (assert (listAny? (fn [(t String)] -> Bool (and (> (listLength (definedReference t)) 0) (< (listLength (definedReference t)) 3))) (definedTexts)) "a text defines some but not all")
    true)

fn runTests -> Bool
  (and (testInternalize) (and (testPin) (and (testKeysMore) (and (testHeadOffsets) (and (testRefKeysReference) (and (testDefinedNamesReference) (testUsedDecls)))))))
