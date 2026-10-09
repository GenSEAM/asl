(module aslHarness/browserCdp :x [CdpConnection makeCdpConnection navigate! extractAxtree! dispatchClick!] :i [(coding :a c) (asl-text/escape :a esc)])

(schema CdpConnection (:f targetUrl Str) (:f sessionId Str) (:f isConnected Bool))

fn makeCdpConnection url: Str session: Str -> CdpConnection
  (CdpConnection :targetUrl url :sessionId session :isConnected true)

fn navigate! conn: CdpConnection destUrl: Str -> Str
  (let [(payload (str "{\"id\":1,\"method\":\"Page.navigate\",\"params\":{\"url\":\"" (esc/escapeJsonStr destUrl) "\"}}")) (call (c/ToolCall :id "cdp" :toolName "exec-cmd" :arguments (list (pair "bin" "bash") (pair "arg" "-c") (pair "arg" (str "echo '" payload "' | websocat " conn.targetUrl))))) (res (c/executeBuiltinTool! call))] res.output)

fn extractAxtree! conn: CdpConnection -> Str
  (let [(payload "{\"id\":2,\"method\":\"Accessibility.getFullAXTree\",\"params\":{}}") (call (c/ToolCall :id "cdp" :toolName "exec-cmd" :arguments (list (pair "bin" "bash") (pair "arg" "-c") (pair "arg" (str "echo '" payload "' | websocat " conn.targetUrl))))) (res (c/executeBuiltinTool! call))] res.output)

fn dispatchClick! conn: CdpConnection nodeId: I64 -> Str
  (let [(payload (str "{\"id\":3,\"method\":\"Input.dispatchMouseEvent\",\"params\":{\"type\":\"mousePressed\",\"button\":\"left\",\"clickCount\":1}}")) (call (c/ToolCall :id "cdp" :toolName "exec-cmd" :arguments (list (pair "bin" "bash") (pair "arg" "-c") (pair "arg" (str "echo '" payload "' | websocat " conn.targetUrl))))) (res (c/executeBuiltinTool! call))] res.output)
