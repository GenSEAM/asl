(module aslGateway/modelWindows
  :x [Window WindowRow contextFields maxOutFields itemWindow listedWindows windowRows defaultContextCap capOfConfigText windowsReportText windowsPatchText]
  :i [(aslGateway/config :a c)
      (asl-json/json :a j)])

; (:m :ref MODELS-CTX-SYNC :do "context window and max output of every model a provider's /models lists, read where the payload carries them; the field names live in the two tables below and nowhere else, a payload with none of them yields no window and the config row stays as it is")
(schema Window
  (:f context Int64)
  (:f maxOut Int64))

; (:m :do "one path per payload shape, first match wins: OpenRouter context_length, Vercel and AI-gateway context_window, vLLM and Together max_model_len, Gemini inputTokenLimit")
fn contextFields -> (List (List String))
  (list (list "context_length") (list "context_window") (list "max_model_len") (list "inputTokenLimit") (list "top_provider" "context_length"))

; (:m :do "OpenRouter top_provider.max_completion_tokens, generic max_output_tokens and max_completion_tokens, Vercel max_tokens, Gemini outputTokenLimit")
fn maxOutFields -> (List (List String))
  (list (list "top_provider" "max_completion_tokens") (list "max_output_tokens") (list "max_completion_tokens") (list "max_tokens") (list "outputTokenLimit"))

fn pathAt v: j/Json path: (List String) -> (Option j/Json)
  (match (listHead path)
    ((none) (some v))
    ((some k) (match (j/jsonGet v k)
                ((none) none)
                ((some x) (pathAt x (optionOr (listTail path) (list)))))))

; (:m :do "a positive whole number from a JSON int, float or numeric string, 0 for anything else")
fn positive v: (Option j/Json) -> Int64
  (let [(n (match v
             ((some (j/jint i)) i)
             ((some (j/jnum f)) (optionOr (float64ToInt64 f) 0))
             ((some (j/jfloat f)) (optionOr (float64ToInt64 f) 0))
             ((some (j/jstr s)) (optionOr (stringToInt64 (stringTrim s)) 0))
             (_ 0)))]
    (if (> n 0) n 0))

fn firstPositive item: j/Json fields: (List (List String)) -> Int64
  (fold (fn [(acc Int64) (p (List String))] -> Int64 (if (> acc 0) acc (positive (pathAt item p)))) 0 fields)

fn itemWindow item: j/Json -> Window
  (Window :context (firstPositive item (contextFields)) :maxOut (firstPositive item (maxOutFields)))

fn itemsOf body: j/Json -> (List j/Json)
  (match body
    ((j/jarr xs) xs)
    (_ (match (j/jsonGet body "data") ((some (j/jarr xs)) xs) (_ (match (j/jsonGet body "models") ((some (j/jarr ys)) ys) (_ (list)))))))

fn idOf item: j/Json -> String
  (let [(raw (match (j/jsonGet item "id") ((some (j/jstr s)) s) (_ (match (j/jsonGet item "name") ((some (j/jstr s2)) s2) (_ "")))))]
    (if (stringStartsWith? raw "models/") (optionOr (stringSlice raw 7 (stringLength raw)) "") raw))

; (:m :do "(id window) for every listed item with an id; an item without either field has window 0 0")
fn listedWindows text: String -> (Result (List (Pair String Window)) String)
  (match (j/jsonParse text)
    ((err e) (err (str "ERR_MODELS_JSON: " e)))
    ((ok body)
      (ok (filter (fn [(p (Pair String Window))] -> Bool (not (stringEmpty? (pairFirst p))))
            (map (fn [(it j/Json)] -> (Pair String Window) (pair (idOf it) (itemWindow it))) (itemsOf body))))))

; (:m :do "per config alias of the provider: the listed window and max output next to the configured :contextBudget and :maxTokens (-1 when the row has none), and the values apply would write, -1 for no change; status is ok when a change is proposed, same when the row already matches, unlisted when the provider list does not name the model, nofield when it names it without a window")
(schema WindowRow
  (:f alias String)
  (:f provider String)
  (:f name String)
  (:f listedContext Int64)
  (:f listedMaxOut Int64)
  (:f cfgBudget Int64)
  (:f cfgMaxTokens Int64)
  (:f newBudget Int64)
  (:f newMaxTokens Int64)
  (:f status String))

fn defaultContextCap -> Int64
  200000

; (:m :do "the cap comes from a top-level :contextCap number in the config text when present, else the default; a flag wins over both in the CLI")
fn capOfConfigText cfgText: String -> Int64
  (match (stringIndexOf cfgText ":contextCap ")
    ((none) (defaultContextCap))
    ((some i)
      (let [(rest (optionOr (stringSlice cfgText (+ i 12) (stringLength cfgText)) ""))
            (tok (optionOr (listHead (stringSplit (stringReplace (stringReplace rest ")" " ") "\n" " ") " ")) ""))
            (n (optionOr (stringToInt64 tok) 0))]
        (if (> n 0) n (defaultContextCap)))))

fn rowFor table: c/GatewayTable provider: String listed: (List (Pair String Window)) cap: Int64 alias: String -> (Option WindowRow)
  (match (mapGet table.models alias)
    ((none) (none))
    ((some m)
      (if (!= m.provider provider)
        (none)
        (let [(cfgB (optionOr m.params.contextBudget -1))
              (cfgM (optionOr m.params.maxTokens -1))
              (hit (listHead (filter (fn [(p (Pair String Window))] -> Bool (= (pairFirst p) m.name)) listed)))]
          (match hit
            ((none) (some (WindowRow :alias alias :provider provider :name m.name :listedContext 0 :listedMaxOut 0 :cfgBudget cfgB :cfgMaxTokens cfgM :newBudget -1 :newMaxTokens -1 :status "unlisted")))
            ((some p)
              (let [(w (pairSecond p))
                    (target (if (> w.context 0) (if (< w.context cap) w.context cap) -1))
                    (newB (if (and (> target 0) (!= target cfgB)) target -1))
                    (newM (if (and (> w.maxOut 0) (and (> cfgM 0) (> cfgM w.maxOut))) w.maxOut -1))
                    (st (cond ((and (= w.context 0) (= w.maxOut 0)) "nofield")
                              ((or (> newB 0) (> newM 0)) "ok")
                              (else "same")))]
                (some (WindowRow :alias alias :provider provider :name m.name :listedContext w.context :listedMaxOut w.maxOut :cfgBudget cfgB :cfgMaxTokens cfgM
                        :newBudget newB :newMaxTokens newM :status st)))))))))

; (:m :do "one row per config alias of the provider, in config order; aliases of another provider are not rows")
fn windowRows table: c/GatewayTable provider: String listed: (List (Pair String Window)) cap: Int64 -> (List WindowRow)
  (listFlatMap (fn [(a String)] -> (List WindowRow) (match (rowFor table provider listed cap a) ((some r) (list r)) ((none) (list)))) table.modelOrder)

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn n v: Int64 -> String
  (stringFromInt64 v)

fn rowText r: WindowRow -> String
  (str "(:window :alias " r.alias " :provider " r.provider " :name " (q r.name) " :listedContext " (n r.listedContext) " :listedMaxOut " (n r.listedMaxOut)
       " :contextBudget " (n r.cfgBudget) " :maxTokens " (n r.cfgMaxTokens) " :newBudget " (n r.newBudget) " :newMaxTokens " (n r.newMaxTokens) " :status " r.status ")")

; (:m :do "the report: every row, rows the provider list did not cover included, with the cap that was applied")
fn windowsReportText date: String cap: Int64 rows: (List WindowRow) -> String
  (str "(:windows :date " date " :cap " (n cap) "\n  :rows (" (stringJoin (map rowText rows) "\n         ") "))\n")

; (:m :do "a models apply patch in the SUB-PACE shape (an empty :spreads selects it, :host guards the machine): one :models row per field to change, which models apply writes with its backup and config check")
fn windowsPatchText id: String host: String rows: (List WindowRow) -> String
  (str "(:patch :id " id " :host " host " :spreads ()\n  :models ("
       (stringJoin (listFlatMap (fn [(r WindowRow)] -> (List String)
                                  (listAppend (if (> r.newBudget 0) (list (str "(:set :model " r.alias " :contextBudget " (n r.newBudget) ")")) (list))
                                              (if (> r.newMaxTokens 0) (list (str "(:set :model " r.alias " :maxTokens " (n r.newMaxTokens) ")")) (list))))
                                rows) "\n           ")
       "))\n")
