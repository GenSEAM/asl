(module aslGateway/tests/nativeToolsRowTest
  :x [runTests]
  :i [(config :a cfg) (chat :a ch) (asl-json/json :a j) (asl-parser/reader :a rd)])

; (:m :ref NATIVE-TOOLS-DEFAULT :do "a model row :nativeTools false is the capability flag for a route that rejects tools: it parses to some false, a non-boolean is an error, and the body sent upstream loses tools and tool_choice; without it the tools pass")

fn body -> j/Json
  (j/jobj (list (pair "model" (j/jstr "m")) (pair "tools" (j/jarr (list (j/jobj (list (pair "type" (j/jstr "function")))))))
                (pair "tool_choice" (j/jstr "auto"))))

fn emptyBody -> j/Json
  (j/jobj (list (pair "model" (j/jstr "m")) (pair "tools" (j/jarr (list)))))

fn ! runTests -> Bool
  (let [(off (cfg/gateway_params (mapFromPairs (list (pair "nativeTools" (rd/sexprAtom "false")))) "rowOff"))
        (bad (cfg/gateway_params (mapFromPairs (list (pair "nativeTools" (rd/sexprAtom "maybe")))) "rowBad"))
        (plain (cfg/gateway_params (mapFromPairs (list)) "rowPlain"))
        (sentOff (j/jsonEmit (ch/upstreamTools (pairFirst off) false (body))))
        (sentPlain (j/jsonEmit (ch/upstreamTools (pairFirst plain) false (body))))
        (sentEmpty (j/jsonEmit (ch/upstreamTools (pairFirst plain) true (emptyBody))))]
    (do
      (assert (listEmpty? (pairSecond off)) "nativeTools false parses without errors")
      (assert (match (pairFirst off).nativeTools ((some b) (not b)) ((none) false)) "nativeTools false is some false")
      (assert (= (listLength (pairSecond bad)) 1) "a non-boolean nativeTools is one error")
      (assert (not (stringContains? sentOff "tools")) (str "a row with nativeTools false sends neither tools nor tool_choice: " sentOff))
      (assert (stringContains? sentOff "\"model\"") "the rest of the body is kept")
      (assert (stringContains? sentPlain "\"tools\"") "a row without the flag sends the tools")
      (assert (stringContains? sentPlain "tool_choice") "and the tool choice")
      (assert (not (stringContains? sentEmpty "tools")) "dropEmptyTools still removes an empty tools array")
      true))
