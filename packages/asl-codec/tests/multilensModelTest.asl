(module asl-codec/multilensModelTest
  :d "Unit verification test suite for unified MultilensModel schema and extraction primitives"
  :x [testParseFullModel
      testOmittedOptionalSections
      testNegativeAndRefutations
      testDefaultLensOptionsAndEmptyModel
      runTests]
  :i [(asl-codec/multilens :a ml)
      (asl-parser/reader :a rd)])

(df testParseFullModel [] -> Bool
  :d "Verifies parsing a complete unified MultilensModel S-expression with all sections."
  (let [(payload "(:doc :meta (:title \"Dashboard\" :version \"1.0.0\") :styles (:vars ((--bg \"#fff\"))) :content (div (:class \"app\") (h1 \"Hello\")) :data (:users [(:id 1)]) :config (:port 8080))")
        (model (ml/parseUnifiedModel payload))]
    (assert (.-success model) "parse full model succeeds")
    (assert (= (.-errorMsg model) "") "no error message on full model")
    (assert (rd/isList? (ml/modelExtractMeta model)) "meta is a list")
    (assert (rd/isList? (ml/modelExtractStyles model)) "styles is a list")
    (assert (rd/isList? (ml/modelExtractContent model)) "content is a list")
    (assert (rd/isList? (ml/modelExtractData model)) "data is a list")
    (assert (rd/isList? (ml/modelExtractConfig model)) "config is a list")
    true))

(df testOmittedOptionalSections [] -> Bool
  :d "Verifies that omitted optional sections default to empty list SExpr."
  (let [(payload "(:doc :meta (:title \"Minimal\"))")
        (model (ml/parseUnifiedModel payload))]
    (assert (.-success model) "minimal model succeeds")
    (assert (rd/isList? (ml/modelExtractMeta model)) "meta is extracted")
    (assert (rd/isList? (ml/modelExtractStyles model)) "styles defaults to empty list")
    (assert (rd/isList? (ml/modelExtractContent model)) "content defaults to empty list")
    (assert (rd/isList? (ml/modelExtractData model)) "data defaults to empty list")
    (assert (rd/isList? (ml/modelExtractConfig model)) "config defaults to empty list")
    true))

(df testNegativeAndRefutations [] -> Bool
  :d "Dual-polarity refutations verifying rejection of malformed or invalid inputs."
  (let [(rEmpty (ml/parseUnifiedModel ""))
        (rAtom (ml/parseUnifiedModel "not-a-list"))
        (rBadRoot (ml/parseUnifiedModel "(:notdoc :meta ())"))
        (vEmpty (ml/validateMultilensModel ""))
        (vBad (ml/validateMultilensModel "invalid"))
        (vBadRoot (ml/validateMultilensModel "(:notdoc :meta ())"))
        (vGood (ml/validateMultilensModel "(:doc :meta ())"))]
    (refute (.-success rEmpty) "empty input rejected")
    (refute (.-success rAtom) "atom input rejected")
    (refute (.-success rBadRoot) "non-doc root rejected")
    (refute vEmpty "validate rejects empty string")
    (refute vBad "validate rejects invalid syntax")
    (refute vBadRoot "validate rejects non-doc root")
    (assert vGood "validate accepts valid doc form")
    true))

(df testDefaultLensOptionsAndEmptyModel [] -> Bool
  :d "Verifies default lens options and empty model constructors."
  (let [(opts (ml/defaultLensOptions))
        (m (ml/emptyModel))]
    (assert (= (.-indent opts) 2) "default indent is 2")
    (assert (not (.-minify opts)) "default minify is false")
    (assert (.-standalone opts) "default standalone is true")
    (assert (.-includeStyles opts) "default includeStyles is true")
    (assert (.-doctype opts) "default doctype is true")
    (assert (.-success m) "empty model is marked success")
    (assert (rd/isList? (.-meta m)) "empty model meta is list")
    (assert (rd/isList? (.-styles m)) "empty model styles is list")
    (assert (rd/isList? (.-content m)) "empty model content is list")
    (assert (rd/isList? (.-data m)) "empty model data is list")
    (assert (rd/isList? (.-config m)) "empty model config is list")
    true))

(df runTests [] -> Bool
  :d "Runs all MultilensModel schema unit tests."
  (do
    (assert (testParseFullModel) "testParseFullModel")
    (assert (testOmittedOptionalSections) "testOmittedOptionalSections")
    (assert (testNegativeAndRefutations) "testNegativeAndRefutations")
    (assert (testDefaultLensOptionsAndEmptyModel) "testDefaultLensOptionsAndEmptyModel")
    true))
