(module asl-agent-bus/tests/browserBridgeCorsTest :x [testAllowedOrigin testRejectedOrigin testAllowedOrigin204 testRejectedOrigin204 runTests] :i [(browserBridge :a bb)])

fn testAllowedOrigin -> Bool
  (let [(response (bb/formatCorsHttpResponse 200 "text/plain" "ok" "http://localhost:5173"))]
    (do (assert (stringContains? response "Access-Control-Allow-Origin: http://localhost:5173") "allowed origin is echoed for 200") true))

fn testRejectedOrigin -> Bool
  (let [(response (bb/formatCorsHttpResponse 200 "text/plain" "ok" "http://evil.com"))]
    (do (assert (not (stringContains? response "Access-Control-Allow-Origin:")) "unlisted origin gets no CORS header for 200") true))

fn testAllowedOrigin204 -> Bool
  (let [(response (bb/formatCorsHttpResponse 204 "" "" "http://localhost:5173"))]
    (do (assert (stringContains? response "Access-Control-Allow-Origin: http://localhost:5173") "allowed origin is echoed for 204") true))

fn testRejectedOrigin204 -> Bool
  (let [(response (bb/formatCorsHttpResponse 204 "" "" "http://evil.com"))]
    (do (assert (not (stringContains? response "Access-Control-Allow-Origin:")) "unlisted origin gets no CORS header for 204") true))

fn runTests -> Bool
  (do (testAllowedOrigin) (testRejectedOrigin) (testAllowedOrigin204) (testRejectedOrigin204) true)
