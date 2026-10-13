(module asl-ir/tests/lowerGapHLGAPSCTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty)])

; (:m :ref HL-GAPS-C :do "regression for the literal-pattern native-lowering gap: a bare Int64 or String literal match arm (mt x (1 \"one\") (2 \"two\") (_ \"other\")) fell through every classifyArm branch (not wild, not a 0-arity ctor, excluded from bindName? by design, not a list) and was rejected ERR_LOWER_UNSUPPORTED; fixed by giving classifyArm a 'lit' arm kind and lowerMatch a termBranch chain (upToLitCatchAll + lowerLitArms) that compares the scrutinee to each literal by the generic '=' entry in source order, ending at a trailing wild/var catch-all or a prebuilt unreachable trap when none is present")

fn configText -> String
  "(:aslConfig)\n"

fn literalIntFixtureSource -> String
  (stringJoin (list
    "(module gapfxc/literalInt :x [describe] :i [])"
    ""
    "fn describe n: Int64 -> String"
    "  (mt n"
    "    (1 \"one\")"
    "    (2 \"two\")"
    "    (_ \"other\"))") "\n")

fn literalStringFixtureSource -> String
  (stringJoin (list
    "(module gapfxc/literalString :x [score] :i [])"
    ""
    "fn score s: String -> Int64"
    "  (mt s"
    "    (\"alpha\" 1)"
    "    (\"beta\" 2)"
    "    (_ 0))") "\n")

fn literalNoCatchAllFixtureSource -> String
  (stringJoin (list
    "(module gapfxc/literalNoCatchAll :x [pick] :i [])"
    ""
    "fn pick n: Int64 -> String"
    "  (mt n"
    "    (1 \"one\")"
    "    (2 \"two\"))") "\n")

fn literalMixedCtorFixtureSource -> String
  (stringJoin (list
    "(module gapfxc/literalMixedCtor :x [bad] :i [])"
    ""
    "fn bad v: (Option Int64) -> String"
    "  (mt v"
    "    ((some x) \"some\")"
    "    (1 \"one\"))") "\n")

fn ! writeOne! base: String name: String src: String -> Bool
  (ok? (fileWrite (str base "/" name ".asl") src))

fn ! writeFixtures! base: String -> Bool
  (and (ok? (dirCreate (str base "/gapfxc")))
       (and (ok? (fileWrite (str base "/.asl.config.asn") (configText)))
       (and (writeOne! base "gapfxc/literalInt" (literalIntFixtureSource))
            (and (writeOne! base "gapfxc/literalString" (literalStringFixtureSource))
                 (and (writeOne! base "gapfxc/literalNoCatchAll" (literalNoCatchAllFixtureSource))
                      (writeOne! base "gapfxc/literalMixedCtor" (literalMixedCtorFixtureSource)))))))

fn diagCodes res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn diagMessages res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.message) ds)))

fn ! testLiteralIntArmsLower base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxc/literalInt.asl")))]
    (do
      (assert (ok? res) (str "a match with bare Int64 literal arms and a wildcard lowers: " (diagMessages res)))
      true))

fn ! testLiteralStringArmsLower base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxc/literalString.asl")))]
    (do
      (assert (ok? res) (str "a match with bare String literal arms and a wildcard lowers: " (diagMessages res)))
      true))

fn ! testLiteralArmsWithoutCatchAllStillLower base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxc/literalNoCatchAll.asl")))]
    (do
      (assert (ok? res) (str "a match with only literal arms and no wildcard still lowers, trapping on an unmatched value at runtime rather than rejecting the lower: " (diagMessages res)))
      true))

fn ! testLiteralArmMixedWithConstructorArmRejected base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxc/literalMixedCtor.asl")))]
    (do
      (assert (not (ok? res)) "mixing a constructor pattern with a literal pattern in the same match is still outside the lowered subset")
      (assert (= (diagCodes res) (list "ERR_LOWER_UNSUPPORTED")) (str "the rejection is the unsupported-construct diagnostic, got " (diagCodes res)))
      true))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/lowerGapHLGAPSCTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate base))
        (wrote (writeFixtures! base))
        (r1 (testLiteralIntArmsLower base))
        (r2 (testLiteralStringArmsLower base))
        (r3 (testLiteralArmsWithoutCatchAllStillLower base))
        (r4 (testLiteralArmMixedWithConstructorArmRejected base))
        (removed (pathRemove base))]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert wrote "the fixture modules are written")
      (assert (ok? removed) "the fixture directory is removed")
      (and r1 (and r2 (and r3 r4)))))
