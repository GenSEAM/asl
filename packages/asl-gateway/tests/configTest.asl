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

fn ! testSessionHeaderParse -> Bool
  (let [(withHeaderText "(:gateway :v 2\n  :providers ((:provider :id custom :kind openai :base \"https://example.com\" :sessionHeader \"x-opencode-session\"))\n  :models ((:model :id m1 :provider custom :name \"m1\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (withHeaderRes (cfg/gateway_config_parse! withHeaderText "sessionHeaderPresent" ".asl/mem/calibration/index.asn"))
        (withoutHeaderText "(:gateway :v 2\n  :providers ((:provider :id custom :kind openai :base \"https://example.com\"))\n  :models ((:model :id m1 :provider custom :name \"m1\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (withoutHeaderRes (cfg/gateway_config_parse! withoutHeaderText "sessionHeaderAbsent" ".asl/mem/calibration/index.asn"))]
    (and
      (mt withHeaderRes
        ((err e) (do (assert false (str "OCSESSION: provider with :sessionHeader failed to parse: " e)) false))
        ((ok tbl)
          (mt (mapGet tbl.providers "custom")
            ((none) (do (assert false "OCSESSION: provider custom missing from parsed table") false))
            ((some pv)
              (do
                (assert (= pv.sessionHeader "x-opencode-session") "OCSESSION: :sessionHeader is parsed onto GatewayProvider")
                (refute (!= pv.sessionHeader "x-opencode-session") "OCSESSION: :sessionHeader must not mismatch")
                true)))))
      (mt withoutHeaderRes
        ((err e) (do (assert false (str "OCSESSION: provider without :sessionHeader failed to parse: " e)) false))
        ((ok tbl)
          (mt (mapGet tbl.providers "custom")
            ((none) (do (assert false "OCSESSION: provider custom missing from parsed table") false))
            ((some pv)
              (do
                (assert (= pv.sessionHeader "") "OCSESSION: absent :sessionHeader stays empty")
                true)))))))

; (:m :tags (anthropic) :do "GW-ANTHROPIC-KIND: a provider with :kind anthropic parses like openai (needs :base) and gateway_v2_entry! propagates the real provider kind onto the resolved GatewayEntry instead of a hardcoded openai literal; a :kind anthropic provider missing :base is rejected the same way an openai one would be")
fn testAnthropicKindParsesAndResolvesEntry -> Bool
  (let [(text "(:gateway :v 2\n  :providers ((:provider :id commandCodeMsg :kind anthropic :base \"https://api.commandcode.ai/provider/v1\" :keyEnv COMMANDCODE_API_KEY))\n  :models ((:model :id ccHaiku :provider commandCodeMsg :name \"claude-haiku-5-5\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (ccHaiku)))))\n  :uses ((:use :for default :profile p1)))")
        (res (cfg/gateway_config_parse! text "anthropicKind" ".asl/mem/calibration/index.asn"))
        (missingBaseText "(:gateway :v 2\n  :providers ((:provider :id badAnthropic :kind anthropic))\n  :models ((:model :id m1 :provider badAnthropic :name \"m1\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (missingBaseRes (cfg/gateway_config_parse! missingBaseText "anthropicKindNoBase" ".asl/mem/calibration/index.asn"))]
    (do
      (mt res
        ((err e) (assert false (str "ANTHROPICKIND: a well-formed :kind anthropic provider must parse: " e)))
        ((ok tbl)
          (mt (mapGet tbl.providers "commandCodeMsg")
            ((none) (assert false "ANTHROPICKIND: provider commandCodeMsg missing from parsed table"))
            ((some pv)
              (do
                (assert (= pv.kind "anthropic") "ANTHROPICKIND: :kind anthropic is parsed onto GatewayProvider")
                (mt (cfg/gateway_v2_entry! tbl "ccHaiku")
                  ((cfg/entryResolved e)
                   (do
                     (assert (= e.kind "anthropic") "ANTHROPICKIND: gateway_v2_entry! propagates the real provider kind, not a hardcoded openai literal")
                     (assert (= e.upstream.url "https://api.commandcode.ai/provider/v1") "ANTHROPICKIND: the resolved entry's upstream url is the provider's :base")
                     true))
                  ((cfg/entryUnresolved _) (assert false "ANTHROPICKIND: ccHaiku must resolve"))))))))
      (mt missingBaseRes
        ((ok _) (assert false "ANTHROPICKIND: a :kind anthropic provider with no :base must be rejected, same as openai"))
        ((err e) (assert (stringContains? e "needs :base") (str "ANTHROPICKIND: missing-base error names the requirement: " e))))
      true))

fn testGeminiKindParsesAndResolvesEntry -> Bool
  (let [(text "(:gateway :v 2\n  :providers ((:provider :id opencodeGemini :kind gemini :base \"https://opencode.ai/inference/go/v1\" :keyEnv OPENCODE_GO_API_KEY :sessionHeader \"x-opencode-session\"))\n  :models ((:model :id gemini4Argon :provider opencodeGemini :name \"gemini-4-argon-contributor\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (gemini4Argon)))))\n  :uses ((:use :for default :profile p1)))")
        (res (cfg/gateway_config_parse! text "geminiKind" ".asl/mem/calibration/index.asn"))
        (missingBaseText "(:gateway :v 2\n  :providers ((:provider :id badGemini :kind gemini))\n  :models ((:model :id m1 :provider badGemini :name \"m1\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (missingBaseRes (cfg/gateway_config_parse! missingBaseText "geminiKindNoBase" ".asl/mem/calibration/index.asn"))]
    (do
      (mt res
        ((err e) (assert false (str "GEMINIKIND: a well-formed :kind gemini provider must parse: " e)))
        ((ok tbl)
          (mt (mapGet tbl.providers "opencodeGemini")
            ((none) (assert false "GEMINIKIND: provider opencodeGemini missing from parsed table"))
            ((some pv)
              (do
                (assert (= pv.kind "gemini") "GEMINIKIND: :kind gemini is parsed onto GatewayProvider")
                (mt (cfg/gateway_v2_entry! tbl "gemini4Argon")
                  ((cfg/entryResolved e)
                   (do
                     (assert (= e.kind "gemini") "GEMINIKIND: gateway_v2_entry! propagates the real provider kind, not a hardcoded openai literal")
                     (assert (= e.upstream.url "https://opencode.ai/inference/go/v1") "GEMINIKIND: the resolved entry's upstream url is the provider's :base")
                     true))
                  ((cfg/entryUnresolved _) (assert false "GEMINIKIND: gemini4Argon must resolve"))))))))
      (mt missingBaseRes
        ((ok _) (assert false "GEMINIKIND: a :kind gemini provider with no :base must be rejected, same as openai"))
        ((err e) (assert (stringContains? e "needs :base") (str "GEMINIKIND: missing-base error names the requirement: " e))))
      true))

; (:m an optional top-level :ledgerPath overrides ul/defaultLedgerPath's home/.asl/run/gatewayCalls.asn; absent, malformed or non-string text is none, never guessed)
fn testLedgerPathOverride -> Bool
  (let [(withPath (cfg/gatewayLedgerPathOverride "(:gateway :v 2 :ledgerPath \"/custom/calls.asn\")"))
        (withoutPath (cfg/gatewayLedgerPathOverride "(:gateway :v 2)"))
        (malformed (cfg/gatewayLedgerPathOverride "not even a gateway form"))
        (nonString (cfg/gatewayLedgerPathOverride "(:gateway :v 2 :ledgerPath 42)"))]
    (do
      (assert (= withPath (some "/custom/calls.asn")) "CONFPATH: a :ledgerPath string is read back exactly")
      (assert (= withoutPath none) "CONFPATH: absent :ledgerPath is none, so the caller falls back to the default path")
      (assert (= malformed none) "CONFPATH: unparseable text is none, never a guess")
      (assert (= nonString none) "CONFPATH: a non-string :ledgerPath is none, not coerced")
      true))

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "an optional top-level :sharedUsagePath, same parse shape as :ledgerPath, overriding ul/defaultSharedUsagePath's home/.asl/run/usage/gatewayCalls.asn; a scratch-HOME gateway that copies the real gateway.asn verbatim (tools/fleet/freePool.asl's writeGatewayConfig!) carries this ABSOLUTE string unchanged, so it still appends to the real, shared, non-deleted ledger -- the gate this closes")
fn testSharedUsagePathOverride -> Bool
  (let [(samplePath (str (optionOr (envGet "HOME") "/opt/op") "/.asl/run/usage/gatewayCalls.asn"))
        (withPath (cfg/gatewaySharedUsagePathOverride (str "(:gateway :v 2 :sharedUsagePath \"" samplePath "\")")))
        (withoutPath (cfg/gatewaySharedUsagePathOverride "(:gateway :v 2)"))
        (malformed (cfg/gatewaySharedUsagePathOverride "not even a gateway form"))
        (nonString (cfg/gatewaySharedUsagePathOverride "(:gateway :v 2 :sharedUsagePath 42)"))]
    (do
      (assert (= withPath (some samplePath)) "SHAREDPATH: a :sharedUsagePath string is read back exactly, unaffected by whatever HOME reads it")
      (assert (= withoutPath none) "SHAREDPATH: absent :sharedUsagePath is none, so the caller falls back to the default home-derived path")
      (assert (= malformed none) "SHAREDPATH: unparseable text is none, never a guess")
      (assert (= nonString none) "SHAREDPATH: a non-string :sharedUsagePath is none, not coerced")
      true))

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "an optional top-level :dailyTokenBudgets list of (profileId N) pairs; a profile absent from the list, or absent in a text with no such key at all, is none -- never guessed, so an operator who sets no budget keeps unlimited behaviour for that profile")
fn testDailyTokenBudget -> Bool
  (let [(freeBulk (cfg/gatewayDailyTokenBudget "(:gateway :v 2 :dailyTokenBudgets ((freeBulk 2000000) (commandCode 5000000)))" "freeBulk"))
        (commandCode (cfg/gatewayDailyTokenBudget "(:gateway :v 2 :dailyTokenBudgets ((freeBulk 2000000) (commandCode 5000000)))" "commandCode"))
        (missingProfile (cfg/gatewayDailyTokenBudget "(:gateway :v 2 :dailyTokenBudgets ((freeBulk 2000000)))" "commandCode"))
        (noKeyAtAll (cfg/gatewayDailyTokenBudget "(:gateway :v 2)" "freeBulk"))
        (malformed (cfg/gatewayDailyTokenBudget "not even a gateway form" "freeBulk"))]
    (do
      (assert (= freeBulk (some 2000000)) "DAILYBUDGET: freeBulk's own row is read back exactly")
      (assert (= commandCode (some 5000000)) "DAILYBUDGET: a second row in the same list reads back exactly too")
      (assert (= missingProfile none) "DAILYBUDGET: a profile absent from the list is none, never a guessed default")
      (assert (= noKeyAtAll none) "DAILYBUDGET: a config with no :dailyTokenBudgets key at all is none")
      (assert (= malformed none) "DAILYBUDGET: unparseable text is none, never a guess")
      true))

; (:m :ref GW-BREAKER-STALE-20261018 :do "an optional top-level :breakerCooldownSec int, same parse shape as :ledgerPath; absent, malformed or non-int text is none, so a config that never sets this keeps the 600s hardcoded default -- this is the knob GW-BREAKER-STALE-20261018 found missing when a fixed 600s cooldown outlasted a whole 45-cell sweep")
fn testBreakerCooldownSecOverride -> Bool
  (let [(withSec (cfg/gatewayBreakerCooldownSecOverride "(:gateway :v 2 :breakerCooldownSec 30)"))
        (withoutSec (cfg/gatewayBreakerCooldownSecOverride "(:gateway :v 2)"))
        (malformed (cfg/gatewayBreakerCooldownSecOverride "not even a gateway form"))
        (nonInt (cfg/gatewayBreakerCooldownSecOverride "(:gateway :v 2 :breakerCooldownSec \"thirty\")"))]
    (do
      (assert (= withSec (some 30)) "COOLDOWNCFG: a :breakerCooldownSec int is read back exactly")
      (assert (= withoutSec none) "COOLDOWNCFG: absent :breakerCooldownSec is none, so the caller falls back to the 600s default")
      (assert (= malformed none) "COOLDOWNCFG: unparseable text is none, never a guess")
      (assert (= nonInt none) "COOLDOWNCFG: a non-int :breakerCooldownSec is none, not coerced")
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

fn ! testModelApiParse -> Bool
  (let [(okText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-m\" :api \"responses\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (badText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-m\" :api \"bogus\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (okRes (cfg/gateway_config_parse! okText "apiOk" ".asl/mem/calibration/index.asn"))
        (badRes (cfg/gateway_config_parse! badText "apiBad" ".asl/mem/calibration/index.asn"))]
    (and
      (mt okRes
        ((err e) (do (assert false (str "RESPAPI: :api responses must parse: " e)) false))
        ((ok tbl)
          (mt (mapGet tbl.models "m1")
            ((none) (do (assert false "RESPAPI: model m1 missing") false))
            ((some m)
              (mt m.params.api
                ((some a) (do (assert (= a "responses") "RESPAPI: :api parsed as responses") true))
                ((none) (do (assert false "RESPAPI: :api not parsed onto params") false)))))))
      (mt badRes
        ((ok _) (do (assert false "RESPAPI: :api bogus must be rejected") false))
        ((err e) (do (assert (stringContains? (stringLower e) ":api") (str "RESPAPI: bogus :api error names :api: " e)) true)))))

; (:m :do "GW-HARDCODED-CASCADES-20261017 gate: a role cascade is a config row, not a built-in model list, so editing only the :chain in the gateway config text -- no source change, no rebuild -- changes which model a role resolves to first")
fn ! testRoleCascadeIsConfigOnly -> Bool
  (let [(textA "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\") (:model :id m2 :provider test :name \"model-b\"))\n  :intents ((:intent :id coder))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)) (:intent coder :chain (m1 m2) :temperature 0.0))))\n  :uses ((:use :for default :profile p1)))")
        (textB "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\") (:model :id m2 :provider test :name \"model-b\"))\n  :intents ((:intent :id coder))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)) (:intent coder :chain (m2 m1) :temperature 0.0))))\n  :uses ((:use :for default :profile p1)))")
        (resA (cfg/gateway_config_parse! textA "cascadeA" ".asl/mem/calibration/index.asn"))
        (resB (cfg/gateway_config_parse! textB "cascadeB" ".asl/mem/calibration/index.asn"))]
    (mt resA
      ((err e) (do (assert false (str "role-cascade-is-config fixture A failed to parse: " e)) false))
      ((ok tblA)
        (mt resB
          ((err e) (do (assert false (str "role-cascade-is-config fixture B failed to parse: " e)) false))
          ((ok tblB)
            (mt (cfg/gatewayRouteEntriesExact! tblA (list) (none) "coder")
              ((err e) (do (assert false (str "role-cascade-is-config: route A failed: " e)) false))
              ((ok reA)
                (mt (cfg/gatewayRouteEntriesExact! tblB (list) (none) "coder")
                  ((err e) (do (assert false (str "role-cascade-is-config: route B failed: " e)) false))
                  ((ok reB)
                    (let [(firstLabel (fn [(re cfg/RouteEntries)] -> String
                                        (mt (listHead re.entries) ((some e) (cfg/gateway_entry_label e)) ((none) ""))))
                          (labA (firstLabel reA))
                          (labB (firstLabel reB))]
                      (do
                        (assert (= labA "m1") (str "role-cascade-is-config: config A's :chain (m1 m2) resolves coder to m1 first, got " labA))
                        (assert (= labB "m2") (str "role-cascade-is-config: config B's :chain (m2 m1) resolves coder to m2 first, got " labB))
                        (refute (= labA labB) "role-cascade-is-config: a config-only cascade edit must change which model is chosen first")
                        true)))))))))))

fn routeNamed routes: (List cfg/GatewayRoute) intent: String -> (Option cfg/GatewayRoute)
  (listHead (filter (fn [(r cfg/GatewayRoute)] -> Bool (= r.intent intent)) routes))

fn routeOfProfile tbl: cfg/GatewayTable pid: String intent: String -> (Option cfg/GatewayRoute)
  (mt (mapGet tbl.profiles pid)
    ((none) none)
    ((some pr) (routeNamed pr.routes intent)))

; (:m :do "GW-SPREAD-20261017 parse+validate gate: a route's :spread ((ALIAS WEIGHT) ...) sits beside :chain, read back as (alias weight) pairs in file order; :cooldownSec defaults to 60 and is overridable; a zero or negative weight, an alias unknown to :models, and a non-positive :cooldownSec are each a parse error naming the offender, never silently dropped or defaulted past")
fn ! testSpreadParsesWeightsAndValidates -> Bool
  (let [(okText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\") (:model :id m2 :provider test :name \"model-b\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1 m2) :spread ((m1 3) (m2 1))))))\n  :uses ((:use :for default :profile p1)))")
        (cooldownText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1) :spread ((m1 1)) :cooldownSec 30))))\n  :uses ((:use :for default :profile p1)))")
        (zeroWeightText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1) :spread ((m1 0))))))\n  :uses ((:use :for default :profile p1)))")
        (negWeightText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1) :spread ((m1 -2))))))\n  :uses ((:use :for default :profile p1)))")
        (unknownAliasText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1) :spread ((ghost 1))))))\n  :uses ((:use :for default :profile p1)))")
        (badCooldownText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1) :spread ((m1 1)) :cooldownSec 0))))\n  :uses ((:use :for default :profile p1)))")
        (okRes (cfg/gateway_config_parse! okText "spreadOk" ".asl/mem/calibration/index.asn"))
        (cooldownRes (cfg/gateway_config_parse! cooldownText "spreadCooldown" ".asl/mem/calibration/index.asn"))
        (zeroRes (cfg/gateway_config_parse! zeroWeightText "spreadZero" ".asl/mem/calibration/index.asn"))
        (negRes (cfg/gateway_config_parse! negWeightText "spreadNeg" ".asl/mem/calibration/index.asn"))
        (unknownRes (cfg/gateway_config_parse! unknownAliasText "spreadUnknown" ".asl/mem/calibration/index.asn"))
        (badCooldownRes (cfg/gateway_config_parse! badCooldownText "spreadBadCooldown" ".asl/mem/calibration/index.asn"))]
    (mt okRes
      ((err e) (do (assert false (str "SPREAD: a valid :spread must parse: " e)) false))
      ((ok tbl)
        (mt (routeOfProfile tbl "p1" "any")
          ((none) (do (assert false "SPREAD: the any route must exist") false))
          ((some route)
            (do
              (assert (= route.spread (list (pair "m1" 3) (pair "m2" 1))) (str "SPREAD: spread pairs read back in file order with their weights, got " route.spread))
              (assert (= route.cooldownSec 60) (str "SPREAD: cooldownSec defaults to 60 when absent, got " route.cooldownSec))
              (mt cooldownRes
                ((err e) (do (assert false (str "SPREAD: a valid :cooldownSec override must parse: " e)) false))
                ((ok tbl2)
                  (mt (routeOfProfile tbl2 "p1" "any")
                    ((none) (do (assert false "SPREAD: the any route must exist in the cooldown fixture") false))
                    ((some route2)
                      (do
                        (assert (= route2.cooldownSec 30) (str "SPREAD: an explicit :cooldownSec overrides the 60 default, got " route2.cooldownSec))
                        (assert (err? zeroRes) "SPREAD: a zero weight must be a parse error, never silently dropped")
                        (assert (mt zeroRes ((err e) (stringContains? e "m1")) ((ok _) false)) "SPREAD: the zero-weight error names the offending alias")
                        (assert (err? negRes) "SPREAD: a negative weight must be a parse error")
                        (assert (err? unknownRes) "SPREAD: an alias absent from :models must be a parse error")
                        (assert (mt unknownRes ((err e) (stringContains? e "ghost")) ((ok _) false)) "SPREAD: the unknown-alias error names the offending alias")
                        (assert (err? badCooldownRes) "SPREAD: a non-positive :cooldownSec must be a parse error")
                        true)))))))))))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "RouteEntries carries the matched route's :spread/:cooldownSec through gatewayRouteEntries!/gatewayRouteEntriesExact!, the same way it already carries :temperature -- cascadeChosen has nothing else to read these from")
fn ! testRouteEntriesCarriesSpread -> Bool
  (let [(okText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\") (:model :id m2 :provider test :name \"model-b\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1 m2) :spread ((m1 3) (m2 1)) :cooldownSec 45))))\n  :uses ((:use :for default :profile p1)))")
        (plainText "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (okRes (cfg/gateway_config_parse! okText "spreadEntriesOk" ".asl/mem/calibration/index.asn"))
        (plainRes (cfg/gateway_config_parse! plainText "spreadEntriesPlain" ".asl/mem/calibration/index.asn"))]
    (mt okRes
      ((err e) (do (assert false (str "SPREADLIVE: a valid config must parse: " e)) false))
      ((ok tbl)
        (mt (cfg/gatewayRouteEntries! tbl (list) (none) "any")
          ((err e) (do (assert false (str "SPREADLIVE: gatewayRouteEntries! must resolve the default profile: " e)) false))
          ((ok re)
            (do
              (assert (= re.spread (list (pair "m1" 3) (pair "m2" 1))) (str "SPREADLIVE: gatewayRouteEntries! must carry the route's :spread, got " re.spread))
              (assert (= re.cooldownSec 45) (str "SPREADLIVE: gatewayRouteEntries! must carry the route's :cooldownSec, got " re.cooldownSec))
              (mt (cfg/gatewayRouteEntriesExact! tbl (list) (none) "any")
                ((err e) (do (assert false (str "SPREADLIVE: gatewayRouteEntriesExact! must resolve the default profile: " e)) false))
                ((ok reExact)
                  (do
                    (assert (= reExact.spread (list (pair "m1" 3) (pair "m2" 1))) (str "SPREADLIVE: gatewayRouteEntriesExact! must carry the route's :spread too, got " reExact.spread))
                    (assert (= reExact.cooldownSec 45) (str "SPREADLIVE: gatewayRouteEntriesExact! must carry the route's :cooldownSec too, got " reExact.cooldownSec))
                    (mt plainRes
                      ((err e) (do (assert false (str "SPREADLIVE: a plain no-spread config must parse: " e)) false))
                      ((ok tbl2)
                        (mt (cfg/gatewayRouteEntries! tbl2 (list) (none) "any")
                          ((err e) (do (assert false (str "SPREADLIVE: gatewayRouteEntries! must resolve the plain profile: " e)) false))
                          ((ok rePlain)
                            (do
                              (assert (listEmpty? rePlain.spread) (str "SPREADLIVE: a route without :spread carries the empty-list default, got " rePlain.spread))
                              (assert (= rePlain.cooldownSec 60) (str "SPREADLIVE: a route without :cooldownSec carries the 60 default, got " rePlain.cooldownSec))
                              true))))))))))))))

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
                              (assert (testSessionHeaderParse) "OCSESSION: provider :sessionHeader parsing tested")
                              (let [(userGtwyRes (cfg/gateway_config_parse! (getPropStr (pairFirst (let [(v0 (optionOr (listHead vList) (rd/sexprAtom "")))] (mt (cfg/asn_props v0 (some ":variant")) ((ok p) (pair p (list))) ((err _) (pair (mapEmpty) (list)))))) "text" "") "userGtwy" ".asl/mem/calibration/index.asn"))]
                                (mt userGtwyRes
                                  ((err e) (assert false (str "user gateway parse failed: " e)))
                                  ((ok tbl) (assert (testRoutingAndEntries! tbl) "Routing, entries, and labels tested"))))
                              (assert (testProfilesV1Parse) "Profiles v1 parsing tested")
                              (assert (testModelApiParse) "RESPAPI: model :api parsing tested")
                              (assert (testLedgerPathOverride) "CONFPATH: top-level :ledgerPath override tested")
                              (assert (testSharedUsagePathOverride) "SHAREDPATH: top-level :sharedUsagePath override tested")
                              (assert (testDailyTokenBudget) "DAILYBUDGET: top-level :dailyTokenBudgets override tested")
                              (assert (testBreakerCooldownSecOverride) "COOLDOWNCFG: top-level :breakerCooldownSec override tested")
                              (assert (testAnthropicKindParsesAndResolvesEntry) "ANTHROPICKIND: :kind anthropic provider parsing and entry resolution tested")
                              (assert (testGeminiKindParsesAndResolvesEntry) "GEMINIKIND: :kind gemini provider parsing and entry resolution tested")
                              (assert (testRoleCascadeIsConfigOnly) "GW-HARDCODED-CASCADES-20261017: a config-only role cascade edit changes the chosen model")
                              (assert (testSpreadParsesWeightsAndValidates) "GW-SPREAD-20261017: :spread parses with :chain, validates weights and aliases, cooldownSec defaults and overrides")
                              (assert (testRouteEntriesCarriesSpread) "GW-SPREAD-LIVE-20261018: gatewayRouteEntries!/gatewayRouteEntriesExact! carry the matched route's :spread/:cooldownSec, defaulting to empty/60 for a route without one")
                              true))
                          (_ (do (assert false "variants is not a list") false))))))))))))))
