(module aslBusTests/browserBridgeTest :x [testBridgeInit testBridgeRegisterTab testBridgeEnqueueAndPollFifo testBridgeCompleteCommand testFormatCorsHttpResponse runTests] :i [(browserBridge :a bb) (asl-text/string :a s)])

fn testBridgeInit -> Bool
  (let [(st (bb/bridgeInit 8765))] (do (assert (== st.port 8765) "port is 8765") (assert (== (listLength st.tabs) 0) "tabs empty") (assert (== (listLength st.commands) 0) "commands empty") true))

fn testBridgeRegisterTab -> Bool
  (let [(st0 (bb/bridgeInit 8765)) (tab1 (bb/BridgeTab :tabId "tab-1" :url "https://example.com" :title "Example" :connectedAt 1000)) (st1 (bb/bridgeRegisterTab st0 tab1)) (tab1Updated (bb/BridgeTab :tabId "tab-1" :url "https://example.com/cart" :title "Cart" :connectedAt 1005)) (st2 (bb/bridgeRegisterTab st1 tab1Updated))] (do (assert (== (listLength st1.tabs) 1) "st1 tab count") (assert (== (listLength st2.tabs) 1) "st2 tab count") (assert (== (mt (listGet st2.tabs 0) ((some t) t.url) (none "")) "https://example.com/cart") "updated tab url") true))

fn testBridgeEnqueueAndPollFifo -> Bool
  (let [(st0 (bb/bridgeInit 8765)) (cmd1 (bb/BridgeCommand :id "c1" :tabId "tab-1" :action "browser_get_dom" :payload "{}" :status "pending" :result "")) (cmd2 (bb/BridgeCommand :id "c2" :tabId "tab-1" :action "browser_click" :payload "{\"selector\":\"#btn\"}" :status "pending" :result "")) (cmd3 (bb/BridgeCommand :id "c3" :tabId "tab-2" :action "browser_eval" :payload "{\"expression\":\"1+1\"}" :status "pending" :result "")) (st1 (bb/bridgeEnqueueCommand st0 cmd1)) (st2 (bb/bridgeEnqueueCommand st1 cmd2)) (st3 (bb/bridgeEnqueueCommand st2 cmd3)) (pollRes (bb/bridgePollCommands st3 "tab-1")) (stPolled (pairFirst pollRes)) (polledCmds (pairSecond pollRes)) (pollAgain (bb/bridgePollCommands stPolled "tab-1"))] (do (assert (== (listLength polledCmds) 2) "polled cmds count") (assert (== (mt (listGet polledCmds 0) ((some c) c.id) (none "")) "c1") "cmd 1 id") (assert (== (mt (listGet polledCmds 1) ((some c) c.id) (none "")) "c2") "cmd 2 id") (assert (== (listLength (pairSecond pollAgain)) 0) "second poll empty") true))

fn testBridgeCompleteCommand -> Bool
  (let [(st0 (bb/bridgeInit 8765)) (cmd (bb/BridgeCommand :id "c1" :tabId "tab-1" :action "browser_click" :payload "{}" :status "pending" :result "")) (st1 (bb/bridgeEnqueueCommand st0 cmd)) (st2 (bb/bridgeCompleteCommand st1 "c1" "completed" "clicked element"))] (mt (listGet st2.commands 0) ((some updatedCmd) (do (assert (== updatedCmd.status "completed") "cmd status completed") (assert (== updatedCmd.result "clicked element") "cmd result match") true)) (none false)))

fn testFormatCorsHttpResponse -> Bool
  (let [(resp200 (bb/formatCorsHttpResponse 200 "application/json" "{\"status\":\"ok\"}")) (resp204 (bb/formatCorsHttpResponse 204 "" ""))] (do (assert (not (= resp200 "")) "200 ok") (assert (stringContains? resp200 "Access-Control-Allow-Origin: http://localhost") "cors 200 allow origin") (assert (stringContains? resp200 "Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE") "cors 200 allow methods") (assert (stringContains? resp200 "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With") "cors 200 allow headers") (assert (not (= resp204 "")) "204 ok") (assert (stringContains? resp204 "Access-Control-Allow-Origin: http://localhost") "cors 204") true))

fn runTests -> Bool
  (do (testBridgeInit) (testBridgeRegisterTab) (testBridgeEnqueueAndPollFifo) (testBridgeCompleteCommand) (testFormatCorsHttpResponse) true)
