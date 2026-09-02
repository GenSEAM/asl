(module asl-codec/core
  :d "Zero-Cost Native JSON Serializer and Algebraic Value Representation for AgentScript."
  :x [JsonValue JsonEntry make-kv render-json render-entry render-json-array render-json-object
           map-items map-entries])

(dfs JsonEntry
  (:f key String "Object key")
  (:f val JsonValue "Object value"))

(dfe JsonValue
  (:c json-null  [] "Null JSON literal")
  (:c json-bool  [(b Bool)] "Boolean JSON value")
  (:c json-int   [(n Int64)] "64-bit signed integer value")
  (:c json-float [(f Float64)] "64-bit floating point value")
  (:c json-str   [(s String)] "UTF-8 string value")
  (:c json-arr   [(items (List JsonValue))] "Ordered array of JSON values")
  (:c json-obj   [(entries (List JsonEntry))] "Key-value JSON object"))

(df make-kv [(k String) (v JsonValue)] -> JsonEntry
  :d "Constructs a key-value JsonEntry."
  (JsonEntry :key k :val v))

(df render-entry [(e JsonEntry)] -> String
  :d "Renders a key-value entry to JSON pair string."
  (str "\"" (.-key e) "\":" (render-json (.-val e))))

(df wrap-delimited [(open String) (items (List String)) (close String)] -> String
  :d "Joins items with commas and encloses in delimiters."
  (str open (string-join items ",") close))

(df map-items [(items (List JsonValue))] -> (List String)
  :d "Maps array items to rendered strings."
  (map (fn [item] (render-json item)) items))

(df map-entries [(entries (List JsonEntry))] -> (List String)
  :d "Maps object entries to rendered strings."
  (map (fn [e] (render-entry e)) entries))

(df render-json-array [(items (List JsonValue))] -> String
  :d "Renders a list of JSON values into a JSON array string."
  (wrap-delimited "[" (map-items items) "]"))

(df render-json-object [(entries (List JsonEntry))] -> String
  :d "Renders object entries into a JSON object string."
  (wrap-delimited "{" (map-entries entries) "}"))

(df render-json [(v JsonValue)] -> String
  :d "Recursively renders algebraic JsonValue to valid JSON string."
  (mt v
    ((json-null)    "null")
    ((json-bool b)  (if b "true" "false"))
    ((json-int n)   (string-from-int64 n))
    ((json-float f) (string-from-float64 f))
    ((json-str s)   (str "\"" s "\""))
    ((json-arr arr) (render-json-array arr))
    ((json-obj obj) (render-json-object obj))))
