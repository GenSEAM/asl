(module asl-ir/tests/lowerDataTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (asl-ir/lower :a low)])

fn joinLines xs: (List String) -> String
  (stringJoin xs "\n")

fn printed res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res ((ok m) (prn/printSsa m)) ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " " d.locus)) ds) "; "))))

fn verified? res: (Result ty/SsaModule (List ty/IrDiag)) -> Bool
  (mt res ((ok m) (ok? (vfy/verifySsa m))) ((err _) false))

fn diagsOf res: (Result ty/SsaModule (List ty/IrDiag)) -> (List ty/IrDiag)
  (mt res ((ok _) (list)) ((err ds) ds))

fn codes diags: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.code) diags)

fn loci diags: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.locus) diags)

fn messageAt diags: (List ty/IrDiag) i: Int64 -> String
  (optionOr (listGet diags i) (ty/makeIrDiag "" "" "")).message

fn logicSource -> String
  (joinLines (list
    "(module demo/logic :x [both])"
    ""
    "(fn both [(a Bool) (b Bool) (c Bool)] -> Bool"
    "  (and a (or b c)))"))

fn logicGolden -> String
  (joinLines (list
    "(ssa-module \"demo/logic\""
    "  (strings)"
    "  (fn both (captures) (params (a i1) (b i1) (c i1)) (returns i1)"
    "    (block entry ()"
    "      (branch a (rhs0.1) (join0 a)))"
    "    (block rhs0.1 ()"
    "      (branch b (join1 b) (rhs1.1)))"
    "    (block rhs1.1 ()"
    "      (jump (join1 c)))"
    "    (block join1 ((%0 i1))"
    "      (jump (join0 %0)))"
    "    (block join0 ((%1 i1))"
    "      (return %1))))"))

fn shapeSource -> String
  (joinLines (list
    "(module demo/shapes :x [area inner round?])"
    ""
    "(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\") (:c empty [] \"nothing\"))"
    ""
    "(fn area [(s Shape)] -> Int64"
    "  (mt s ((circle r) (* r r)) ((rect w _) w) ((empty) 0)))"
    ""
    "(fn inner [(s Shape)] -> Int64"
    "  (mt s ((circle r) r) (rest (area rest))))"
    ""
    "(fn round? [(s Shape)] -> Bool"
    "  (mt (rect 1 2) ((circle _) true) (_ false)))"))

fn shapeGolden -> String
  (joinLines (list
    "(ssa-module \"demo/shapes\""
    "  (strings)"
    "  (type Shape (circle 1) (rect 2) (empty 0))"
    "  (fn area (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s Shape (circle (arm0.0)) (rect (arm0.1)) (empty (arm0.2))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (let %1 val (entry \"*\" %0 %0))"
    "      (jump (join0 %1)))"
    "    (block arm0.1 ()"
    "      (let %2 val (variant-field s 0))"
    "      (jump (join0 %2)))"
    "    (block arm0.2 ()"
    "      (let %3 i64 (const int 0))"
    "      (let %4 val (box %3))"
    "      (jump (join0 %4)))"
    "    (block join0 ((%5 val))"
    "      (let %6 i64 (unbox %5))"
    "      (return %6)))"
    "  (fn inner (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s Shape (circle (arm0.0)) (default (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (jump (join0 %0)))"
    "    (block arm0.1 ()"
    "      (let %1 i64 (call area s))"
    "      (let %2 val (box %1))"
    "      (jump (join0 %2)))"
    "    (block join0 ((%3 val))"
    "      (let %4 i64 (unbox %3))"
    "      (return %4)))"
    "  (fn round? (captures) (params (s val)) (returns i1)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (const int 2))"
    "      (let %2 val (box %0))"
    "      (let %3 val (box %1))"
    "      (let %4 val (construct Shape rect %2 %3))"
    "      (switch %4 Shape (circle (arm0.0)) (default (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %5 i1 (const bool true))"
    "      (jump (join0 %5)))"
    "    (block arm0.1 ()"
    "      (let %6 i1 (const bool false))"
    "      (jump (join0 %6)))"
    "    (block join0 ((%7 i1))"
    "      (return %7))))"))

fn preludeSource -> String
  (joinLines (list
    "(module demo/prelude :x [orZero wrap nothing])"
    ""
    "(fn orZero [(o (Option Int64))] -> Int64"
    "  (mt o ((some v) v) ((none) 0)))"
    ""
    "(fn wrap [(x Int64)] -> (Result Int64 String)"
    "  (if (< x 0) (err \"neg\") (ok x)))"
    ""
    "(fn nothing [] -> (Option Int64)"
    "  (none))"))

fn preludeGolden -> String
  (joinLines (list
    "(ssa-module \"demo/prelude\""
    "  (strings \"neg\")"
    "  (type Option (some 1) (none 0))"
    "  (type Result (ok 1) (err 1))"
    "  (fn orZero (captures) (params (o val)) (returns i64)"
    "    (block entry ()"
    "      (switch o Option (some (arm0.0)) (none (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field o 0))"
    "      (jump (join0 %0)))"
    "    (block arm0.1 ()"
    "      (let %1 i64 (const int 0))"
    "      (let %2 val (box %1))"
    "      (jump (join0 %2)))"
    "    (block join0 ((%3 val))"
    "      (let %4 i64 (unbox %3))"
    "      (return %4)))"
    "  (fn wrap (captures) (params (x i64)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 0))"
    "      (let %1 i1 (prim ltInt x %0))"
    "      (branch %1 (then0) (else0)))"
    "    (block then0 ()"
    "      (let %2 val (const str 0))"
    "      (let %3 val (construct Result err %2))"
    "      (jump (join0 %3)))"
    "    (block else0 ()"
    "      (let %4 val (box x))"
    "      (let %5 val (construct Result ok %4))"
    "      (jump (join0 %5)))"
    "    (block join0 ((%6 val))"
    "      (return %6)))"
    "  (fn nothing (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 val (construct Option none))"
    "      (return %0))))"))

fn recordSource -> String
  (joinLines (list
    "(module demo/points :x [mk sum items])"
    ""
    "(schema Point (:f x Int64 \"x\") (:f y Int64 \"y\"))"
    ""
    "(fn mk [(a Int64)] -> Point"
    "  (Point :y (+ a 1) :x a))"
    ""
    "(fn sum [(p Point)] -> Int64"
    "  (+ p.x p.y))"
    ""
    "(fn items [(a Int64)] -> (List Int64)"
    "  (list a 2 (list)))"))

fn recordGolden -> String
  (joinLines (list
    "(ssa-module \"demo/points\""
    "  (strings)"
    "  (record Point x y)"
    "  (fn mk (captures) (params (a i64)) (returns rec:Point)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (prim addIntHost a %0))"
    "      (let %2 val (box a))"
    "      (let %3 val (box %1))"
    "      (let %4 val (record Point (x %2) (y %3)))"
    "      (return %4)))"
    "  (fn sum (captures) (params (p rec:Point)) (returns i64)"
    "    (block entry ()"
    "      (let %0 val (field p x))"
    "      (let %1 i64 (unbox %0))"
    "      (let %2 val (field p y))"
    "      (let %3 i64 (unbox %2))"
    "      (let %4 i64 (prim addIntHost %1 %3))"
    "      (return %4)))"
    "  (fn items (captures) (params (a i64)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 2))"
    "      (let %1 val (list))"
    "      (let %2 val (box a))"
    "      (let %3 val (box %0))"
    "      (let %4 val (list %2 %3 %1))"
    "      (return %4))))"))

fn badMatchSource -> String
  (joinLines (list
    "(module demo/badMatch :x [partial])"
    "(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\") (:c empty [] \"nothing\"))"
    "(fn partial [(s Shape)] -> Int64 (mt s ((circle r) r) ((empty) 0)))"
    "(fn unknown [(s Shape)] -> Int64 (mt s ((square r) r) (_ 0)))"
    "(fn short [(s Shape)] -> Int64 (mt s ((rect w) w) (_ 0)))"
    "(fn build [] -> Shape (circle 1 2))"
    "(fn mixed [(s Shape)] -> Int64 (mt s ((circle r) r) ((some v) v) (_ 0)))"
    "(fn twice [(s Shape)] -> Int64 (mt s ((empty) 0) ((empty) 1) (_ 2)))"
    "(fn late [(s Shape)] -> Int64 (mt s (_ 0) ((empty) 1)))"
    "(fn opt [] -> (Option Int64) (none 1))"
    "(fn bare [(s Shape)] -> Int64 (mt s (circle 0) (_ 1)))"))

fn badRecordSource -> String
  (joinLines (list
    "(module demo/badRecord :x [stray])"
    "(schema Point (:f x Int64 \"x\") (:f y Int64 \"y\"))"
    "(fn stray [] -> Point (Point :x 1 :z 2))"
    "(fn half [] -> Point (Point :x 1))"
    "(fn again [] -> Point (Point :x 1 :x 2 :y 3))"
    "(fn loose [] -> Point (Point 1 2))"))

fn testLogic -> Bool
  (let [(res (low/lowerSource (logicSource)))]
    (do (assert (verified? res) "and/or lower and pass verifySsa")
        (assert (= (printed res) (logicGolden)) "and branches on to the next operand or decides false, or decides true or branches on; the last operand jumps to the join")
        true))

fn testMatch -> Bool
  (let [(res (low/lowerSource (shapeSource)))]
    (do (assert (verified? res) "enum constructors and match lower and pass verifySsa")
        (assert (= (printed res) (shapeGolden)) "match switches on the tag, binds payload by variant-field, _ skips a field, a name or _ arm is the default; the enum is a module type")
        true))

fn testPrelude -> Bool
  (let [(res (low/lowerSource (preludeSource)))]
    (do (assert (verified? res) "some, none, ok and err lower and pass verifySsa")
        (assert (= (printed res) (preludeGolden)) "prelude constructors build Option and Result, declared once each in the module")
        true))

fn testRecords -> Bool
  (let [(res (low/lowerSource (recordSource)))]
    (do (assert (verified? res) "records, field access and list literals lower and pass verifySsa")
        (assert (= (printed res) (recordGolden)) "fields evaluate in source order and are stored in declared order; .-field reads one; list builds a list; no prelude type is declared when unused")
        true))

fn testBadMatch -> Bool
  (let [(ds (diagsOf (low/lowerSource (badMatchSource))))]
    (do (assert (= (codes ds) (list "ERR_LOWER_UNKNOWN_CONSTRUCTOR" "ERR_LOWER_ARITY" "ERR_LOWER_ARITY" "ERR_LOWER_PATTERN_TYPE" "ERR_LOWER_DUPLICATE_ARM" "ERR_LOWER_ARITY" "ERR_LOWER_ARITY")) "each malformed match or constructor is its own diagnostic; a non-exhaustive match is not one, nor one whose arms after its catch-all are unreachable")
        (assert (= (loci ds) (list "unknown@4:1" "short@5:1" "build@6:1" "mixed@7:1" "twice@8:1" "opt@10:1" "bare@11:1")) "each diagnostic carries its declaration position")
        (assert (stringContains? (messageAt ds 0) "'square'") "the unknown constructor is named")
        (assert (stringContains? (messageAt ds 1) "binds 1 field(s), the variant has 2") "a short pattern names both arities")
        (assert (stringContains? (messageAt ds 2) "takes 1 field(s), got 2") "an over-applied constructor names both arities")
        (assert (stringStartsWith? (messageAt ds 3) "mt arms mix") (str "diagnostics name the match form as written, mt: " (messageAt ds 3)))
        (assert (stringContains? (messageAt ds 6) "pattern 'circle' of Shape binds 0 field(s), the variant has 1") "a bare constructor pattern for a variant with fields is an arity error")
        true))

fn testBadRecord -> Bool
  (let [(ds (diagsOf (low/lowerSource (badRecordSource))))]
    (do (assert (= (codes ds) (list "ERR_LOWER_UNKNOWN_FIELD" "ERR_LOWER_DUPLICATE_FIELD" "ERR_LOWER_POSITIONAL_RECORD")) "an unknown field and a repeated field are diagnostics; an omitted field with no value supplied is left out, not one; a positional record literal (Point 1 2) is its own diagnostic, not an unknown field '1'")
        (assert (= (loci ds) (list "stray@3:1" "again@5:1" "loose@6:1")) "each diagnostic carries its declaration position; half has none")
        (assert (stringContains? (messageAt ds 0) "no field 'z'") "the unknown field is named")
        (assert (stringContains? (messageAt ds 1) "repeats a field") "the duplicate field diagnostic names the repeat")
        (assert (stringContains? (messageAt ds 2) "positional record literal: write (Point :x 1 :y 2)") "the positional diagnostic shows the keyed literal to write, pairing declared fields with the given values")
        true))

fn testBareKeyRecord -> Bool
  (let [(res (low/lowerSource (joinLines (list "(module demo/bareKey :x [bare])" "(schema Point (:f x Int64 \"x\") (:f y Int64 \"y\"))" "(fn bare [] -> Point (Point x 1 y 2))"))))]
    (do (assert (verified? res) (str "a bare declared field name is a key, not a positional value: " (stringJoin (codes (diagsOf res)) " ")))
        true))

fn runTests -> Bool
  (do (assert (testLogic) "testLogic")
      (assert (testMatch) "testMatch")
      (assert (testPrelude) "testPrelude")
      (assert (testRecords) "testRecords")
      (assert (testBareKeyRecord) "testBareKeyRecord")
      (assert (testBadMatch) "testBadMatch")
      (assert (testBadRecord) "testBadRecord")
      true)
