(module asl-checker/tests/unknownSymbolHintTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/check :a c) (asl-checker/types :a ty)])

fn messagesOf src: String -> String
  (match (a/parseForTypeCheck src)
    ((ok forms) (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) (c/checkModuleSource forms (mapEmpty) "probe.asl" src)) "\n"))
    ((err e) (str "parse " e.msg)))

fn probe body: String -> String
  (str "(module probe :x [f])\n\nfn f x: (Option Int64) r: (Result Int64 String) s: String -> Int64\n" body "\n")

fn ! testBracketArm! -> Bool
  (let [(m (messagesOf (probe "  (match x\n    [(some v) v]\n    ((none) 0))")))]
    (do
      (assert (stringContains? m "ERR_UNKNOWN_SYMBOL unbound symbol: v; hint: a match arm is a list ((some v) body), not a vector [(some v) body]") (str "a bracketed arm names the list arm shape, got " m))
      true))

fn ! testBareArm! -> Bool
  (let [(m (messagesOf (probe "  (match r\n    (ok v)\n    ((err e) 0))")))]
    (do
      (assert (stringContains? m "unbound symbol: v; hint: the arm (ok v) is read as a catch-all binding ok with body v; a match arm wraps its pattern: ((ok v) body)") (str "a bare (ok v) arm names the wrapped pattern, got " m))
      true))

fn ! testWellFormedArmHasNoHint! -> Bool
  (let [(m (messagesOf (probe "  (match x\n    ((some v) w)\n    ((none) 0))")))]
    (do
      (assert (stringContains? m "unbound symbol: w") (str "an unknown name in a well-formed arm is still reported, got " m))
      (refute (stringContains? m "hint:") (str "a well-formed arm gets no arm-shape hint, got " m))
      true))

fn linesOf src: String -> (List String)
  (match (a/parseForTypeCheck src)
    ((ok forms) (map (fn [(d ty/Diagnostic)] -> String (str d.code " " (stringFromInt64 d.line) ":" (stringFromInt64 d.col) " " d.message)) (c/checkModuleSource forms (mapEmpty) "probe.asl" src)))
    ((err e) (list (str "parse " e.msg))))

fn twoFns -> String
  "(module probe :x [f g])\n\nfn f x: (Option Int64) -> Int64\n  (match x\n    [(some v) v]\n    ((none) 0))\n\nfn g y: Int64 -> Int64\n  (+ y v)\n"

fn ! testSameNameKeepsItsFunction! -> Bool
  (let [(ls (linesOf (str "(module probe :x [f g])\n\nfn f a: Int64 -> Int64\n  (+ a zz)\n\nfn g b: Int64 -> Int64\n  (* b zz)\n")))
        (m (stringJoin ls "\n"))]
    (do
      (assert (stringContains? m "ERR_UNKNOWN_SYMBOL 4:8 unbound symbol: zz") (str "f reports its own zz at 4:8, got " m))
      (assert (stringContains? m "ERR_UNKNOWN_SYMBOL 7:8 unbound symbol: zz") (str "g reports its own zz at 7:8, got " m))
      true))

fn ! testArmHintFollowsPosition! -> Bool
  (let [(ls (linesOf (twoFns)))
        (inArm (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "ERR_UNKNOWN_SYMBOL 5:") (stringContains? l "a match arm is a list"))) ls))
        (outside (filter (fn [(l String)] -> Bool (stringStartsWith? l "ERR_UNKNOWN_SYMBOL 9:")) ls))]
    (do
      (assert (>= (listLength inArm) 1) (str "the bracketed arm in f gets its hint on line 5, got " (stringJoin ls "; ")))
      (assert (= (listLength outside) 1) (str "g reports its own v on line 9, got " (stringJoin ls "; ")))
      (refute (listAny? (fn [(l String)] -> Bool (stringContains? l "hint:")) outside) (str "the same name outside the arm gets no arm hint, got " (stringJoin ls "; ")))
      true))

fn ! testStringHelperHint! -> Bool
  (let [(trim (messagesOf (probe "  (length (strTrim s))")))
        (len (messagesOf (probe "  (strLength s)")))
        (far (messagesOf (probe "  (strQuuxFrobnicate s)")))]
    (do
      (assert (stringContains? trim "unbound symbol: strTrim; did you mean trim (prelude builtins)") (str "strTrim suggests trim, got " trim))
      (assert (stringContains? len "unbound symbol: strLength; did you mean length (prelude builtins)") (str "strLength suggests length, got " len))
      (refute (stringContains? far "did you mean") (str "a string helper with no near builtin gets no suggestion, got " far))
      true))

fn ! testRenamedKeepsItsHint! -> Bool
  (let [(m (messagesOf (probe "  (stringLength s)")))]
    (do
      (refute (stringContains? m "did you mean") (str "a retired name keeps only its renamed hint, got " m))
      true))

fn ! testStringBuiltinNamesAreBuiltins! -> Bool
  (do
    (assert (listAll? (fn [(n String)] -> Bool (some? (ty/builtinSig n))) (ty/stringBuiltinNames)) "every stringBuiltinNames row is a checker builtin")
    (assert (listContains? (ty/stringBuiltinNames) "stringJoin") "stringJoin is in the string vocabulary")
    true)

fn mapProbe body: String -> String
  (str "(module probe :x [f])\n\nfn f xs: (List Int64) -> (Map String Int64)\n" body "\n")

fn ! testEmptyMapHint! -> Bool
  (let [(bare (messagesOf (mapProbe "  (map)")))
        (lst (messagesOf (mapProbe "  (list)")))
        (good (messagesOf (mapProbe "  (mapEmpty)")))]
    (do
      (assert (stringContains? bare "ERR_ARITY map takes 2 argument(s), given 0; hint: the empty map is (mapEmpty); map is the list function") (str "(map) with no args hints mapEmpty, got " bare))
      (assert (stringContains? lst "found (List _); hint: the empty map is (mapEmpty); map is the list function") (str "a list where a Map is expected hints mapEmpty, got " lst))
      (refute (stringContains? good "hint:") (str "(mapEmpty) checks clean with no hint, got " good))
      true))

fn pairProbe body: String -> String
  (str "(module probe :x [f])\n\nfn f p: (Pair Int64 String) -> Int64\n" body "\n")

fn ! testPairFieldHint! -> Bool
  (let [(fst (messagesOf (pairProbe "  p.fst")))
        (snd (messagesOf (pairProbe "  (length p.second)")))
        (other (messagesOf (pairProbe "  p.width")))]
    (do
      (assert (stringContains? fst "field fst; hint: read a pair with (pairFirst p) and (pairSecond p)") (str "p.fst hints pairFirst, got " fst))
      (assert (stringContains? snd "field second; hint: read a pair with (pairFirst p) and (pairSecond p)") (str "p.second hints pairSecond, got " snd))
      (refute (stringContains? other "pairFirst") (str "an unrelated missing field gets no pair hint, got " other))
      true))

fn ! runTests -> Bool
  (and (testBracketArm!)
    (and (testBareArm!)
      (and (testWellFormedArmHasNoHint!)
        (and (testStringHelperHint!)
          (and (testRenamedKeepsItsHint!) (and (testStringBuiltinNamesAreBuiltins!) (and (testEmptyMapHint!) (and (testPairFieldHint!) (and (testSameNameKeepsItsFunction!) (testArmHintFollowsPosition!))))))))))
