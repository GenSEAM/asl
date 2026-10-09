(module asl-ir/tests/lowerParityTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (asl-ir/link :a lk)])

fn joinLines xs: (List String) -> String
  (stringJoin xs "\n")

fn printed res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res ((ok m) (prn/printSsa m)) ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " " d.locus)) ds) "; "))))

fn verified? res: (Result ty/SsaModule (List ty/IrDiag)) -> Bool
  (mt res ((ok m) (ok? (vfy/verifySsa m))) ((err _) false))

fn valuesSource -> String
  (joinLines (list
    "(module demo/values :x [lens])"
    "(fn lens [(xs (List String))] -> (List Int64) (map stringLength xs))"
    "(fn wrap [(xs (List Int64))] -> (List (Option Int64)) (map some xs))"
    "(fn nothing [] -> (Option Int64) none)"
    "(fn has [(s String)] -> Bool (and (stringContains? s \"x\") (listEmpty? (cons 1 (list)))))"
    "(fn adder [(n Int64)] -> Int64 (fn [(a Int64) (b Int64)] -> Int64 (+ a b n)))"
    "(fn apply [] -> Int64 ((adder 1) 2 3))"
    "(fn vec [] -> (List Int64) [1 (* 2 3 4)])"
    "(fn neg [(a Int64)] -> Int64 (- a))"
    "(fn flat [(a Int64)] -> Int64 (let [b (+ a 1) c (* b 2)] (- c b)))"))

fn patternSource -> String
  (joinLines (list
    "(module demo/patterns :x [radius])"
    "(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\") (:c empty [] \"nothing\"))"
    "(fn radius [(s Shape)] -> Int64 (mt s ((circle r) r) (else 0)))"
    "(fn blank? [(s Shape)] -> Bool (mt s (empty true) (else false)))"
    "(fn width [(s Shape)] -> Int64 (mt s ((rect w _) w)))"
    "(fn fail [(m String)] -> Int64 (mt m))"))

fn escapeSource -> String
  (joinLines (list
    "(module demo/escapes :x [text])"
    "(fn text [] -> String \"a\\x41\\u00e9{b\\x00\\x1b\\n\\\"q\")"))

fn indentSource -> String
  (joinLines (list
    "(module demo/indent :x [area])"
    ""
    "(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\"))"
    ""
    "fn area s: Shape -> Int64"
    "  (mt s ((circle r) (* r r)) ((rect w h) (* w h)))"))

fn valuesGolden -> String
  (joinLines (list
    "(ssa-module \"demo/values\""
    "  (strings \"x\")"
    "  (type Option (some 1) (none 0))"
    "  (fn lens (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure lens@lambda0))"
    "      (let %1 val (call prelude.map %0 xs))"
    "      (return %1)))"
    "  (fn lens@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (entry \"stringLength\" @0))"
    "      (let %1 val (box %0))"
    "      (return %1)))"
    "  (fn wrap (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure wrap@lambda0))"
    "      (let %1 val (call prelude.map %0 xs))"
    "      (return %1)))"
    "  (fn wrap@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (construct Option some @0))"
    "      (return %0)))"
    "  (fn nothing (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 val (construct Option none))"
    "      (return %0)))"
    "  (fn has (captures) (params (s val)) (returns i1)"
    "    (block entry ()"
    "      (let %0 val (const str 0))"
    "      (let %1 i1 (entry \"stringContains?\" s %0))"
    "      (branch %1 (rhs0.1) (join0 %1)))"
    "    (block rhs0.1 ()"
    "      (let %2 i64 (const int 1))"
    "      (let %3 val (list))"
    "      (let %4 val (box %2))"
    "      (let %5 val (entry \"cons\" %4 %3))"
    "      (let %6 i1 (entry \"listEmpty?\" %5))"
    "      (jump (join0 %6)))"
    "    (block join0 ((%7 i1))"
    "      (return %7)))"
    "  (fn adder (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 val (box n))"
    "      (let %1 val (make-closure adder@lambda0 %0))"
    "      (let %2 i64 (unbox %1))"
    "      (return %2)))"
    "  (fn adder@lambda0 (captures (n val)) (params (a val) (b val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox n))"
    "      (let %1 i64 (unbox a))"
    "      (let %2 i64 (unbox b))"
    "      (let %3 i64 (prim addIntHost %1 %2))"
    "      (let %4 i64 (prim addIntHost %3 %0))"
    "      (let %5 val (box %4))"
    "      (return %5)))"
    "  (fn apply (captures) (params) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (call adder %0))"
    "      (let %2 i64 (const int 2))"
    "      (let %3 i64 (const int 3))"
    "      (let %4 val (box %1))"
    "      (let %5 val (box %2))"
    "      (let %6 val (box %3))"
    "      (let %7 val (call-closure %4 %5 %6))"
    "      (let %8 i64 (unbox %7))"
    "      (return %8)))"
    "  (fn vec (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (const int 2))"
    "      (let %2 i64 (const int 3))"
    "      (let %3 i64 (prim mulIntHost %1 %2))"
    "      (let %4 i64 (const int 4))"
    "      (let %5 i64 (prim mulIntHost %3 %4))"
    "      (let %6 val (box %0))"
    "      (let %7 val (box %5))"
    "      (let %8 val (list %6 %7))"
    "      (return %8)))"
    "  (fn neg (captures) (params (a i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (prim negIntHost a))"
    "      (return %0)))"
    "  (fn flat (captures) (params (a i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (prim addIntHost a %0))"
    "      (let %2 i64 (const int 2))"
    "      (let %3 i64 (prim mulIntHost %1 %2))"
    "      (let %4 i64 (prim subIntHost %3 %1))"
    "      (return %4)))"
    "  (fn prelude.map (captures) (params (f val) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeMapOnto f xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeMapOnto (captures) (params (f val) (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (call-closure f %1))"
    "      (let %5 val (entry \"cons\" %4 acc))"
    "      (let %6 val (call prelude.preludeMapOnto f %3 %5))"
    "      (jump (join1 %6)))"
    "    (block join1 ((%7 val))"
    "      (jump (join0 %7)))"
    "    (block arm0.1 ()"
    "      (let %8 val (call prelude.listReverse acc))"
    "      (jump (join0 %8)))"
    "    (block join0 ((%9 val))"
    "      (return %9)))"
    "  (fn prelude.listReverse (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeReverseOnto xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeReverseOnto (captures) (params (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (entry \"cons\" %1 acc))"
    "      (let %5 val (call prelude.preludeReverseOnto %3 %4))"
    "      (jump (join1 %5)))"
    "    (block join1 ((%6 val))"
    "      (jump (join0 %6)))"
    "    (block arm0.1 ()"
    "      (jump (join0 acc)))"
    "    (block join0 ((%7 val))"
    "      (return %7))))"))

fn patternGolden -> String
  (joinLines (list
    "(ssa-module \"demo/patterns\""
    "  (strings)"
    "  (type Shape (circle 1) (rect 2) (empty 0))"
    "  (fn radius (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s Shape (circle (arm0.0)) (default (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (jump (join0 %0)))"
    "    (block arm0.1 ()"
    "      (let %1 i64 (const int 0))"
    "      (let %2 val (box %1))"
    "      (jump (join0 %2)))"
    "    (block join0 ((%3 val))"
    "      (let %4 i64 (unbox %3))"
    "      (return %4)))"
    "  (fn blank? (captures) (params (s val)) (returns i1)"
    "    (block entry ()"
    "      (switch s Shape (empty (arm0.0)) (default (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 i1 (const bool true))"
    "      (jump (join0 %0)))"
    "    (block arm0.1 ()"
    "      (let %1 i1 (const bool false))"
    "      (jump (join0 %1)))"
    "    (block join0 ((%2 i1))"
    "      (return %2)))"
    "  (fn width (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s Shape (rect (arm0.0)) (default (nomatch0))))"
    "    (block nomatch0 ()"
    "      (unreachable))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (jump (join0 %0)))"
    "    (block join0 ((%1 val))"
    "      (let %2 i64 (unbox %1))"
    "      (return %2)))"
    "  (fn fail (captures) (params (m val)) (returns i64)"
    "    (block entry ()"
    "      (unreachable))"
    "    (block dead0 ()"
    "      (let %0 val (const unit))"
    "      (let %1 i64 (unbox %0))"
    "      (return %1))))"))

fn indentGolden -> String
  (joinLines (list
    "(ssa-module \"demo/indent\""
    "  (strings)"
    "  (type Shape (circle 1) (rect 2))"
    "  (fn area (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s Shape (circle (arm0.0)) (rect (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (let %1 val (entry \"*\" %0 %0))"
    "      (jump (join0 %1)))"
    "    (block arm0.1 ()"
    "      (let %2 val (variant-field s 0))"
    "      (let %3 val (variant-field s 1))"
    "      (let %4 val (entry \"*\" %2 %3))"
    "      (jump (join0 %4)))"
    "    (block join0 ((%5 val))"
    "      (let %6 i64 (unbox %5))"
    "      (return %6))))"))

fn poolOf res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok m) m.strings) ((err _) (list)))

fn arityOf res: (Result ty/SsaModule (List ty/IrDiag)) -> (List Int64)
  (mt res
    ((ok m) (fold (fn [(acc (List Int64)) (d ty/SsaTypeDecl)] -> (List Int64) (listAppend acc (map (fn [(v ty/SsaVariant)] -> Int64 v.arity) d.variants))) (list) m.types))
    ((err _) (list)))

fn ! testValues -> Bool
  (let [(res (lk/lowerSourceLinked! (valuesSource)))]
    (do (assert (verified? res) "builtins and constructors as values, computed heads, vectors, variadic +/*, unary minus and flat let lower and pass verifySsa")
        (assert (= (printed res) (valuesGolden)) "a builtin or constructor value is a lifted wrapper, none is a construct, a computed head is call-closure, [..] is a list, (+ a b n) folds left, (- a) of an Int64 is the negIntHost primitive, flat let pairs bind in order")
        true))

fn ! testPatterns -> Bool
  (let [(res (lk/lowerSourceLinked! (patternSource)))]
    (do (assert (verified? res) "else arms, bare constructor patterns and trapping matches pass verifySsa")
        (assert (= (printed res) (patternGolden)) ":else and else are the default arm, a bare constructor tests the tag, a non-exhaustive match defaults to an unreachable block, an armless match is unreachable")
        true))

fn ! testEscapes -> Bool
  (let [(res (lk/lowerSourceLinked! (escapeSource)))]
    (do (assert (verified? res) "a string with host escapes lowers and passes verifySsa")
        (assert (= (poolOf res) (list "a\x41é{b\x00\x1b\n\"q")) "the pooled string equals what the host reader makes of the same literal")
        true))

fn literalSource body: String -> String
  (joinLines (list "(module demo/lit :x [text])" (str "(fn text [] -> String \"" body "\")")))

fn elseKeywordSource -> String
  (joinLines (list
    "(module demo/elseKeyword :x [pick])"
    "(enum Shape (:c circle [(r Int64)] \"round\") (:c square [(q Int64)] \"flat\"))"
    "(fn pick [(s Shape)] -> Int64 (mt s ((circle r) r) (:else 0)))"))

fn diagCodes res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn ! testStrictEscapes -> Bool
  (do (assert (= (poolOf (lk/lowerSourceLinked! (literalSource "\\u{62}\\u{1F600}\\u{10FFFF}\\u00e9\\xff"))) (list "\u{62}\u{1F600}\u{10FFFF}\u00e9\xff")) "braced, 4-digit and byte escapes pool the bytes the host reader makes")
      (map (fn [(body String)] -> Bool
             (do (assert (= (diagCodes (lk/lowerSourceLinked! (literalSource body))) (list "ERR_BAD_ESCAPE")) (str body " is ERR_BAD_ESCAPE, got " (printed (lk/lowerSourceLinked! (literalSource body)))))
                 true))
           (list "\\u{1g}" "\\u{110000}" "\\u{}" "\\u{D800}" "\\u{1234567}" "\\xZZ" "\\x-1" "\\a" "\\q" "\\0" "\\e" "\\{" "\\u +1a" "\\uD800"))
      true)

fn ! testElseKeywordRejected -> Bool
  (let [(res (lk/lowerSourceLinked! (elseKeywordSource)))]
    (do (assert (= (diagCodes res) (list "ERR_LOWER_UNSUPPORTED")) (str "ASL1-elseKeywordPatternParity: (:else ...) is a keyword literal, not the catch-all arm, so lowering it is unsupported rather than silently treated as wild, got " (printed res)))
        true))

fn ! testIndentEnum -> Bool
  (let [(res (lk/lowerSourceLinked! (indentSource)))]
    (do (assert (verified? res) "an enum in a module with indent-dialect functions lowers and passes verifySsa")
        (assert (= (arityOf res) (list 1 2)) "variant arities count declared fields, not the (list ...) head of the rendered field vector")
        (assert (= (printed res) (indentGolden)) "patterns bind every declared field")
        true))

fn ! runTests -> Bool
  (do (assert (testValues) "testValues")
      (assert (testPatterns) "testPatterns")
      (assert (testEscapes) "testEscapes")
      (assert (testStrictEscapes) "testStrictEscapes")
      (assert (testElseKeywordRejected) "testElseKeywordRejected")
      (assert (testIndentEnum) "testIndentEnum")
      true)
