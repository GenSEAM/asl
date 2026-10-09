(module aslAgentCore/dispatch :x [ToolHandler ToolRegistry registerTool registerHandler findTool findHandler checkRequiredParams validateInvocation executeTool dispatchCall dispatchBatchCalls DispatchResult CanonicalAutonomy autonomyAsk autonomyGuarded autonomyAuto isCanonicalTool pathEscapes targetEscapesRoot dispatchCanonicalTool! dispatchCanonicalToolWithRegistry!] :i [(protocol :a proto)])

(schema ToolHandler (:f name Str) (:f run (fn ! [proto/ToolInvocation] -> proto/ToolResult)))

(schema ToolRegistry (:f tools (List proto/ToolDef)) (:f handlers (List ToolHandler)))

(enum CanonicalAutonomy (:c autonomyAsk [] "Ask autonomy level") (:c autonomyGuarded [] "Guarded autonomy level") (:c autonomyAuto [] "Auto autonomy level"))

fn registerTool reg: ToolRegistry tool: proto/ToolDef -> ToolRegistry
  (with reg :tools (cons tool reg.tools))

fn registerHandler reg: ToolRegistry name: Str handler: (fn ! [proto/ToolInvocation] -> proto/ToolResult) -> ToolRegistry
  (with reg :handlers (cons (ToolHandler :name name :run handler) reg.handlers))

fn findTool reg: ToolRegistry name: Str -> (Option proto/ToolDef)
  (let [(matches (filter (fn [(t proto/ToolDef)] -> Bool (= t.name name)) reg.tools))] (listHead matches))

fn checkRequiredParams params: (List proto/ToolParam) args: (List proto/ToolArg) -> (Option Str)
  (let [(missing (filter (fn [(p proto/ToolParam)] -> Bool (and p.required (mt (proto/getArgValue args p.name) ((none) true) ((some _) false)))) params))] (mt (listHead missing) ((none) (none)) ((some p) (some p.name))))

fn validateInvocation reg: ToolRegistry inv: proto/ToolInvocation -> (Result proto/ToolInvocation Str)
  (mt (findTool reg inv.toolName) ((none) (err (str "Unknown tool: " inv.toolName))) ((some tdef) (mt (checkRequiredParams tdef.params inv.args) ((some missingParam) (err (str "Missing required argument: " missingParam))) ((none) (ok inv)))))

fn findHandler handlers: (List ToolHandler) name: Str -> (Option ToolHandler)
  (mt (listHead handlers) ((none) (none)) ((some handler) (if (= handler.name name) (some handler) (findHandler (optionOr (listTail handlers) (list)) name))))

fn executeTool reg: ToolRegistry inv: proto/ToolInvocation -> proto/ToolResult
  (let [(toolName inv.toolName)]
    (mt (findTool reg toolName)
      ((none) (proto/ToolResult :toolName toolName :success false :output "" :errorMsg (str "Unknown tool: " toolName)))
      ((some _) (mt (findHandler reg.handlers toolName)
        ((none) (proto/ToolResult :toolName toolName :success false :output "" :errorMsg (str "Missing handler: " toolName)))
        ((some handler) (handler.run inv))))))

fn dispatchCall reg: ToolRegistry rawCall: Str -> Str
  (mt (proto/parseInvocation rawCall) ((err parseErr) (proto/formatResult (proto/ToolResult :toolName "unknown" :success false :output "" :errorMsg parseErr))) ((ok inv) (mt (validateInvocation reg inv) ((err valErr) (proto/formatResult (proto/ToolResult :toolName inv.toolName :success false :output "" :errorMsg valErr))) ((ok validInv) (let [(res (executeTool reg validInv))] (proto/formatResult res))))))

fn dispatchBatchCalls reg: ToolRegistry calls: (List Str) -> (List Str)
  (map (fn [(rawCall Str)] -> Str (dispatchCall reg rawCall)) calls)

(schema DispatchResult (:f status Str) (:f success Bool) (:f output Str) (:f errorMsg Str))

fn isCanonicalTool toolName: Str -> Bool
  (or (= toolName "eddie-preload") (or (= toolName "ast-patch") (or (= toolName "eddie-health") (or (= toolName "deps-resolve") (or (= toolName "knowledge-load") (or (= toolName "knowledge-offload") (or (= toolName "intent-record") (or (= toolName "intent-query") (or (= toolName "trace-verify") (or (= toolName "exec-cmd") (= toolName "ptr-deref")))))))))))

fn pathEscapes segments: (List Str) depth: I64 -> Bool
  (if (listEmpty? segments) false (let [(segment (optionOr (listHead segments) "")) (remaining (optionOr (listTail segments) (list)))] (cond ((or (= segment "") (= segment ".")) (pathEscapes remaining depth)) ((= segment "..") (if (= depth 0) true (pathEscapes remaining (- depth 1)))) (else (pathEscapes remaining (+ depth 1))))))

fn targetEscapesRoot targetFile: Str -> Bool
  (or (stringStartsWith? targetFile "/") (pathEscapes (stringSplit targetFile "/") 0))

fn ! dispatchCanonicalTool! reg: ToolRegistry toolName: Str targetFile: Str payload: Str autonomy: CanonicalAutonomy -> DispatchResult
  (dispatchCanonicalToolWithRegistry! reg toolName targetFile payload (= autonomy (autonomyAuto)))

fn ! dispatchCanonicalToolWithRegistry! reg: ToolRegistry toolName: Str targetFile: Str payload: Str canExecute: Bool -> DispatchResult
  (if (not (isCanonicalTool toolName))
    (DispatchResult :status "unknown" :success false :output "" :errorMsg (str "Unknown canonical tool: " toolName))
    (if (targetEscapesRoot targetFile)
      (DispatchResult :status "denied" :success false :output "" :errorMsg (str "Target escapes workspace root: " targetFile))
      (if (stringEmpty? targetFile)
        (DispatchResult :status "error" :success false :output "" :errorMsg "Canonical tool target is required")
        (if (and (= toolName "exec-cmd") (not canExecute))
          (DispatchResult :status "denied" :success false :output "" :errorMsg "exec-cmd is not authorized")
          (let [(inv (proto/ToolInvocation :toolName toolName :args (list (proto/ToolArg :key "targetFile" :val targetFile) (proto/ToolArg :key "payload" :val payload)) :rawCall ""))]
            (mt (findHandler reg.handlers toolName)
              ((none) (DispatchResult :status "error" :success false :output "" :errorMsg (str "Missing handler: " toolName)))
              ((some handler) (let [(result (handler.run inv))]
                (if result.success
                  (DispatchResult :status "ok" :success true :output result.output :errorMsg "")
                  (DispatchResult :status "error" :success false :output "" :errorMsg result.errorMsg))))))))))
