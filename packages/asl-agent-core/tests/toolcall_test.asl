(module asl-agent-core/toolcall-test
  :d "Unit tests for ASL S-expression tool calling protocol and dispatcher"
  :x [run-tests]
  :i [(protocol :a proto) (dispatch :a disp)])

(df sample-registry [] -> disp/ToolRegistry
  :d "Constructs sample registry with search and fetch tools."
  (let [(p-q (proto/ToolParam :name "q" :param-type "Str" :required true :doc "Search query string"))
        (p-limit (proto/ToolParam :name "limit" :param-type "I64" :required false :doc "Max results count"))
        (search-tool (proto/ToolDef :name "search" :doc "Web and ecosystem search" :params (list p-q p-limit)))
        (p-url (proto/ToolParam :name "url" :param-type "Str" :required true :doc "Target URL"))
        (fetch-tool (proto/ToolDef :name "fetch" :doc "HTTP document fetcher" :params (list p-url)))
        (empty-reg (disp/ToolRegistry :tools (list)))]
    (disp/register-tool (disp/register-tool empty-reg search-tool) fetch-tool)))

(df test-format-tool-def [] -> Bool
  :d "Verifies compact tool definition formatting."
  (let [(p-q (proto/ToolParam :name "q" :param-type "Str" :required true :doc "Search query"))
        (p-limit (proto/ToolParam :name "limit" :param-type "I64" :required false :doc "Max count"))
        (tdef (proto/ToolDef :name "search" :doc "Web search" :params (list p-q p-limit)))
        (spec (proto/format-tool-def tdef))]
    (and (string-contains? spec "(tool :search")
         (and (string-contains? spec ":q! Str")
              (string-contains? spec ":limit I64")))))

(df test-parse-invocation [] -> Bool
  :d "Verifies S-expression tokenizing and parsing into ToolInvocation."
  (let [(raw "(call :tool search :q \"agentscript language\" :limit 5)")
        (res (proto/parse-invocation raw))]
    (mt res
      ((err _) false)
      ((ok inv)
       (and (= (.-tool-name inv) "search")
            (and (= (option-or (proto/get-arg-value (.-args inv) "q") "") "agentscript language")
                 (= (option-or (proto/get-arg-value (.-args inv) "limit") "") "5")))))))

(df test-validate-invocation [] -> Bool
  :d "Verifies validation of required parameters and unknown tools."
  (let [(reg (sample-registry))
        (inv-valid (proto/ToolInvocation
                     :tool-name "search"
                     :args (list (proto/ToolArg :key "q" :val "test"))
                     :raw-call "(call :tool search :q \"test\")"))
        (inv-missing (proto/ToolInvocation
                       :tool-name "search"
                       :args (list (proto/ToolArg :key "limit" :val "10"))
                       :raw-call "(call :tool search :limit 10)"))
        (inv-unknown (proto/ToolInvocation
                       :tool-name "non-existent"
                       :args (list)
                       :raw-call "(call :tool non-existent)"))]
    (let [(res-valid (disp/validate-invocation reg inv-valid))
          (res-missing (disp/validate-invocation reg inv-missing))
          (res-unknown (disp/validate-invocation reg inv-unknown))]
      (and (mt res-valid ((ok _) true) ((err _) false))
           (and (mt res-missing ((ok _) false) ((err msg) (string-contains? msg "Missing required argument: q")))
                (mt res-unknown ((ok _) false) ((err msg) (string-contains? msg "Unknown tool: non-existent"))))))))

(df test-dispatch-call [] -> Bool
  :d "Verifies end-to-end execution of a valid tool call."
  (let [(reg (sample-registry))
        (raw "(call :tool search :q \"agentscript\" :limit 3)")
        (out (disp/dispatch-call reg raw))]
    (and (string-contains? out "(result :tool search :ok true")
         (string-contains? out "agentscript"))))

(df test-dispatch-error [] -> Bool
  :d "Verifies error response framing on invalid tool call."
  (let [(reg (sample-registry))
        (raw "(call :tool search :limit 5)")
        (out (disp/dispatch-call reg raw))]
    (and (string-contains? out "(result :tool search :ok false")
         (string-contains? out "Missing required argument: q"))))

(df run-tests [] -> Bool
  :d "Runs all asl-toolcall unit tests."
  (and (test-format-tool-def)
       (and (test-parse-invocation)
            (and (test-validate-invocation)
                 (and (test-dispatch-call)
                      (test-dispatch-error))))))
