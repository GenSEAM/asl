(module asl-ir/tests/lowerGapHLGAPSATest
  :x [runTests]
  :i [(asl-ir/link :a lk)])

; (:m :ref HL-GAPS-A :do "regression for two native-lowering gaps: a module fn literally named loop/recur/try/return/quote, and an enum case exported without its enum type name")

fn configText -> String
  "(:aslConfig)\n"

fn quoteFixtureSource -> String
  (stringJoin (list
    "(module gapfx/quoteFixture :x [quote callsQuote] :i [])"
    ""
    "fn quote s: String -> String"
    "  (str \"'\" s \"'\")"
    ""
    "fn callsQuote s: String -> String"
    "  (quote s)") "\n")

fn bareLoopFixtureSource -> String
  (stringJoin (list
    "(module gapfx/bareLoopFixture :x [callsUnboundLoop] :i [])"
    ""
    "fn callsUnboundLoop -> Int64"
    "  (loop 1 2)") "\n")

fn enumProducerSource -> String
  (stringJoin (list
    "(module gapfx/enumProducer :x [windowOf] :i [])"
    ""
    "enum Window"
    "  (windowOf text: String)"
    "  (hiddenOf text: String)") "\n")

fn enumConsumerSource -> String
  (stringJoin (list
    "(module gapfx/enumConsumer :x [makeWindow] :i [(gapfx/enumProducer :a p)])"
    ""
    "fn makeWindow t: String -> p/Window"
    "  (p/windowOf t)") "\n")

fn enumHiddenConsumerSource -> String
  (stringJoin (list
    "(module gapfx/enumHiddenConsumer :x [makeHidden] :i [(gapfx/enumProducer :a p)])"
    ""
    "fn makeHidden t: String -> p/Window"
    "  (p/hiddenOf t)") "\n")

fn ! writeOne! base: String name: String src: String -> Bool
  (ok? (fileWrite (str base "/" name ".asl") src))

fn ! writeFixtures! base: String -> Bool
  (and (ok? (dirCreate (str base "/gapfx")))
       (and (ok? (fileWrite (str base "/.asl.config.asn") (configText)))
       (and (writeOne! base "gapfx/quoteFixture" (quoteFixtureSource))
            (and (writeOne! base "gapfx/bareLoopFixture" (bareLoopFixtureSource))
                 (and (writeOne! base "gapfx/enumProducer" (enumProducerSource))
                      (and (writeOne! base "gapfx/enumConsumer" (enumConsumerSource))
                           (writeOne! base "gapfx/enumHiddenConsumer" (enumHiddenConsumerSource))))))))

fn diagCodes res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.code) ds)))

fn diagMessages res: (Result ty/SsaModule (List ty/IrDiag)) -> (List String)
  (mt res ((ok _) (list)) ((err ds) (map (fn [(d ty/IrDiag)] -> String d.message) ds)))

fn ! testQuoteNamedFunctionLowers base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfx/quoteFixture.asl")))]
    (do
      (assert (ok? res) (str "a module-level function literally named 'quote' lowers and links: " (diagMessages res)))
      true))

fn ! testBareUnboundLoopStillRejected base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfx/bareLoopFixture.asl")))]
    (do
      (assert (not (ok? res)) "an unbound call to the reserved name 'loop' is still outside the lowered subset")
      (assert (= (diagCodes res) (list "ERR_LOWER_UNSUPPORTED")) (str "the rejection is the reserved-form diagnostic, got " (diagCodes res)))
      true))

fn ! testEnumCaseExportWithoutTypeName base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfx/enumConsumer.asl")))]
    (do
      (assert (ok? res) (str "a constructor individually named in :x lowers even when its enum type name is not: " (diagMessages res)))
      true))

fn ! testEnumCaseStillHiddenWhenNotExported base: String -> Bool
  (let [(res (lk/linkEntry! (str base "/gapfx/enumHiddenConsumer.asl")))]
    (do
      (assert (not (ok? res)) "a constructor named in neither :x nor its enum type stays hidden")
      (assert (= (diagCodes res) (list "ERR_LOWER_UNEXPORTED")) (str "the rejection is the unexported-name diagnostic, got " (diagCodes res)))
      true))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/lowerGapHLGAPSATest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate base))
        (wrote (writeFixtures! base))
        (r1 (testQuoteNamedFunctionLowers base))
        (r2 (testBareUnboundLoopStillRejected base))
        (r3 (testEnumCaseExportWithoutTypeName base))
        (r4 (testEnumCaseStillHiddenWhenNotExported base))
        (removed (pathRemove base))]
    (do
      (assert (ok? made) "the fixture directory is created")
      (assert wrote "the fixture modules are written")
      (assert (ok? removed) "the fixture directory is removed")
      (and r1 (and r2 (and r3 r4)))))
