(module aslMem/pointerTest :x [runTests testMakeBlobPointer testFormatPointerToken testExtractScalarFact testPointerTokenSavings] :i [(pointer :a p)])

fn testMakeBlobPointer -> Bool
  (let [(raw "<html><body><h1>Hello World</h1><p>Sample text for offload test</p></body></html>") (ptr (p/makeBlobPointer "b3-dom-001" "dom" raw "DOM summary for hello page"))] (assert (= ptr.id "b3-dom-001") "id matches") (assert (= ptr.kind "dom") "kind matches") (assert (= ptr.bytes (stringLength raw)) "bytes match") (assert (= ptr.tokensSaved (/ (stringLength raw) 4)) "tokens saved match") (assert (= ptr.summary "DOM summary for hello page") "summary matches") true)

fn testFormatPointerToken -> Bool
  (let [(ptr (p/BlobPointer :id "b3-123" :kind "dom" :bytes 16800 :tokensSaved 4200 :summary "Authentication form DOM tree")) (tok (p/formatPointerToken ptr))] (assert (stringContains? tok "(:ptr :id \"b3-123\"") "token contains id") (assert (stringContains? tok ":kind \"dom\"") "token contains kind") (assert (stringContains? tok ":tokens-saved 4200") "token contains tokens-saved") (assert (stringContains? tok ":summary \"Authentication form DOM tree\")") "token contains summary") true)

fn testExtractScalarFact -> Bool
  (let [(ptr (p/makeBlobPointer "b3-dom-456" "dom" "<button id=\"sso\">Login SSO</button>" "SSO button")) (fact (p/extractScalarFact ptr "button_label" "Login SSO")) (fmt (p/formatPerceptualFact fact))] (assert (= fact.key "button_label") "key matches") (assert (= fact.val "Login SSO") "val matches") (assert (> fact.confidence 0.99) "confidence > 0.99") (assert (= fact.sourceId "b3-dom-456") "source-id matches") (assert (stringContains? fmt "(:fact :key \"button_label\" :val \"Login SSO\"") "formatted fact matches") true)

fn testPointerTokenSavings -> Bool
  (let [(largeContent "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789") (ptr (p/makeBlobPointer "b3-blob-big" "pdf" largeContent "100-char PDF segment")) (tok (p/formatPointerToken ptr))] (assert (= ptr.bytes 100) "bytes 100") (assert (= ptr.tokensSaved 25) "tokens saved 25") (assert (> ptr.tokensSaved 0) "tokens saved > 0") (assert (< (stringLength tok) ptr.bytes) "token string smaller than bytes") true)

fn runTests -> Bool
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p)) true (list (testMakeBlobPointer) (testFormatPointerToken) (testExtractScalarFact) (testPointerTokenSavings)))

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (runTests) (let [(u (println "asl-mem pointer tests passed cleanly"))] (ok ())) (let [(u (eprintln "asl-mem pointer test failure"))] (err (other))))
