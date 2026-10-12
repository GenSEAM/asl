(module asl-ir/tests/lowerGapHLGAPSBTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty)])

; (:m :ref HL-GAPS-B :do "regression for two native-lowering gaps: a let bound with a parenthesized binding list ((a v) (b w)) is still outside the lowered subset, fixed upstream by migrating source to [(a v) (b w)] in asl-gateway browser/media/server.asl and harness multiLensPipeline/stepsPipeline.asl; and an enum case whose sole field is positional (bare type, no name, e.g. (early s/RunResult)) was undercounted to arity 0 by caseArity filtering out empty-named fields, rejecting every correct-arity construct/match of such a case (asl/agentLoop/runLoop.LoopSetup.early)")

fn configText -> String
  "(:aslConfig)\n"

fn parenLetFixtureSource -> String
  (stringJoin (list
    "(module gapfxb/parenLet :x [addPair] :i [])"
    ""
    "fn addPair a: Int64 b: Int64 -> Int64"
    "  (let ((x a) (y b)) (+ x y))") "\n")

fn bracketLetFixtureSource -> String
  (stringJoin (list
    "(module gapfxb/bracketLet :x [addPair] :i [])"
    ""
    "fn addPair a: Int64 b: Int64 -> Int64"
    "  (let [(x a) (y b)] (+ x y))") "\n")

fn positionalEnumFixtureSource -> String
  (stringJoin (list
    "(module gapfxb/positionalEnum :x [makeEarly makeReady unwrap] :i [])"
    ""
    "schema Payload"
    "  (:f code Int64)"
    ""
    "enum Setup"
    "  (ready Payload)"
    "  (early Payload)"
    ""
    "fn makeEarly p: Payload -> Setup"
    "  (early p)"
    ""
    "fn makeReady p: Payload -> Setup"
    "  (ready p)"
    ""
    "fn unwrap s: Setup -> Int64"
    "  (mt s"
    "    ((ready p) p.code)"
    "    ((early p) p.code))") "\n")

fn positionalEnumWrongArityFixtureSource -> String
  (stringJoin (list
    "(module gapfxb/positionalEnumBad :x [bad] :i []) "
    ""
    "schema Payload"
    "  (:f code Int64)"
    ""
    "enum Setup"
    "  (ready Payload)"
    "  (early Payload)"
    ""
    "fn bad p: Payload q: Payload -> Setup"
    "  (early p q)") "\n")

fn ! writeOne! base: String name: String src: String -> Bool
  (ok? (fileWrite (str base "/" name ".asl") src))

fn ! writeFixtures! base: String -> Bool
  (and (ok? (dirCreate (str base "/gapfxb")))
       (and (ok? (fileWrite (str base "/.asl.config.asn") (configText)))
       (and (writeOne! base "gapfxb/parenLet" (parenLetFixtureSource))
            (and (writeOne! base "gapfxb/bracketLet" (bracketLetFixtureSource))
                 (and (writeOne! base "gapfxb/positionalEnum" (positionalEnumFixtureSource))
                      (writeOne! base "gapfxb/positionalEnumBad" (positionalEnumWrongArityFixtureSource)))))))

fn diagCodes res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn diagMessages res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.message) ds)))

fn ! testParenLetStillRejected base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxb/parenLet.asl")))]
    (do
      (assert (not (ok? res)) "a let with a parenthesized binding list ((a v) (b w)) is still outside the lowered subset")
      (assert (= (diagCodes res) (list "ERR_LOWER_UNSUPPORTED")) (str "the rejection is the unsupported-form diagnostic, got " (diagCodes res)))
      true))

fn ! testBracketLetLowers base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxb/bracketLet.asl")))]
    (do
      (assert (ok? res) (str "the same bindings in a [(a v) (b w)] binding vector lower cleanly: " (diagMessages res)))
      true))

fn ! testPositionalEnumFieldLowers base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxb/positionalEnum.asl")))]
    (do
      (assert (ok? res) (str "constructing and matching an enum case whose sole field is positional (no field name) lowers: " (diagMessages res)))
      true))

fn ! testPositionalEnumWrongArityStillRejected base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfxb/positionalEnumBad.asl")))]
    (do
      (assert (not (ok? res)) "a positional-field case constructed with the wrong number of arguments is still outside the lowered subset")
      (assert (= (diagCodes res) (list "ERR_LOWER_ARITY")) (str "the rejection is the arity diagnostic, got " (diagCodes res)))
      true))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/lowerGapHLGAPSBTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate base))
        (wrote (writeFixtures! base))
        (r1 (testParenLetStillRejected base))
        (r2 (testBracketLetLowers base))
        (r3 (testPositionalEnumFieldLowers base))
        (r4 (testPositionalEnumWrongArityStillRejected base))
        (removed (pathRemove base))]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert wrote "the fixture modules are written")
      (assert (ok? removed) "the fixture directory is removed")
      (and r1 (and r2 (and r3 r4)))))
