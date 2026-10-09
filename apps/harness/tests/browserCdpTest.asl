(module aslHarness/tests/browserCdpTest :x [runTests] :i [(browserCdp :a cdp)])

fn testMakeCdpConnection -> Bool
  (let [(conn (cdp/makeCdpConnection "ws://127.0.0.1:9222/devtools/page/1" "sess-42")) (conn2 (cdp/CdpConnection :targetUrl "ws" :sessionId "s" :isConnected false))] (assert (= conn.targetUrl "ws://127.0.0.1:9222/devtools/page/1") "target url matches") (assert (= conn.sessionId "sess-42") "session id matches") (assert conn.isConnected "is connected is true") (refute conn2.isConnected "CdpConnection explicitly disconnected") true)

fn testNavigate! -> Bool
  (let [(conn (cdp/makeCdpConnection "ws://127.0.0.1:9222" "s1")) (cmd (cdp/navigate! conn "https://example.com"))] (assert (= cmd "") "cmd is empty in sandbox") true)

fn testExtractAxtree! -> Bool
  (let [(conn (cdp/makeCdpConnection "ws://127.0.0.1:9222" "s1")) (cmd (cdp/extractAxtree! conn))] (assert (= cmd "") "cmd is empty in sandbox") true)

fn testDispatchClick! -> Bool
  (let [(conn (cdp/makeCdpConnection "ws://127.0.0.1:9222" "s1")) (cmd (cdp/dispatchClick! conn 101))] (assert (= cmd "") "cmd is empty in sandbox") true)

fn ! runTests -> Bool
  (do (testMakeCdpConnection) (testNavigate!) (testExtractAxtree!) (testDispatchClick!) true)
