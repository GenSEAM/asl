(module aslGateway/tests/structuredOutputTest
  :x [runTests]
  :i [(chat :a ch)
      (asl-json/json :a j)])

; (:m :tags (structured-output) :do "GW-STRUCTURED-OUTPUT: chat.asl carries an OpenAI response_format onto Anthropic (a forced tool) and Gemini (responseMimeType/responseSchema) request bodies, and structuredOutputError names the cases a provider cannot honor")

fn bodyWith rf: j/Json -> j/Json
  (j/jobj (list (pair "messages" (j/jarr (list)))
                (pair "max_tokens" (j/jint 100))
                (pair "response_format" rf)))

fn objectRf -> j/Json
  (j/jobj (list (pair "type" (j/jstr "json_object"))))

fn schemaRf -> j/Json
  (j/jobj (list (pair "type" (j/jstr "json_schema"))
                (pair "json_schema" (j/jobj (list (pair "name" (j/jstr "foo"))
                                                  (pair "schema" (j/jobj (list (pair "type" (j/jstr "object"))))))))))

fn schemaNoNameRf -> j/Json
  (j/jobj (list (pair "type" (j/jstr "json_schema"))
                (pair "json_schema" (j/jobj (list (pair "schema" (j/jobj (list (pair "type" (j/jstr "object"))))))))))

fn textRf -> j/Json
  (j/jobj (list (pair "type" (j/jstr "text"))))

fn unknownRf -> j/Json
  (j/jobj (list (pair "type" (j/jstr "xml"))))

fn errOf body: j/Json provider: String -> String
  (match (ch/structuredOutputError body provider)
    ((some s) s)
    ((none) ""))

fn testAnthropicJsonSchema -> Bool
  (let [(out (ch/anthropicBody (bodyWith (schemaRf)) "m"))]
    (do
      (assert (= (j/jsonEmit out) "{\"model\":\"m\",\"messages\":[],\"max_tokens\":100,\"tools\":[{\"name\":\"foo\",\"input_schema\":{\"type\":\"object\"}}],\"tool_choice\":{\"type\":\"tool\",\"name\":\"foo\"}}")
              (str "anthropic json_schema emits one forced tool, got " (j/jsonEmit out)))
      true))

fn testAnthropicJsonSchemaDefaultName -> Bool
  (let [(out (ch/anthropicBody (bodyWith (schemaNoNameRf)) "m"))]
    (do
      (assert (= (j/jsonEmit out) "{\"model\":\"m\",\"messages\":[],\"max_tokens\":100,\"tools\":[{\"name\":\"output\",\"input_schema\":{\"type\":\"object\"}}],\"tool_choice\":{\"type\":\"tool\",\"name\":\"output\"}}")
              (str "anthropic json_schema without a name defaults to output, got " (j/jsonEmit out)))
      true))

fn testAnthropicJsonObject -> Bool
  (let [(out (ch/anthropicBody (bodyWith (objectRf)) "m"))]
    (do
      (assert (= (j/jsonEmit out) "{\"model\":\"m\",\"messages\":[],\"max_tokens\":100}")
              (str "anthropic json_object adds no field, got " (j/jsonEmit out)))
      true))

fn testGeminiJsonObject -> Bool
  (let [(out (ch/geminiGenerationConfig (bodyWith (objectRf))))]
    (do
      (assert (= (j/jsonEmit out) "{\"maxOutputTokens\":100,\"responseMimeType\":\"application/json\"}")
              (str "gemini json_object sets responseMimeType, got " (j/jsonEmit out)))
      true))

fn testGeminiJsonSchema -> Bool
  (let [(out (ch/geminiGenerationConfig (bodyWith (schemaRf))))]
    (do
      (assert (= (j/jsonEmit out) "{\"maxOutputTokens\":100,\"responseMimeType\":\"application/json\",\"responseSchema\":{\"type\":\"object\"}}")
              (str "gemini json_schema sets responseMimeType and responseSchema, got " (j/jsonEmit out)))
      true))

fn testStructuredOutputError -> Bool
  (do
    (assert (= (errOf (bodyWith (objectRf)) "anthropic") "ERR_STRUCTURED_UNSUPPORTED: anthropic json_object")
            "anthropic json_object is unsupported")
    (assert (= (errOf (bodyWith (schemaRf)) "anthropic") "")
            "anthropic json_schema is supported")
    (assert (= (errOf (bodyWith (objectRf)) "gemini") "")
            "gemini json_object is supported")
    (assert (= (errOf (bodyWith (schemaRf)) "gemini") "")
            "gemini json_schema is supported")
    (assert (= (errOf (bodyWith (unknownRf)) "anthropic") "ERR_STRUCTURED_UNSUPPORTED: anthropic xml")
            "an unknown response_format type is unsupported on anthropic")
    (assert (= (errOf (bodyWith (unknownRf)) "gemini") "ERR_STRUCTURED_UNSUPPORTED: gemini xml")
            "an unknown response_format type is unsupported on gemini")
    (assert (= (errOf (bodyWith (textRf)) "anthropic") "")
            "anthropic text is supported")
    (assert (= (errOf (bodyWith (textRf)) "gemini") "")
            "gemini text is supported")
    (assert (= (errOf (j/jobj (list)) "anthropic") "")
            "no response_format is fine")
    true)

fn ! runTests -> Bool
  (do
    (assert (testAnthropicJsonSchema) "testAnthropicJsonSchema passed")
    (assert (testAnthropicJsonSchemaDefaultName) "testAnthropicJsonSchemaDefaultName passed")
    (assert (testAnthropicJsonObject) "testAnthropicJsonObject passed")
    (assert (testGeminiJsonObject) "testGeminiJsonObject passed")
    (assert (testGeminiJsonSchema) "testGeminiJsonSchema passed")
    (assert (testStructuredOutputError) "testStructuredOutputError passed")
    true)
