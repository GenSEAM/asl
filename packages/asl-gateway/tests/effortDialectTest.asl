(module aslGateway/tests/effortDialectTest
  :x [runTests]
  :i [(aslGateway/config :a cfg) (aslGateway/chat :a ch) (asl-json/json :a j) (asl-parser/reader :a rd)])

fn bodyOf -> j/Json
  (j/jobj (list (pair "model" (j/jstr "m"))))

fn has? v: j/Json k: String -> Bool
  (some? (j/jsonGet v k))

; (:m :ref GWREASON :do "each dialect writes the provider's own field and returns the effort forwarded")
fn ! wireChecks -> Bool
  (let [(rLow (ch/applyEffort "reasoningEffort" (some "low") (bodyOf)))
        (rNone (ch/applyEffort "reasoningEffort" none (bodyOf)))
        (orLow (ch/applyEffort "openrouter" (some "low") (bodyOf)))
        (orNone (ch/applyEffort "openrouter" (some "none") (bodyOf)))
        (nimNone (ch/applyEffort "chatTemplateThinking" (some "none") (bodyOf)))
        (nimLow (ch/applyEffort "chatTemplateThinking" (some "low") (bodyOf)))
        (glm (ch/applyEffort "glmThinking" (some "none") (bodyOf)))
        (offD (ch/applyEffort "off" (some "low") (bodyOf)))
        (bad (ch/applyEffort "reasoningEffort" (some "turbo") (bodyOf)))]
    (do
      (assert (= (j/jsonGet (pairFirst rLow) "reasoning_effort") (some (j/jstr "low"))) "openai-compatible low sends reasoning_effort low")
      (assert (= (pairSecond rLow) (some "low")) "forwarded effort is reported")
      (assert (not (has? (pairFirst rNone) "reasoning_effort")) "no effort sends no field")
      (assert (none? (pairSecond rNone)) "no effort reports none")
      (assert (= (j/jsonGet (pairFirst orLow) "reasoning") (some (j/jobj (list (pair "effort" (j/jstr "low")))))) "openrouter shape reasoning.effort")
      (assert (= (j/jsonGet (pairFirst orNone) "reasoning") (some (j/jobj (list (pair "effort" (j/jstr "none")))))) "openrouter none disables reasoning")
      (assert (not (has? (pairFirst orNone) "reasoning_effort")) "openrouter does not send reasoning_effort")
      (assert (= (j/jsonGet (pairFirst nimNone) "chat_template_kwargs") (some (j/jobj (list (pair "enable_thinking" (j/jbool false)) (pair "thinking" (j/jbool false)))))) "nim none turns thinking off")
      (assert (= (j/jsonGet (pairFirst nimLow) "chat_template_kwargs") (some (j/jobj (list (pair "enable_thinking" (j/jbool true)) (pair "thinking" (j/jbool true)) (pair "low_effort" (j/jbool true)))))) "nim low keeps thinking on with low_effort")
      (assert (= (j/jsonGet (pairFirst glm) "thinking") (some (j/jobj (list (pair "type" (j/jstr "disabled")))))) "glm none disables thinking")
      (assert (= (pairFirst offD) (bodyOf)) "off sends nothing")
      (assert (none? (pairSecond offD)) "off reports none")
      (assert (= (pairFirst bad) (bodyOf)) "an unknown effort sends nothing")
      true))

fn ! defaultChecks -> Bool
  (do
    (assert (= (ch/effortDialectFor "ollama" "openai" none) "reasoningEffort") "ollama keeps reasoning_effort")
    (assert (= (ch/effortDialectFor "opencodeGo" "openai" none) "reasoningEffort") "openai-compatible default")
    (assert (= (ch/effortDialectFor "openrouter" "openai" none) "openrouter") "openrouter default")
    (assert (= (ch/effortDialectFor "nim" "openai" none) "chatTemplateThinking") "nim default")
    (assert (= (ch/effortDialectFor "nim" "openai" (some "off")) "off") "row override wins")
    (assert (= (ch/effortDialectFor "agy" "cli" none) "off") "non-openai kind sends nothing")
    true)

fn ! configChecks -> Bool
  (let [(okRes (cfg/gateway_params (mapFromPairs (list (pair "effort" (rd/sexprAtom "none")) (pair "effortDialect" (rd/sexprAtom "chatTemplateThinking")))) "t"))
        (badRes (cfg/gateway_params (mapFromPairs (list (pair "effortDialect" (rd/sexprAtom "bogus")))) "t"))]
    (do
      (assert (listEmpty? (pairSecond okRes)) "valid effortDialect parses without errors")
      (assert (= (pairFirst okRes).effortDialect (some "chatTemplateThinking")) "effortDialect parsed")
      (assert (= (pairFirst okRes).effort (some "none")) "effort none parsed")
      (assert (not (listEmpty? (pairSecond badRes))) "an unknown effortDialect is an error")
      true))

fn ! runTests -> Bool
  (and (wireChecks) (and (defaultChecks) (configChecks)))
