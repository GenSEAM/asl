(module asl-codec/core
  :d "Zero-Cost Native JSON Serializer and Algebraic Value Representation for AgentScript."
  :x [JsonValue JsonEntry makeKv renderJson renderEntry renderJsonArray renderJsonObject
      mapItems mapEntries
      projectLens emitMultilensBundle]
  :i [(../multilens :a ml)])

(dfs JsonEntry
  (:f key String "Object key")
  (:f val JsonValue "Object value"))

(dfe JsonValue
  (:c jsonNull  [] "Null JSON literal")
  (:c jsonBool  [(b Bool)] "Boolean JSON value")
  (:c jsonInt   [(n Int64)] "64-bit signed integer value")
  (:c jsonFloat [(f Float64)] "64-bit floating point value")
  (:c jsonStr   [(s String)] "UTF-8 string value")
  (:c jsonArr   [(items (List JsonValue))] "Ordered array of JSON values")
  (:c jsonObj   [(entries (List JsonEntry))] "Key-value JSON object"))

(df makeKv [(k String) (v JsonValue)] -> JsonEntry
  :d "Constructs a key-value JsonEntry."
  (JsonEntry :key k :val v))

(df renderEntry [(e JsonEntry)] -> String
  :d "Renders a key-value entry to JSON pair string."
  (str "\"" (.-key e) "\":" (renderJson (.-val e))))

(df wrapDelimited [(open String) (items (List String)) (close String)] -> String
  :d "Joins items with commas and encloses in delimiters."
  (str open (string-join items ",") close))

(df mapItems [(items (List JsonValue))] -> (List String)
  :d "Maps array items to rendered strings."
  (map (fn [item] (renderJson item)) items))

(df mapEntries [(entries (List JsonEntry))] -> (List String)
  :d "Maps object entries to rendered strings."
  (map (fn [e] (renderEntry e)) entries))

(df renderJsonArray [(items (List JsonValue))] -> String
  :d "Renders a list of JSON values into a JSON array string."
  (wrapDelimited "[" (mapItems items) "]"))

(df renderJsonObject [(entries (List JsonEntry))] -> String
  :d "Renders object entries into a JSON object string."
  (wrapDelimited "{" (mapEntries entries) "}"))

(df renderJson [(v JsonValue)] -> String
  :d "Recursively renders algebraic JsonValue to valid JSON string."
  (mt v
    ((jsonNull)    "null")
    ((jsonBool b)  (if b "true" "false"))
    ((jsonInt n)   (string-from-int64 n))
    ((jsonFloat f) (string-from-float64 f))
    ((jsonStr s)   (str "\"" s "\""))
    ((jsonArr arr) (renderJsonArray arr))
    ((jsonObj obj) (renderJsonObject obj))))

(df projectLens [(lens String) (model ml/MultilensModel) (opts ml/LensOptions)] -> ml/LensResult
  :d "Top-level facade dispatching format projection through requested lens."
  (ml/projectLens lens model opts))

(df emitMultilensBundle [(model ml/MultilensModel) (lenses (List String)) (opts ml/LensOptions)] -> ml/MultilensBundle
  :d "Top-level facade emitting complete multilens bundle across formats."
  (ml/emitMultilensBundle model lenses opts))

