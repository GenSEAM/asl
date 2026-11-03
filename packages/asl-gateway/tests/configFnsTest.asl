(module aslGateway/tests/configFnsTest
  :x [runTests]
  :i [(config :a c)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)])

; (:m :ref COVERAGE-RATCHET-RED :do "direct cases for config functions the other suites reach only through larger flows: the concurrency defaults, the empty and text-built limit scope (groups, provider bases, model prices), the limit and group errors of a parsed :gateway row, a top-level scalar override of any type, and the mode and judge rules of a named profile")
fn base -> String
  "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://b\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\" :priceInPerM 1.0 :priceOutPerM 2.0) (:model :id m2 :provider fp :name \"n2\"))"

fn withExtra extra: String -> String
  (str (base) " " extra ")")

fn propsOf text: String -> (Map String rd/SExpr)
  (match (ast/readForms (lx/tokenize text))
    ((err _) (mapEmpty))
    ((ok forms)
     (match (listHead forms)
       ((none) (mapEmpty))
       ((some f) (match (c/asnProps f.expr (some ":gateway")) ((ok p) p) ((err _) (mapEmpty)))))))

fn testDefaults -> Bool
  (let [(e (c/emptyLimitScope))]
    (do (assert (= (c/defaultConcurrencyLeaseSec) 600) "a concurrency slot is held at most 600 s by default")
        (assert (= (c/defaultConcurrencyPollMs) 250) "a parked call asks again every 250 ms by default")
        (assert (and (listEmpty? e.groups) (and (listEmpty? e.bases) (listEmpty? e.prices))) "the empty scope has no groups, bases or prices")
        true))

fn testScope -> Bool
  (let [(sc (c/gatewayLimitScopeFromText (withExtra ":groups ((:group :id G :provider fp :models (m1 m2)))")))
        (bad (c/gatewayLimitScopeFromText "((("))
        (two (c/gatewayLimitScopeFromText (str (withExtra "") (withExtra ""))))
        (other (c/gatewayLimitScopeFromText "(:other :a 1)"))]
    (do (assert (= (listLength sc.groups) 1) "one group row is read")
        (assert (= (map (fn [(g c/GatewayGroup)] -> String g.id) sc.groups) (list "G")) "the group keeps its id")
        (assert (= (map (fn [(g c/GatewayGroup)] -> (List String) g.models) sc.groups) (list (list "m1" "m2"))) "the group keeps its members in order")
        (assert (= sc.bases (list (pair "fp" "http://b"))) "each provider's base is read")
        (assert (= sc.prices (list (pair "m1" (pair 1.0 2.0)) (pair "m2" (pair 0.0 0.0)))) "each model's price per million is read, an unpriced model is 0 and 0")
        (assert (= bad (c/emptyLimitScope)) "unparseable text is the empty scope")
        (assert (= two (c/emptyLimitScope)) "two top-level forms are the empty scope")
        (assert (= other (c/emptyLimitScope)) "a form that is not :gateway is the empty scope")
        true))

fn has errs: (List String) part: String -> Bool
  (listAny? (fn [(e String)] -> Bool (stringContains? e part)) errs)

fn testErrors -> Bool
  (let [(sound (c/gatewayLimitErrors (propsOf (withExtra ":groups ((:group :id G :provider fp :models (m1 m2))) :limits ((:limit :scope group :group G :window day :calls 100))"))))
        (undeclared (c/gatewayLimitErrors (propsOf (withExtra ":limits ((:limit :scope group :group Z :window day :calls 5))"))))
        (twice (c/gatewayLimitErrors (propsOf (withExtra ":groups ((:group :id G :provider fp :models (m1)) (:group :id G :provider fp :models (m2)))"))))
        (unknownModel (c/gatewayLimitErrors (propsOf (withExtra ":groups ((:group :id G :provider fp :models (m1 nope)))"))))
        (lease (c/gatewayLimitErrors (propsOf (withExtra ":concurrencyLeaseSec 5"))))
        (poll (c/gatewayLimitErrors (propsOf (withExtra ":concurrencyPollMs 99999"))))
        (leaseOk (c/gatewayLimitErrors (propsOf (withExtra ":concurrencyLeaseSec 600 :concurrencyPollMs 250"))))
        (malformed (c/gatewayLimitErrors (propsOf (withExtra ":limits ((:limit :provider fp :scope planet :window day :calls 5))"))))]
    (do (assert (listEmpty? sound) (str "a declared group and a limit naming it are sound: " (stringJoin sound " | ")))
        (assert (has undeclared "group Z is not declared under :groups") "a limit naming an undeclared group is an error")
        (assert (has twice "group G is declared twice") "a group declared twice is an error")
        (assert (has unknownModel "nope") "a group naming an unknown model is an error naming it")
        (assert (has lease "concurrencyLeaseSec") "a lease under 10 s is an error naming the key")
        (assert (has poll "concurrencyPollMs") "a poll over 5000 ms is an error naming the key")
        (assert (listEmpty? leaseOk) "the documented defaults are in range")
        (assert (not (listEmpty? malformed)) "a malformed limit row is named")
        true))

fn testOverride -> Bool
  (let [(text "(:gateway :v 2 :flag false :count 3 :word keep)")]
    (do (assert (= (c/gatewayTopScalarOverride text "flag") (some (c/scalarBool false))) "a boolean row reads as a boolean")
        (assert (= (c/gatewayTopScalarOverride text "count") (some (c/scalarInt 3))) "an integer row reads as an integer")
        (assert (= (c/gatewayTopScalarOverride text "word") (some (c/scalarStr "keep"))) "a bare word reads as a string")
        (assert (= (c/gatewayTopScalarOverride text "absent") (none)) "an absent key is none")
        (assert (= (c/gatewayTopScalarOverride "(((" "flag") (none)) "unparseable text is none")
        (assert (= (c/gatewayTopScalarOverride (str text " " text) "flag") (none)) "two top-level forms are none")
        (assert (= (c/gatewayTopScalarOverride "(:other :flag true)" "flag") (none)) "a form that is not :gateway is none")
        true))

fn tableOf extra: String -> (Result c/GatewayTable String)
  (c/gatewayProfilesLoadText! "/test" true
    (ok (str (base) " :intents ((:intent :id code)) :profiles (" extra ") :uses ((:use :for default :profile plain))" ")"))
    "")

fn testProfilesOn t: c/GatewayTable -> Bool
  (let [(judged (c/gatewayProfileJudge t "judged"))]
    (do (assert (= (c/gatewayProfileMode t "plain") "route") "a profile without :mode routes")
        (assert (= (c/gatewayProfileMode t "pinned") "pin") "a pinned profile says pin")
        (assert (= (c/gatewayProfileMode t "judged") "judge") "a judge profile says judge")
        (assert (= (c/gatewayProfileMode t "nowhere") "route") "an unknown profile routes")
        (assert (= (c/gatewayProfileJudge t "plain") (c/judgeDefault)) "a profile without :judge has the default rules")
        (assert (= (c/gatewayProfileJudge t "nowhere") (c/judgeDefault)) "an unknown profile has the default rules")
        (assert (not judged.empty) "the :empty row is read")
        (assert judged.truncated "the :truncated row is read")
        (assert (= judged.stepIntents (list "plan")) "step intents are read and lowercased")
        (assert (= judged.stepHeads (list "STEP:")) "step heads are read as written")
        true))

fn profilesText -> String
  "(:profile :id plain :routes ((:intent any :chain (m1 m2)))) (:profile :id pinned :mode pin :routes ((:intent any :chain (m1)))) (:profile :id judged :mode judge :judge (:empty false :truncated true :stepIntents (Plan) :stepHeads (\"STEP:\")) :routes ((:intent any :chain (m1 m2))))"

fn testProfiles -> Bool
  (match (tableOf (profilesText))
    ((ok t) (testProfilesOn t))
    ((err e) (do (assert false (str "the profile table loads: " e)) false)))

fn ! runTests -> Bool
  (do (testDefaults) (testScope) (testErrors) (testOverride) (testProfiles) true)
