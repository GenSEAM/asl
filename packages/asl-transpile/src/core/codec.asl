(module asl-transpile/core :x [JsonValue JsonEntry makeKv renderJson renderEntry renderJsonArray renderJsonObject mapItems mapEntries projectLens emitMultilensBundle] :i [(asl-transpile/multilens :a ml)])

(schema JsonEntry (:f key String) (:f val JsonValue))

(enum JsonValue (:c jsonNull [] "Null JSON literal") (:c jsonBool [(b Bool)] "Boolean JSON value") (:c jsonInt [(n Int64)] "64-bit signed integer value") (:c jsonFloat [(f Float64)] "64-bit floating point value") (:c jsonStr [(s String)] "UTF-8 string value") (:c jsonArr [(items (List JsonValue))] "Ordered array of JSON values") (:c jsonObj [(entries (List JsonEntry))] "Key-value JSON object"))

fn makeKv k: String v: JsonValue -> JsonEntry
  (JsonEntry :key k :val v)

fn renderEntry e: JsonEntry -> String
  (str "\"" e.key "\":" (renderJson e.val))

fn wrapDelimited open: String items: (List String) close: String -> String
  (str open (stringJoin items ",") close)

fn mapItems items: (List JsonValue) -> (List String)
  (map (fn [item] (renderJson item)) items)

fn mapEntries entries: (List JsonEntry) -> (List String)
  (map (fn [e] (renderEntry e)) entries)

fn renderJsonArray items: (List JsonValue) -> String
  (wrapDelimited "[" (mapItems items) "]")

fn renderJsonObject entries: (List JsonEntry) -> String
  (wrapDelimited "{" (mapEntries entries) "}")

fn renderJson v: JsonValue -> String
  (mt v ((jsonNull) "null") ((jsonBool b) (if b "true" "false")) ((jsonInt n) (stringFromInt64 n)) ((jsonFloat f) (stringFromFloat64 f)) ((jsonStr s) (str "\"" s "\"")) ((jsonArr arr) (renderJsonArray arr)) ((jsonObj obj) (renderJsonObject obj)))

fn projectLens lens: String model: ml/MultilensModel opts: ml/LensOptions -> ml/LensResult
  (ml/projectLens lens model opts)

fn emitMultilensBundle model: ml/MultilensModel lenses: (List String) opts: ml/LensOptions -> ml/MultilensBundle
  (ml/emitMultilensBundle model lenses opts)
