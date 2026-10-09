(module asl-help/toolDescriptor
  :x [ToolParameter ToolDescriptor makeToolParameter makeToolDescriptor formatToolCompact formatToolDeep compactTokenCost deepTokenCost]
  :i [(asl-text/text :a txt)])

schema ToolParameter
  name: Str  ptype: Str  required: Bool  desc: Str
schema ToolDescriptor
  name: Str  contract: Str  signature: Str  summary: Str  situations: (List Str)  parameters: (List ToolParameter)  returns: Str  whenToUse: Str  whenNotToUse: Str  failureModes: (List Str)  example: Str
fn makeToolParameter name: Str ptype: Str required: Bool desc: Str -> ToolParameter
  (ToolParameter :name name :ptype ptype :required required :desc desc)

fn makeToolDescriptor name: Str contract: Str signature: Str summary: Str situations: (List Str) parameters: (List ToolParameter) returns: Str whenToUse: Str whenNotToUse: Str failureModes: (List Str) example: Str -> ToolDescriptor
  (ToolDescriptor
    :name name
    :contract contract
    :signature signature
    :summary summary
    :situations situations
    :parameters parameters
    :returns returns
    :whenToUse whenToUse
    :whenNotToUse whenNotToUse
    :failureModes failureModes
    :example example)

fn formatStringList items: (List Str) -> Str
  (if (listEmpty? items)
    "()"
    (str "(" (stringJoin (map (fn [(s Str)] -> Str (str "\"" s "\"")) items) " ") ")"))

fn formatParameter p: ToolParameter -> Str
  (str "(:param :name \"" p.name "\" :type \"" p.ptype "\" :required " (if p.required "true" "false") " :desc \"" p.desc "\")")

fn formatParameters params: (List ToolParameter) -> Str
  (if (listEmpty? params)
    "()"
    (str "(" (stringJoin (map (fn [(p ToolParameter)] -> Str (formatParameter p)) params) " ") ")"))

fn formatToolCompact td: ToolDescriptor -> Str
  (str "(:tool :name \"" td.name "\" :contract \"" td.contract "\" :signature \"" td.signature "\" :summary \"" td.summary "\" :situations " (formatStringList td.situations) ")")

fn formatToolDeep td: ToolDescriptor -> Str
  (str "(:tool-descriptor :name \"" td.name "\" :contract \"" td.contract "\" :signature \"" td.signature "\" :summary \"" td.summary "\" :situations " (formatStringList td.situations) " :parameters " (formatParameters td.parameters) " :returns \"" td.returns "\" :whenToUse \"" td.whenToUse "\" :whenNotToUse \"" td.whenNotToUse "\" :failureModes " (formatStringList td.failureModes) " :example \"" td.example "\")")

fn compactTokenCost td: ToolDescriptor -> I64
  (/ (+ (stringLength td.name) (+ (stringLength td.contract) (+ (stringLength td.signature) (stringLength td.summary)))) 4)

fn deepTokenCost td: ToolDescriptor -> I64
  (/ (+ (stringLength td.name) (+ (stringLength td.contract) (+ (stringLength td.whenToUse) (+ (stringLength td.whenNotToUse) (stringLength td.example))))) 4)
