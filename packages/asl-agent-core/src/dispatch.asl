(module asl-agent-core/dispatch
  :d "Zero-JSON tool dispatcher and validation engine for AgentScript S-expressions."
  :x [ToolRegistry register-tool find-tool check-required-params validate-invocation execute-mock-tool dispatch-call]
  :i [(protocol :a proto)])

(dfs ToolRegistry
  (:f tools (List proto/ToolDef) "List of registered tool definitions"))

(df register-tool [(reg ToolRegistry) (tool proto/ToolDef)] -> ToolRegistry
  :d "Appends a new tool definition to the registry."
  (ToolRegistry :tools (list-cons tool (.-tools reg))))

(df find-tool [(reg ToolRegistry) (name Str)] -> (Option proto/ToolDef)
  :d "Finds a registered tool definition by name."
  (let [(matches (filter (fn [(t proto/ToolDef)] -> Bool (= (.-name t) name)) (.-tools reg)))]
    (list-head matches)))

(df check-required-params [(params (List proto/ToolParam)) (args (List proto/ToolArg))] -> (Option Str)
  :d "Checks if any required parameter is missing from args, returning missing parameter name."
  (let [(missing (filter (fn [(p proto/ToolParam)] -> Bool
                           (and (.-required p)
                                (mt (proto/get-arg-value args (.-name p))
                                  ((none) true)
                                  ((some _) false))))
                         params))]
    (mt (list-head missing)
      ((none) (none))
      ((some p) (some (.-name p))))))

(df validate-invocation [(reg ToolRegistry) (inv proto/ToolInvocation)] -> (Result proto/ToolInvocation Str)
  :d "Validates that target tool exists and all required parameters are provided."
  (mt (find-tool reg (.-tool-name inv))
    ((none) (err (str "Unknown tool: " (.-tool-name inv))))
    ((some tdef)
     (mt (check-required-params (.-params tdef) (.-args inv))
       ((some missing-param)
        (err (str "Missing required argument: " missing-param)))
       ((none) (ok inv))))))

(df execute-mock-tool [(inv proto/ToolInvocation)] -> proto/ToolResult
  :d "Executes standard tools or falls back to mock echo response."
  (let [(tname (.-tool-name inv))
        (args (.-args inv))]
    (cond
      ((= tname "search")
       (let [(q (option-or (proto/get-arg-value args "q")
                           (option-or (proto/get-arg-value args "query") "")))
             (limit (option-or (proto/get-arg-value args "limit") "5"))]
         (proto/ToolResult
           :tool-name tname
           :success true
           :output (str "Found 3 results for query "" q "" (limit " limit "): [ASL Docs, Prelude Spec, Benchmarks]")
           :error-msg "")))
      ((= tname "fetch")
       (let [(url (option-or (proto/get-arg-value args "url") ""))]
         (if (string-empty? url)
             (proto/ToolResult
               :tool-name tname
               :success false
               :output ""
               :error-msg "URL parameter is empty")
             (proto/ToolResult
               :tool-name tname
               :success true
               :output (str "Document fetched from " url ": 200 OK")
               :error-msg ""))))
      ((= tname "mem-recall")
       (let [(q (option-or (proto/get-arg-value args "query") ""))]
         (proto/ToolResult
           :tool-name tname
           :success true
           :output (str "Memory vector match for "" q "" with similarity 0.94")
           :error-msg "")))
      (:else
       (proto/ToolResult
         :tool-name tname
         :success true
         :output (str "Executed tool " tname " successfully")
         :error-msg "")))))

(df dispatch-call [(reg ToolRegistry) (raw-call Str)] -> Str
  :d "Parses, validates, executes, and formats an ASL S-expression tool call."
  (mt (proto/parse-invocation raw-call)
    ((err parse-err)
     (proto/format-result
       (proto/ToolResult
         :tool-name "unknown"
         :success false
         :output ""
         :error-msg parse-err)))
    ((ok inv)
     (mt (validate-invocation reg inv)
       ((err val-err)
        (proto/format-result
          (proto/ToolResult
            :tool-name (.-tool-name inv)
            :success false
            :output ""
            :error-msg val-err)))
       ((ok valid-inv)
        (let [(res (execute-mock-tool valid-inv))]
          (proto/format-result res)))))))
