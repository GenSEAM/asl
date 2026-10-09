(module aslGateway/tests/configTest
  :x [runTests]
  :i [(config :a cfg)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)])

fn getPropStr props: (Map String rd/SExpr) key: String fallback: String -> String
  (mt (mapGet props key)
    ((none) fallback)
    ((some expr)
      (mt (cfg/asn_scalar expr)
        ((cfg/scalarStr s) s)
        (_ fallback))))

fn getPropBool props: (Map String rd/SExpr) key: String fallback: Bool -> Bool
  (mt (mapGet props key)
    ((none) fallback)
    ((some expr)
      (mt (cfg/asn_scalar expr)
        ((cfg/scalarBool b) b)
        (_ fallback))))

fn getPropInt props: (Map String rd/SExpr) key: String fallback: Int64 -> Int64
  (mt (mapGet props key)
    ((none) fallback)
    ((some expr)
      (mt (cfg/asn_scalar expr)
        ((cfg/scalarInt n) n)
        (_ fallback))))

fn testOneVariant! vForm: rd/SExpr -> Bool
  (mt (cfg/asn_props vForm (some ":variant"))
    ((err e) (do (assert false (str "Failed to parse variant props: " e)) false))
    ((ok vProps)
      (let [(vid (getPropStr vProps "id" ""))
            (text (getPropStr vProps "text" ""))
            (expectedValid (getPropBool vProps "valid" false))
            (expectedVer (getPropInt vProps "version" 0))
            (expectedDef (getPropStr vProps "defaultProfile" ""))
            (expectedProfs (getPropInt vProps "numProfiles" 0))
            (expectedMods (getPropInt vProps "numModels" 0))
            (expectedErr (getPropStr vProps "error" ""))
            (parsed (cfg/gateway_config_parse! text vid ".asl/mem/calibration/index.asn"))]
        (if expectedValid
          (do
            (refute (err? parsed) (str vid ": valid variant must not fail"))
            (mt parsed
              ((err e) (do (assert false (str "Expected variant " vid " to succeed, got error: " e)) false))
              ((ok tbl)
                (do
                  (assert (= tbl.version expectedVer) (str vid ": version matches"))
                  (refute (!= tbl.version expectedVer) (str vid ": version must not mismatch"))
                  (assert (= tbl.defaultProfile expectedDef) (str vid ": default profile matches"))
                  (assert (= (listLength tbl.profileOrder) expectedProfs) (str vid ": num profiles matches"))
                  (assert (= (listLength (mapKeys tbl.models)) expectedMods) (str vid ": num models matches"))
                  true))))
          (do
            (refute (ok? parsed) (str vid ": invalid variant must not succeed"))
            (mt parsed
              ((ok _) (do (assert false (str "Expected variant " vid " to fail, but succeeded")) false))
              ((err e)
                (do
                  (assert (> (stringLength e) 0) (str vid ": error is non-empty"))
                  (refute (stringEmpty? e) (str vid ": error string must not be empty"))
                  (if (= vid "malformed_form")
                    (do (assert (stringContains? (stringLower e) "unclosed") (str vid ": malformed form reports unclosed: " e)) true)
                    (if (> (stringLength expectedErr) 0)
                      (let [(prefix (optionOr (stringSlice expectedErr 0 10) expectedErr))]
                        (do (assert (stringContains? (stringLower e) (stringLower prefix))
                                (str vid ": error contains expected substring (" prefix ") in (" e ")")) true))
                      true))
                  true))))))))

fn testVariantsLoop! vs: (List rd/SExpr) -> Bool
  (mt (listHead vs)
    ((none) true)
    ((some v)
      (let [(ok1 (testOneVariant! v))
            (rest (optionOr (listTail vs) (list)))]
        (and ok1 (testVariantsLoop! rest)))))

fn testAsnScalarAndFigure -> Bool
  (let [(sb (cfg/asn_scalar (rd/sexprAtom "true")))
        (sf (cfg/asn_scalar (rd/sexprAtom "false")))
        (si (cfg/asn_scalar (rd/sexprAtom "123")))
        (sneg (cfg/asn_scalar (rd/sexprAtom "-456")))
        (sflt (cfg/asn_scalar (rd/sexprAtom "3.14")))
        (sstr (cfg/asn_scalar (rd/sexprAtom "\"quoted string\"")))
        (skw (cfg/asn_scalar (rd/sexprAtom ":my-keyword")))
        (sident (cfg/asn_scalar (rd/sexprAtom "bareSymbol")))
        (figAtom (cfg/asn_figure (rd/sexprAtom "999")))
        (figList (cfg/asn_figure (rd/sexprList (list (rd/sexprAtom ":v") (rd/sexprAtom "888")))))]
    (do
      (mt sb ((cfg/scalarBool b) (assert b "true atom is scalarBool true")) (_ (assert false "sb wrong")))
      (mt sf ((cfg/scalarBool b) (assert (not b) "false atom is scalarBool false")) (_ (assert false "sf wrong")))
      (mt si ((cfg/scalarInt n) (assert (= n 123) "int atom is scalarInt 123")) (_ (assert false "si wrong")))
      (mt sneg ((cfg/scalarInt n) (assert (= n -456) "negative int atom is scalarInt -456")) (_ (assert false "sneg wrong")))
      (mt sflt ((cfg/scalarFloat f) (assert (> f 3.0) "float atom is scalarFloat > 3")) (_ (assert false "sflt wrong")))
      (mt sstr ((cfg/scalarStr s) (assert (= s "quoted string") "quoted str unescaped")) (_ (assert false "sstr wrong")))
      (mt skw ((cfg/scalarStr s) (assert (= s "my-keyword") "keyword stripped")) (_ (assert false "skw wrong")))
      (mt sident ((cfg/scalarStr s) (assert (= s "bareSymbol") "bare symbol scalarStr")) (_ (assert false "sident wrong")))
      (mt figAtom ((cfg/scalarInt n) (assert (= n 999) "figAtom is scalarInt 999")) (_ (assert false "figAtom wrong")))
      (mt figList ((cfg/scalarInt n) (assert (= n 888) "figList unwraps :v 888")) (_ (assert false "figList wrong")))
      true))

fn testGatewayParams -> Bool
  (let [(propsValid (mapFromPairs (list (pair "temperature" (rd/sexprAtom "0.7"))
                                        (pair "effort" (rd/sexprAtom "high"))
                                        (pair "maxTokens" (rd/sexprAtom "4096"))
                                        (pair "contextBudget" (rd/sexprAtom "16384"))
                                        (pair "timeoutSec" (rd/sexprAtom "120.0"))
                                        (pair "reasoning" (rd/sexprAtom "true"))
                                        (pair "rpm" (rd/sexprAtom "60.0")))))
        (resValid (cfg/gateway_params propsValid "testValid"))
        (pValid (pairFirst resValid))
        (errsValid (pairSecond resValid))
        (propsInvalid (mapFromPairs (list (pair "effort" (rd/sexprAtom "superfast"))
                                          (pair "maxTokens" (rd/sexprAtom "-10"))
                                          (pair "reasoning" (rd/sexprAtom "yes")))))
        (resInvalid (cfg/gateway_params propsInvalid "testInvalid"))
        (errsInvalid (pairSecond resInvalid))]
    (do
      (assert (listEmpty? errsValid) "valid gateway params produce no errors")
      (refute (not (listEmpty? errsValid)) "valid gateway params must not produce errors")
      (mt pValid.temperature
        ((some t) (assert (> t 0.6) "temperature parsed"))
        ((none) (assert false "temperature missing")))
      (mt pValid.effort
        ((some eff) (assert (= eff "high") "effort parsed"))
        ((none) (assert false "effort missing")))
      (mt pValid.maxTokens
        ((some mtVal) (assert (= mtVal 4096) "maxTokens parsed"))
        ((none) (assert false "maxTokens missing")))
      (mt pValid.contextBudget
        ((some cbVal) (assert (= cbVal 16384) "contextBudget parsed"))
        ((none) (assert false "contextBudget missing")))
      (mt pValid.reasoning
        ((some rBool) (assert rBool "reasoning parsed"))
        ((none) (assert false "reasoning missing")))
      (assert (= (listLength errsInvalid) 3) "invalid params produce 3 errors")
      (refute (listEmpty? errsInvalid) "invalid params must produce errors")
      true))

fn testRoutingAndEntries! tbl: cfg/GatewayTable -> Bool
  (let [(lineDesign (cfg/gateway_intent_line tbl "design"))
        (lineImplement (cfg/gateway_intent_line tbl "implement"))
        (linePlan (cfg/gateway_intent_line tbl "plan"))
        (lineUnknown (cfg/gateway_intent_line tbl "unknownIntent"))
        (pWork (optionOr (mapGet tbl.profiles "work")
                         (cfg/GatewayProfile :id "" :routes (list) :fallback (none))))
        (routeDesign (cfg/gateway_v2_route pWork lineDesign))
        (routeImplement (cfg/gateway_v2_route pWork lineImplement))
        (routeUnknown (cfg/gateway_v2_route pWork lineUnknown))
        (entriesDesign (cfg/gateway_v2_entries! tbl "work" "design"))
        (aliasLookupDirect (cfg/gateway_v2_alias_entry! tbl "flashLow"))
        (aliasLookupProviderName (cfg/gateway_v2_alias_entry! tbl "codex/gpt-6-astra"))
        (aliasLookupNonexistent (cfg/gateway_v2_alias_entry! tbl "nonexistent/model"))
        (anyOnlys (cfg/gateway_any_only_intents tbl))
        (tblWithUndeclared (cfg/gateway_note_intent tbl "customNewIntent"))
        (tblWithDeclared (cfg/gateway_note_intent tblWithUndeclared "plan"))
        (undMap (cfg/gateway_undeclared_intents tblWithDeclared))]
    (do
      (assert (= lineDesign (list "design" "plan")) "design intent line is [design, plan]")
      (refute (!= lineDesign (list "design" "plan")) "design line must not deviate")
      (assert (= lineImplement (list "implement" "code")) "implement intent line is [implement, code]")
      (refute (!= lineImplement (list "implement" "code")) "implement line must not deviate")
      (assert (= linePlan (list "plan")) "plan intent line is [plan]")
      (assert (= lineUnknown (list "unknownintent")) "unknown intent line is [unknownintent]")
      (assert (= routeDesign (list "opus" "flashHigh")) "route for design is [opus, flashHigh]")
      (refute (!= routeDesign (list "opus" "flashHigh")) "route design must not deviate")
      (assert (= routeImplement (list "flashLow")) "route for implement is [flashLow]")
      (assert (= routeUnknown (list "flashLow")) "route for unknown falls back to any [flashLow]")
      (assert (not (listEmpty? entriesDesign)) "entries for design is non-empty")
      (let [(firstEntry (optionOr (listHead entriesDesign) (cfg/entryUnresolved "")))]
        (assert (= (cfg/gateway_entry_label firstEntry) "opus") "first entry label is opus"))
      (refute (none? aliasLookupDirect) "direct alias lookup must not be none")
      (mt aliasLookupDirect
        ((some e) (assert (= (cfg/gateway_entry_label e) "flashLow") "direct alias lookup succeeds"))
        ((none) (assert false "direct alias lookup failed")))
      (refute (none? aliasLookupProviderName) "provider/name lookup must not be none")
      (mt aliasLookupProviderName
        ((some e) (assert (= (cfg/gateway_entry_label e) "astra") "provider/name alias lookup finds astra"))
        ((none) (assert false "provider/name lookup failed")))
      (refute (some? aliasLookupNonexistent) "nonexistent alias lookup must not be some")
      (assert (none? aliasLookupNonexistent) "nonexistent alias returns none")
      (assert (not (listEmpty? anyOnlys)) "gateway_any_only_intents finds profiles resolving only to any")
      (mt (mapGet undMap "customNewIntent")
        ((some count) (assert (= count 1) "customNewIntent noted once"))
        ((none) (assert false "customNewIntent not in undeclared map")))
      (assert (none? (mapGet undMap "plan")) "declared intent plan is not in undeclared map")
      true))

fn testProfilesV1Parse -> Bool
  (let [(v1Text "(:gateway :profile defProfile :profiles ((:profile :id defProfile :routes ((:intent any :models (\"m1\"))))))")
        (parseRes (cfg/gateway_profiles_parse v1Text))]
    (mt parseRes
      ((err e) (do (assert false (str "v1 profile parse failed: " e)) false))
      ((ok v1Cfg)
        (do
          (assert (= v1Cfg.defaultProfile "defProfile") "v1 default profile matches")
          (refute (!= v1Cfg.defaultProfile "defProfile") "v1 default profile must not mismatch")
          (assert (mapHas? v1Cfg.profiles "defProfile") "v1 profiles map has defProfile")
          true))))

fn ! runTests -> Bool
  (let [(contentRes (fileReadString "asl/packages/asl-gateway/tests/configFixture.asn"))]
    (mt contentRes
      ((err e) (do (assert false (str "Failed to read fixture: " e)) false))
      ((ok content)
        (let [(toks (lx/tokenize content))]
          (mt (ast/readForms toks)
            ((err e) (do (assert false (str "Lex/ast error reading fixture: " e.msg)) false))
            ((ok forms)
              (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
                (mt (cfg/asn_props top (some ":fixture"))
                  ((err e) (do (assert false (str "Fixture form error: " e)) false))
                  ((ok fProps)
                    (mt (mapGet fProps "variants")
                      ((none) (do (assert false "No :variants in fixture") false))
                      ((some vListExpr)
                        (mt vListExpr
                          ((rd/sexprList vList)
                            (do
                              (assert (>= (listLength vList) 12) "At least 12 fixture variants tested")
                              (refute (< (listLength vList) 12) "Fixture must have >= 12 variants")
                              (assert (testVariantsLoop! vList) "All fixture variants verified")
                              (assert (testAsnScalarAndFigure) "ASN scalar and figure tested")
                              (assert (testGatewayParams) "Gateway params validation tested")
                              (let [(userGtwyRes (cfg/gateway_config_parse! (getPropStr (pairFirst (let [(v0 (optionOr (listHead vList) (rd/sexprAtom "")))] (mt (cfg/asn_props v0 (some ":variant")) ((ok p) (pair p (list))) ((err _) (pair (mapEmpty) (list)))))) "text" "") "userGtwy" ".asl/mem/calibration/index.asn"))]
                                (mt userGtwyRes
                                  ((err e) (assert false (str "user gateway parse failed: " e)))
                                  ((ok tbl) (assert (testRoutingAndEntries! tbl) "Routing, entries, and labels tested"))))
                              (assert (testProfilesV1Parse) "Profiles v1 parsing tested")
                              true))
                          (_ (do (assert false "variants is not a list") false))))))))))))))
