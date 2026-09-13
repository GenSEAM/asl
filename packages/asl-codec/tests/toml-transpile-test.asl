(module asl-codec/tomlTranspileTest
  :d "Unit verification test suite for TOML <-> ASN Configuration Transpiler"
  :x [testTomlBasicKv
      testTomlSections
      testTomlInlineArrays
      testTomlArrayOfTables
      testTomlCommentsStripped
      testTomlRoundtrip
      testTomlNegative
      runTests]
  :i [(asl-codec/tomlTranspile :a tt)])

(df testTomlBasicKv [] -> Bool
  :d "Verifies basic TOML key-value assignments."
  (let [(res (tt/tomlToAsn "name = \"asex\"\nversion = \"0.1.0\"\nactive = true\ntokens = 1200"))]
    (assert (.-success res) "basic toml succeeds")
    (assert (string-contains? (.-output res) ":name \"asex\"") "contains name")
    (assert (string-contains? (.-output res) ":version \"0.1.0\"") "contains version")
    (assert (string-contains? (.-output res) ":active true") "contains boolean active")
    (assert (string-contains? (.-output res) ":tokens 1200") "contains integer tokens")
    (assert (>= (.-savingsPercent res) 20.0) "savings >= 20%")
    true))

(df testTomlSections [] -> Bool
  :d "Verifies multi-section TOML document conversion."
  (let [(tomlPayload "[package]\nname = \"asex\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = \"1.0\"\ntokio = \"1.28\"")
        (res (tt/tomlToAsn tomlPayload))]
    (assert (.-success res) "sectioned toml succeeds")
    (assert (string-contains? (.-output res) ":package (") "contains package section record")
    (assert (string-contains? (.-output res) ":dependencies (") "contains dependencies section record")
    (assert (string-contains? (.-output res) ":serde \"1.0\"") "contains serde dependency")
    (assert (string-contains? (.-output res) ":tokio \"1.28\"") "contains tokio dependency")
    true))

(df testTomlInlineArrays [] -> Bool
  :d "Verifies inline vector values in TOML."
  (let [(tomlPayload "[server]\nhost = \"localhost\"\nports = [8001, 8002, 8003]")
        (res (tt/tomlToAsn tomlPayload))]
    (assert (.-success res) "inline array toml succeeds")
    (assert (string-contains? (.-output res) ":ports [8001 8002 8003]") "contains compact ports vector")
    true))

(df testTomlArrayOfTables [] -> Bool
  :d "Verifies array of tables [[name]] syntax."
  (let [(tomlPayload "[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\nname = \"Nail\"\nsku = 284758393")
        (res (tt/tomlToAsn tomlPayload))]
    (assert (.-success res) "array of tables succeeds")
    (assert (string-contains? (.-output res) ":products [") "contains products array")
    (assert (string-contains? (.-output res) "(:name \"Hammer\" :sku 738594937)") "contains first product record")
    (assert (string-contains? (.-output res) "(:name \"Nail\" :sku 284758393)") "contains second product record")
    true))

(df testTomlCommentsStripped [] -> Bool
  :d "Verifies comment stripping outside quotes."
  (let [(tomlPayload "# Application Configuration\nname = \"asex\" # inline comment\nversion = \"1.0.0\"")
        (res (tt/tomlToAsn tomlPayload))]
    (assert (.-success res) "commented toml succeeds")
    (assert (string-contains? (.-output res) ":name \"asex\"") "preserves name value")
    (assert (not (string-contains? (.-output res) "#")) "strips comment characters")
    true))

(df testTomlRoundtrip [] -> Bool
  :d "Verifies ASN record serialization back to valid TOML sections."
  (let [(asnPayload "(:package (:name \"asex\" :version \"0.1.0\") :dependencies (:serde \"1.0\"))")
        (res (tt/asnToToml asnPayload))]
    (assert (.-success res) "asn to toml succeeds")
    (assert (string-contains? (.-output res) "[package]") "contains package section header")
    (assert (string-contains? (.-output res) "name = \"asex\"") "contains name assignment")
    (assert (string-contains? (.-output res) "version = \"0.1.0\"") "contains version assignment")
    (assert (string-contains? (.-output res) "[dependencies]") "contains dependencies section header")
    (assert (string-contains? (.-output res) "serde = \"1.0\"") "contains serde assignment")
    true))

(df testTomlNegative [] -> Bool
  :d "Verifies rejection of empty or malformed inputs."
  (let [(rEmptyT (tt/tomlToAsn ""))
        (rEmptyA (tt/asnToToml ""))
        (rBadA (tt/asnToToml "not an asn"))]
    (assert (not (.-success rEmptyT)) "empty toml rejected")
    (assert (not (.-success rEmptyA)) "empty asn rejected")
    (assert (not (.-success rBadA)) "invalid asn root rejected")
    true))

(df runTests [] -> Bool
  :d "Runs all TOML transpiler unit tests."
  (do
    (assert (testTomlBasicKv) "basic kv")
    (assert (testTomlSections) "sections")
    (assert (testTomlInlineArrays) "inline arrays")
    (assert (testTomlArrayOfTables) "array of tables")
    (assert (testTomlCommentsStripped) "comments stripped")
    (assert (testTomlRoundtrip) "roundtrip")
    (assert (testTomlNegative) "negative")
    true))
