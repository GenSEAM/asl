(module asl/agentLoop/nativeTools
  :x [validTools? systemHint ShapeParam ShapeTool shapeTool toolSpecs stepToolSpec callForm callsText]
  :i [(asl-json/json :a j) (asl/agentLoop/core :a c)])

; (:m :ref PROTO-STUDY :do "opt-in native tool calling: :tools ops offers one function per op shape (the same grammar the text protocol prints), :tools step offers one step(form) function; every tool_call maps back to the ASN form the text protocol would have carried, so the loop after the reply is unchanged; off (empty) sends no tools")
fn validTools? v: String -> Bool
  (listContains? (list "" "off" "ops" "step") v)

; (:m :do "one line after the system prompt when tools are on, so the reply contract names the channel; off adds nothing")
fn systemHint v: String -> String
  (if (or (= v "ops") (= v "step")) "\n(:reply :via tools :use \"call the tools; each call is one op; no prose\")" "")

(schema ShapeParam
  (:f key String)
  (:f kind String)
  (:f required Bool))

(schema ShapeTool
  (:f name String)
  (:f step Bool)
  (:f shape String)
  (:f params (List ShapeParam)))

fn intPlaceholder? v: String -> Bool
  (listContains? (list "n" "m" "i" "sec") v)

fn stripBrackets t: String -> String
  (stringReplace (stringReplace (stringReplace t "[" "") "]" "") ")" "")

; (:m :do "a shape token list is :key placeholder pairs, a [ opens an optional run and a ] closes it; a shape with nested forms or | alternatives in a key position is not offered")
fn paramsLoop toks: (List String) opt: Bool acc: (List ShapeParam) -> (Option (List ShapeParam))
  (if (listEmpty? toks) (some (listReverse acc))
    (let [t (c/firstOf toks)
          rest (c/restOf toks)
          opens (stringStartsWith? t "[")
          optNow (or opt opens)
          key (stripBrackets t)]
      (cond
        ((stringContains? t "(") none)
        ((not (stringStartsWith? key ":")) (paramsLoop rest optNow acc))
        ((listEmpty? rest) none)
        (else
          (let [v (c/firstOf rest)
                closes (stringContains? v "]")
                kind (if (intPlaceholder? (stripBrackets v)) "integer" "string")]
            (if (stringContains? v "(") none
              (paramsLoop (c/restOf rest) (and optNow (not closes))
                (cons (ShapeParam :key (optionOr (stringSlice key 1 (stringLength key)) key) :kind kind :required (not optNow)) acc))))))))

fn shapeTool shape: String -> (Option ShapeTool)
  (let [body (stringTrim shape)
        inner (optionOr (stringSlice body 1 (stringLength body)) "")
        toks (filter (fn [t] (not (stringEmpty? t))) (stringSplit inner " "))]
    (if (listEmpty? toks) none
      (let [head (c/firstOf toks)]
        (if (= head ":step")
          (let [rest (c/restOf toks)]
            (if (or (listEmpty? rest) (not (= (c/firstOf rest) ":op"))) none
              (let [nameTok (optionOr (listHead (c/restOf rest)) "")
                    name (stripBrackets (stringReplace nameTok "\"" ""))]
                (match (paramsLoop (c/restOf (c/restOf rest)) false (list))
                  ((some ps) (some (ShapeTool :name name :step true :shape shape :params ps)))
                  ((none) none)))))
          (match (paramsLoop (c/restOf toks) false (list))
            ((some ps) (some (ShapeTool :name (stripBrackets (optionOr (stringSlice head 1 (stringLength head)) "")) :step false :shape shape :params ps)))
            ((none) none))))))

fn paramSchema p: ShapeParam -> (Pair String j/Json)
  (pair p.key (j/jobj (list (pair "type" (j/jstr p.kind)))))

fn toolJson t: ShapeTool -> j/Json
  (j/jobj (list (pair "type" (j/jstr "function"))
    (pair "function" (j/jobj (list (pair "name" (j/jstr t.name))
      (pair "description" (j/jstr t.shape))
      (pair "parameters" (j/jobj (list (pair "type" (j/jstr "object"))
        (pair "properties" (j/jobj (map paramSchema t.params)))
        (pair "required" (j/jarr (map (fn [p] (j/jstr p.key)) (filter (fn [p] p.required) t.params))))))))))))

fn someOf xs: (List (Option T)) -> (List T)
  (fold (fn [acc o] (match o ((some v) (listAppend acc (list v))) ((none) acc))) (list) xs)

fn toolsOf shapes: (List String) -> (List ShapeTool)
  (someOf (map shapeTool shapes))

; (:m :do "one function per offered op shape; names stay the op names so a call reads back as (:step :op name ...)")
fn toolSpecs shapes: (List String) -> (List j/Json)
  (map toolJson (toolsOf shapes))

fn stepToolSpec -> j/Json
  (j/jobj (list (pair "type" (j/jstr "function"))
    (pair "function" (j/jobj (list (pair "name" (j/jstr "step"))
      (pair "description" (j/jstr "run one or more ASN forms, e.g. (:step :op \"read\" :file \"a.asl\" :symbol \"f\") or (:done)"))
      (pair "parameters" (j/jobj (list (pair "type" (j/jstr "object"))
        (pair "properties" (j/jobj (list (pair "form" (j/jobj (list (pair "type" (j/jstr "string"))))))))
        (pair "required" (j/jarr (list (j/jstr "form"))))))))))))

fn rawNeeded? s: String -> Bool
  (or (stringContains? s "\n") (or (stringContains? s "\"") (stringContains? s "\\")))

fn valueText v: j/Json -> String
  (match v
    ((j/jstr s) s)
    ((j/jint i) (stringFromInt64 i))
    ((j/jnum f) (j/jsonEmit v))
    ((j/jfloat f) (j/jsonEmit v))
    ((j/jbool b) (if b "true" "false"))
    (_ (j/jsonEmit v)))

fn intValue? v: j/Json -> Bool
  (match v ((j/jint _) true) (_ false))

; (:m :do "multi-line or quoted strings go out as :raw keys with fenced blocks after the form, in key order, which is how bindRawBlocks reads a text reply; everything else is an inline quoted or integer value")
fn argPieces kvs: (List (Pair String j/Json)) inline: (List String) blocks: (List String) -> (Pair (List String) (List String))
  (if (listEmpty? kvs) (pair inline blocks)
    (let [kv (c/firstOf kvs)
          k (pairFirst kv)
          v (pairSecond kv)
          s (valueText v)]
      (cond
        ((= k "op") (argPieces (c/restOf kvs) inline blocks))
        ((intValue? v) (argPieces (c/restOf kvs) (listAppend inline (list (str ":" k " " s))) blocks))
        ((rawNeeded? s) (argPieces (c/restOf kvs) (listAppend inline (list (str ":" k " :raw"))) (listAppend blocks (list (str "```\n" s (if (stringEndsWith? s "\n") "" "\n") "```")))))
        (else (argPieces (c/restOf kvs) (listAppend inline (list (str ":" k " \"" (c/escapeAsn s) "\""))) blocks)))))

fn argsObject args: String -> (List (Pair String j/Json))
  (match (j/jsonParse (if (stringEmpty? (stringTrim args)) "{}" args))
    ((ok (j/jobj kvs)) kvs)
    (_ (list)))

; (:m :do "a step(form) call carries the form text itself; an op call names a step op or a terminal head (done, escalate); an unknown name still becomes a step so the loop rejects it with its usual unknown-op receipt")
fn callForm name: String args: String -> String
  (let [kvs (argsObject args)]
    (if (= name "step")
      (match (c/dictGet (map (fn [kv] (pair (pairFirst kv) (c/kvStr (valueText (pairSecond kv))))) kvs) "form")
        ((some (c/kvStr f)) f)
        (_ ""))
      (let [pieces (argPieces kvs (list) (list))
            terminal (listContains? (list "done" "escalate") name)
            head (if terminal (str "(:" name) (str "(:step :op \"" (c/escapeAsn name) "\""))
            inline (pairFirst pieces)
            form (str head (if (listEmpty? inline) "" (str " " (c/joinSep inline " "))) ")")
            blocks (pairSecond pieces)]
        (if (listEmpty? blocks) form (str form "\n" (c/joinSep blocks "\n"))))))

fn callOf call: j/Json -> String
  (let [fnObj (optionOr (j/jsonGet call "function") (j/jobj (list)))
        name (match (j/jsonGet fnObj "name") ((some (j/jstr s)) s) (_ ""))
        args (match (j/jsonGet fnObj "arguments") ((some (j/jstr s)) s) ((some (j/jobj kvs)) (j/jsonEmit (j/jobj kvs))) (_ ""))]
    (if (stringEmpty? name) "" (callForm name args)))

; (:m :do "the reply text a native-tools turn hands to the parser: the forms of every tool call in order, after any text content the model also sent")
fn callsText content: String calls: (List j/Json) -> String
  (let [forms (filter (fn [s] (not (stringEmpty? s))) (map callOf calls))]
    (cond
      ((listEmpty? forms) content)
      ((stringEmpty? (stringTrim content)) (c/joinSep forms "\n"))
      (else (str content "\n" (c/joinSep forms "\n")))))
