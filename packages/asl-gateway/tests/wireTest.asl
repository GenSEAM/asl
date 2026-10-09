(module aslGateway/tests/wireTest :x [testWireHeaders testIsToolCall testIsDeclarativeAsn testExtractToolName testFormatToolCallFrame testDemuxRawAsnTurn runTests] :i [(wire :a wire)])

fn testWireHeaders -> Bool
  (let [(headers (wire/formatWireHeaders))] (do (assert (= (listLength headers) 3) "Must have 3 wire protocol headers") (assert (= (optionOr (listHead headers) "") "X-ASL-Wire-Protocol: asn/1.0") "First header must be ASN wire protocol") true))

fn testIsToolCall -> Bool
  (do (assert (wire/isToolCall? "(:call :tool \"bash\" :cmd \"ls\")") "(:call :tool ...) must be a tool call") (assert (wire/isToolCall? "(call :tool \"eval\" :expr \"(+ 1 2)\")") "(call :tool ...) must be a tool call") (assert (wire/isToolCall? "(:call \"read\" :file \"foo.txt\")") "(:call \"...\" ...) must be a tool call") (assert (wire/isToolCall? "(:tool-call :name \"git\")") "(:tool-call ...) must be a tool call") (assert (not (wire/isToolCall? "(:struct Foo (:f x I64))")) "(:struct ...) must not be a tool call") (assert (not (wire/isToolCall? "Hello, here is the answer.")) "Conversational text must not be a tool call") true)

fn testIsDeclarativeAsn -> Bool
  (do (assert (wire/isDeclarativeAsn? "(:struct User (:f name Str))") "(:struct ...) must be declarative ASN") (assert (wire/isDeclarativeAsn? "(:ast :node \"Program\")") "(:ast ...) must be declarative ASN") (assert (wire/isDeclarativeAsn? "(:code :lang \"asl\" \"(fn foo [] -> I64 42)\")") "(:code ...) must be declarative ASN") (assert (wire/isDeclarativeAsn? "(:config :port 8080)") "(:config ...) must be declarative ASN") (assert (wire/isDeclarativeAsn? "(module my-mod)") "(module ...) must be declarative ASN") (assert (not (wire/isDeclarativeAsn? "(:call :tool \"bash\")")) "Tool call must not be declarative ASN") true)

fn testExtractToolName -> Bool
  (let [(name1 (wire/extractToolName "(:call :tool \"bash\" :cmd \"ls\")")) (name2 (wire/extractToolName "(:call :tool \"read_file\" :path \"a.txt\")")) (name3 (wire/extractToolName "non-tool-call"))] (do (assert (= name1 "bash") "Tool name must be bash") (assert (= name2 "read_file") "Tool name must be read_file") (assert (= name3 "tool") "Fallback tool name must be tool") true))

fn testFormatToolCallFrame -> Bool
  (let [(frame (wire/formatToolCallFrame "search" ":query \"paxos\""))] (do (assert (= frame "(:call :tool \"search\" :args :query \"paxos\")") "Frame must match canonical S-expression") (assert (not (stringContains? frame "error")) "Frame must not contain error") true))

fn testDemuxRawAsnTurn -> Bool
  (let [(turnTool (wire/demuxRawAsnTurn "(:call :tool \"ls\" :path \".\")")) (turnText (wire/demuxRawAsnTurn "(:struct Result (:f ok Bool))")) (uiTool (pairFirst turnTool)) (toolsTool (pairSecond turnTool)) (uiText (pairFirst turnText)) (toolsText (pairSecond turnText))] (do (assert (= uiTool "") "UI text for tool call must be empty") (assert (= (listLength toolsTool) 1) "Must extract 1 tool call frame") (assert (= uiText "(:struct Result (:f ok Bool))") "Declarative ASN must remain in UI text") (assert (= (listLength toolsText) 0) "No tool calls extracted from declarative ASN") true))

fn runTests -> Bool
  (and (testWireHeaders) (and (testIsToolCall) (and (testIsDeclarativeAsn) (and (testExtractToolName) (and (testFormatToolCallFrame) (testDemuxRawAsnTurn))))))
