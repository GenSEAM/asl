(module aslHarness/toolcall :x [OpenAiTool OpenAiToolCall toolToOpenaiSchema parseOpenaiToolCall formatAsnToolCall asnCallToOpenaiJson toolsToOpenaiJson RpcAgentPolicy defaultAgentToolPolicy agentRpcDescription rpcOperationForCommand allCommandsRpcMapped? agentToolsToOpenaiJson enforceAgentToolCall] :i [(coding :a c)])

(schema OpenAiTool (:f toolType Str) (:f name Str) (:f description Str) (:f parametersJson Str))

(schema OpenAiToolCall (:f id Str) (:f functionName Str) (:f argumentsJson Str))

(schema RpcAgentPolicy (:f rpcDescriptionVisible Bool) (:f commandDescriptionVisible Bool) (:f allCommandsMapped Bool) (:f batchRequired Bool))

fn defaultAgentToolPolicy -> RpcAgentPolicy
  (RpcAgentPolicy :rpcDescriptionVisible true :commandDescriptionVisible false :allCommandsMapped true :batchRequired true)

fn agentRpcDescription -> Str
  "RPC operation descriptions are available from asl/grammar/rpc.asn. Use the rpc_batch function with one or more operation IDs and payloads; direct command descriptions are intentionally unavailable."

fn rpcOperationForCommand commandName: Str -> Str
  (cond ((= commandName "fs-read") "asl-intel-read") ((= commandName "fs-write") "asl-mem-write") ((= commandName "fs-list") "asl-intel-ls") ((= commandName "exec-cmd") "asl-exec") ((= commandName "ast-search") "asl-intel-ast") ((= commandName "intel-query") "asl-engine") ((= commandName "git-status") "asl-git") ((= commandName "ast-patch") "asl-mem-patch") ((= commandName "str-replace") "asl-mem-edit") ((= commandName "intel-preload") "asl-engine") ((= commandName "intel-impact") "asl-intel-impact") ((= commandName "intel-health") "asl-engine") ((= commandName "deps-resolve") "asl-engine") (else (if (stringEmpty? commandName) "" "asl-engine")))

fn allCommandsRpcMapped? tools: (List c/BuiltinTool) -> Bool
  (fold (fn [(mapped Bool) (tool c/BuiltinTool)] -> Bool (and mapped (not (stringEmpty? (rpcOperationForCommand tool.name))))) true tools)

fn agentToolsToOpenaiJson tools: (List c/BuiltinTool) -> Str
  (let [(mapped (allCommandsRpcMapped? tools)) (desc (stringReplace (agentRpcDescription) "\"" "\\\""))] (if (not mapped) "[]" (str "[{\"type\": \"function\", \"function\": {\"name\": \"rpc_batch\", \"description\": \"" desc "\", \"parameters\": {\"type\": \"object\", \"properties\": {\"operations\": {\"type\": \"array\", \"description\": \"RPC operation IDs and payloads executed as one batch\"}}, \"required\": [\"operations\"]}}}]")))

fn enforceAgentToolCall call: c/ToolCall -> c/ToolResult
  (if (= call.toolName "rpc-batch") (c/ToolResult :callId call.id :toolName call.toolName :success true :output "RPC batch accepted" :errorMsg "") (c/ToolResult :callId call.id :toolName call.toolName :success false :output "" :errorMsg "Direct command tools are unavailable; submit operations through rpc-batch"))

fn toolNameToJson name: Str -> Str
  (stringReplace name "-" "_")

fn jsonNameToTool name: Str -> Str
  (stringReplace name "_" "-")

fn mapAslTypeToJson t: Str -> Str
  (cond ((or (= t "Str") (= t "String")) "string") ((or (= t "I64") (or (= t "Int64") (or (= t "Int") (= t "i64")))) "integer") ((or (= t "F64") (or (= t "Float64") (or (= t "Float") (= t "f64")))) "number") ((or (= t "Bool") (= t "Boolean")) "boolean") ((or (= t "List") (= t "Array")) "array") ((or (= t "Map") (= t "Dict")) "object") (else "string"))

fn formatParamProp p: c/ToolParam -> Str
  (let [(pName (toolNameToJson p.name)) (jType (mapAslTypeToJson p.paramType)) (doc (stringReplace p.doc "\"" "\\\""))] (str "\"" pName "\": {\"type\": \"" jType "\", \"description\": \"" doc "\"}"))

fn formatProperties params: (List c/ToolParam) -> Str
  (let [(propsList (map (fn [(p c/ToolParam)] -> Str (formatParamProp p)) params))] (stringJoin propsList ", "))

fn extractRequiredFields params: (List c/ToolParam) -> Str
  (let [(reqParams (filter (fn [(p c/ToolParam)] -> Bool p.required) params)) (reqNames (map (fn [(p c/ToolParam)] -> Str (str "\"" (toolNameToJson p.name) "\"")) reqParams))] (str "[" (stringJoin reqNames ", ") "]"))

fn toolToOpenaiSchema tool: c/BuiltinTool -> OpenAiTool
  (let [(fnName (toolNameToJson tool.name)) (desc (stringReplace tool.description "\"" "\\\"")) (params tool.params) (props (formatProperties params)) (req (extractRequiredFields params)) (schema (str "{\"type\": \"object\", \"properties\": {" props "}, \"required\": " req "}"))] (OpenAiTool :toolType "function" :name fnName :description desc :parametersJson schema))

fn toolsToOpenaiJson tools: (List c/BuiltinTool) -> Str
  (let [(schemas (map (fn [(t c/BuiltinTool)] -> OpenAiTool (toolToOpenaiSchema t)) tools)) (entries (map (fn [(s OpenAiTool)] -> Str (str "{\"type\": \"function\", \"function\": {\"name\": \"" s.name "\", \"description\": \"" s.description "\", \"parameters\": " s.parametersJson "}}")) schemas))] (str "[" (stringJoin entries ", ") "]"))

fn formatAsnToolCall toolName: Str args: (List (Pair Str Str)) -> Str
  (let [(argsStr (fold (fn [(acc Str) (p (pair Str Str))] -> Str (str acc ":" (pairFirst p) " \"" (pairSecond p) "\" ")) "" args))] (str "(:call :tool \"" toolName "\" " (stringTrim argsStr) ")"))

fn parseJsonPair entry: Str -> (Option (Pair Str Str))
  (let [(colonIdx (stringIndexOf entry ":"))] (mt colonIdx ((none) (none)) ((some idx) (let [(rawK (optionOr (stringSlice entry 0 idx) "")) (rawV (optionOr (stringSlice entry (+ idx 1) (stringLength entry)) "")) (cleanK (jsonNameToTool (stringReplace (stringTrim rawK) "\"" ""))) (trimmedV (stringTrim rawV)) (cleanV (if (and (stringStartsWith? trimmedV "\"") (stringEndsWith? trimmedV "\"")) (optionOr (stringSlice trimmedV 1 (- (stringLength trimmedV) 1)) "") trimmedV))] (if (stringEmpty? cleanK) (none) (some (pair cleanK cleanV)))))))

fn parseJsonArguments jsonStr: Str -> (List (Pair Str Str))
  (let [(trimmed (stringTrim jsonStr))] (if (or (stringEmpty? trimmed) (= trimmed "{}")) (list) (let [(inner (if (and (stringStartsWith? trimmed "{") (stringEndsWith? trimmed "}")) (optionOr (stringSlice trimmed 1 (- (stringLength trimmed) 1)) "") trimmed)) (parts (stringSplit inner ",")) (parsed (fold (fn [(acc (List (pair Str Str))) (part Str)] -> (List (Pair Str Str)) (let [(maybeP (parseJsonPair part))] (mt maybeP ((none) acc) ((some p) (listAppend acc (list p)))))) (list) parts))] (if (listEmpty? parsed) (list (pair "raw-json" jsonStr)) parsed))))

fn parseOpenaiToolCall call: OpenAiToolCall -> c/ToolCall
  (let [(canonicalName (jsonNameToTool call.functionName)) (parsedArgs (parseJsonArguments call.argumentsJson))] (c/ToolCall :id call.id :toolName canonicalName :arguments parsedArgs))

fn asnCallToOpenaiJson call: c/ToolCall -> Str
  (let [(fnName (toolNameToJson call.toolName)) (args call.arguments) (argsPairs (map (fn [(p (pair Str Str))] -> Str (str "\"" (toolNameToJson (pairFirst p)) "\": \"" (stringReplace (pairSecond p) "\"" "\\\"") "\"")) args)) (argsInner (stringJoin argsPairs ", ")) (argsJson (str "{" (stringReplace (stringReplace argsInner "\\" "\\\\") "\"" "\\\"") "}"))] (str "{\"id\": \"" call.id "\", \"type\": \"function\", \"function\": {\"name\": \"" fnName "\", \"arguments\": \"" argsJson "\"}}"))
