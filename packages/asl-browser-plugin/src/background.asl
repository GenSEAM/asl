(module aslBrowserPlugin/background :x [initServiceWorker routeActionMessage handleMessage] :i [(content :a cnt) (safetyGate :a sg)])

fn initServiceWorker -> Str
  "(:service-worker :state \"active\" :engine \"wasi\")"

fn routeActionMessage msg: Str -> Str
  (let [(actionIdx (stringIndexOf msg ":action \""))
        (actionVal (if (some? actionIdx) (let [(sub (optionOr (stringSlice msg (+ (optionOr actionIdx 0) 9) (stringLength msg)) "")) (qIdx (stringIndexOf sub "\""))] (if (some? qIdx) (optionOr (stringSlice sub 0 (optionOr qIdx 0)) "") "")) ""))
        (cleanAct (stringLower (stringTrim actionVal)))
        (isConfirmed (stringContains? msg ":confirmed true"))
        (safetyCheck (let [(act (sg/makeBrowserAction cleanAct "tab-1" "" isConfirmed))] (sg/isActionPermitted? act [] "")))
        (isValidAct (or (= cleanAct "click")
                      (or (= cleanAct "fill")
                        (or (= cleanAct "type")
                          (or (= cleanAct "hover")
                            (or (= cleanAct "key")
                              (or (= cleanAct "scroll")
                                (or (= cleanAct "watchmedia")
                                  (or (= cleanAct "extractmedia")
                                    (or (= cleanAct "navigate")
                                      (or (= cleanAct "snapshot")
                                        (or (= cleanAct "execasl")
                                          (or (= cleanAct "execinpageagent")
                                            (= cleanAct "execInPageAgent"))))))))))))))
        (hasEmptySel (or (stringContains? msg ":selector \"\"") (stringContains? msg ":selector ''")))]
    (if (not safetyCheck)
      "(:action-result :status \"blocked\" :reason \"safety-gate-rejected\")"
      (if (and isValidAct (or (not hasEmptySel) (= cleanAct "navigate") (= cleanAct "snapshot") (= cleanAct "execinpageagent") (= cleanAct "extractmedia")))
        (if (= cleanAct "execinpageagent")
          "(:action-result :status \"dispatched\" :bridge \"in-page-agent\" :success true)"
          "(:action-result :status \"dispatched\" :success true)")
        "(:action-result :status \"failed\" :reason \"invalid-action-or-selector\")")))

fn handleMessage msg: Str -> Str
  (let [(clean (stringTrim msg))] (cond ((or (= clean "(:ping)") (= clean "ping")) "(:pong)") ((or (= clean "(:get-version)") (= clean "get-version")) "(:version \"1.0.0\")") ((stringContains? clean ":extract-context") (let [(urlIdx (stringIndexOf clean ":url \"")) (url (if (some? urlIdx) (let [(sub (optionOr (stringSlice clean (+ (optionOr urlIdx 0) 6) (stringLength clean)) "")) (qIdx (stringIndexOf sub "\""))] (if (some? qIdx) (optionOr (stringSlice sub 0 (optionOr qIdx 0)) "https://agentslang.org") "https://agentslang.org")) "https://agentslang.org")) (titleIdx (stringIndexOf clean ":title \"")) (title (if (some? titleIdx) (let [(sub (optionOr (stringSlice clean (+ (optionOr titleIdx 0) 8) (stringLength clean)) "")) (qIdx (stringIndexOf sub "\""))] (if (some? qIdx) (optionOr (stringSlice sub 0 (optionOr qIdx 0)) "AgentSlang Hub") "AgentSlang Hub")) "AgentSlang Hub"))] (str "(:context-response :status \"ok\" :title \"" title "\" :url \"" url "\")"))) ((stringContains? clean ":tab-query") "(:tab-query-response :status \"ok\" :tabs-count 1)") ((or (stringContains? clean ":exec-action") (stringContains? clean ":dispatch-action")) (routeActionMessage clean)) (else (str "(:error :reason \"unknown-message\" :raw \"" clean "\")"))))
