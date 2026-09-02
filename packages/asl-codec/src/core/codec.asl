(module asl-codec/core
  :doc "Zero-Cost Native JSON Serializer and Algebraic Value Representation for AgentScript."
  :export [JsonValue JsonEntry make-kv render-json render-entry render-json-array render-json-object])

(defschema JsonEntry
  (:field key String "Object key")
  (:field val JsonValue "Object value"))

(defenum JsonValue
  (:case json-null  [] "Null JSON literal")
  (:case json-bool  [(b Bool)] "Boolean JSON value")
  (:case json-int   [(n Int64)] "64-bit signed integer value")
  (:case json-float [(f Float64)] "64-bit floating point value")
  (:case json-str   [(s String)] "UTF-8 string value")
  (:case json-arr   [(items (List JsonValue))] "Ordered array of JSON values")
  (:case json-obj   [(entries (List JsonEntry))] "Key-value JSON object"))

(defun make-kv [(k String) (v JsonValue)] -> JsonEntry
  :doc "Constructs a key-value JsonEntry."
  (JsonEntry :key k :val v))

(defun render-entry [(e JsonEntry)] -> String
  :doc "Renders a key-value entry to JSON pair string."
  (str "\"" (.-key e) "\":" (render-json (.-val e))))

(defun wrap-delimited [(open String) (items (List String)) (close String)] -> String
  :doc "Joins items with commas and encloses in delimiters."
  (str open (string-join items ",") close))

(defun render-json-array [(items (List JsonValue))] -> String
  :doc "Renders a list of JSON values into a JSON array string."
  (wrap-delimited "[" (map (fn [item] (render-json item)) items) "]"))

(defun render-json-object [(entries (List JsonEntry))] -> String
  :doc "Renders object entries into a JSON object string."
  (wrap-delimited "{" (map (fn [e] (render-entry e)) entries) "}"))

(defun render-json [(v JsonValue)] -> String
  :doc "Recursively renders algebraic JsonValue to valid JSON string."
  (match v
    ((json-null)    "null")
    ((json-bool b)  (if b "true" "false"))
    ((json-int n)   (string-from-int64 n))
    ((json-float f) (string-from-float64 f))
    ((json-str s)   (str "\"" s "\""))
    ((json-arr arr) (render-json-array arr))
    ((json-obj obj) (render-json-object obj))))
