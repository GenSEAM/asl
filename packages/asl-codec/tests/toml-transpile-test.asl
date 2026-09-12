(module asl-codec/toml-transpile-test
  :d "Unit verification test suite for TOML <-> ASN Configuration Transpiler"
  :x [test-toml-basic-kv
      test-toml-sections
      test-toml-inline-arrays
      test-toml-array-of-tables
      test-toml-comments-stripped
      test-toml-roundtrip
      test-toml-negative
      run-tests]
  :i [(asl-codec/toml-transpile :a tt)])

(df test-toml-basic-kv [] -> Bool
  :d "Verifies basic TOML key-value assignments."
  (let [(res (tt/toml-to-asn "name = \"asex\"\nversion = \"0.1.0\"\nactive = true\ntokens = 1200"))]
    (assert (.-success res) "basic toml succeeds")
    (assert (string-contains? (.-output res) ":name \"asex\"") "contains name")
    (assert (string-contains? (.-output res) ":version \"0.1.0\"") "contains version")
    (assert (string-contains? (.-output res) ":active true") "contains boolean active")
    (assert (string-contains? (.-output res) ":tokens 1200") "contains integer tokens")
    (assert (>= (.-savings-percent res) 20.0) "savings >= 20%")
    true))

(df test-toml-sections [] -> Bool
  :d "Verifies multi-section TOML document conversion."
  (let [(toml-payload "[package]\nname = \"asex\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = \"1.0\"\ntokio = \"1.28\"")
        (res (tt/toml-to-asn toml-payload))]
    (assert (.-success res) "sectioned toml succeeds")
    (assert (string-contains? (.-output res) ":package (") "contains package section record")
    (assert (string-contains? (.-output res) ":dependencies (") "contains dependencies section record")
    (assert (string-contains? (.-output res) ":serde \"1.0\"") "contains serde dependency")
    (assert (string-contains? (.-output res) ":tokio \"1.28\"") "contains tokio dependency")
    true))

(df test-toml-inline-arrays [] -> Bool
  :d "Verifies inline vector values in TOML."
  (let [(toml-payload "[server]\nhost = \"localhost\"\nports = [8001, 8002, 8003]")
        (res (tt/toml-to-asn toml-payload))]
    (assert (.-success res) "inline array toml succeeds")
    (assert (string-contains? (.-output res) ":ports [8001 8002 8003]") "contains compact ports vector")
    true))

(df test-toml-array-of-tables [] -> Bool
  :d "Verifies array of tables [[name]] syntax."
  (let [(toml-payload "[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\nname = \"Nail\"\nsku = 284758393")
        (res (tt/toml-to-asn toml-payload))]
    (assert (.-success res) "array of tables succeeds")
    (assert (string-contains? (.-output res) ":products [") "contains products array")
    (assert (string-contains? (.-output res) "(:name \"Hammer\" :sku 738594937)") "contains first product record")
    (assert (string-contains? (.-output res) "(:name \"Nail\" :sku 284758393)") "contains second product record")
    true))

(df test-toml-comments-stripped [] -> Bool
  :d "Verifies comment stripping outside quotes."
  (let [(toml-payload "# Application Configuration\nname = \"asex\" # inline comment\nversion = \"1.0.0\"")
        (res (tt/toml-to-asn toml-payload))]
    (assert (.-success res) "commented toml succeeds")
    (assert (string-contains? (.-output res) ":name \"asex\"") "preserves name value")
    (assert (not (string-contains? (.-output res) "#")) "strips comment characters")
    true))

(df test-toml-roundtrip [] -> Bool
  :d "Verifies ASN record serialization back to valid TOML sections."
  (let [(asn-payload "(:package (:name \"asex\" :version \"0.1.0\") :dependencies (:serde \"1.0\"))")
        (res (tt/asn-to-toml asn-payload))]
    (assert (.-success res) "asn to toml succeeds")
    (assert (string-contains? (.-output res) "[package]") "contains package section header")
    (assert (string-contains? (.-output res) "name = \"asex\"") "contains name assignment")
    (assert (string-contains? (.-output res) "version = \"0.1.0\"") "contains version assignment")
    (assert (string-contains? (.-output res) "[dependencies]") "contains dependencies section header")
    (assert (string-contains? (.-output res) "serde = \"1.0\"") "contains serde assignment")
    true))

(df test-toml-negative [] -> Bool
  :d "Verifies rejection of empty or malformed inputs."
  (let [(r-empty-t (tt/toml-to-asn ""))
        (r-empty-a (tt/asn-to-toml ""))
        (r-bad-a (tt/asn-to-toml "not an asn"))]
    (assert (not (.-success r-empty-t)) "empty toml rejected")
    (assert (not (.-success r-empty-a)) "empty asn rejected")
    (assert (not (.-success r-bad-a)) "invalid asn root rejected")
    true))

(df run-tests [] -> Bool
  :d "Runs all TOML transpiler unit tests."
  (do
    (assert (test-toml-basic-kv) "basic kv")
    (assert (test-toml-sections) "sections")
    (assert (test-toml-inline-arrays) "inline arrays")
    (assert (test-toml-array-of-tables) "array of tables")
    (assert (test-toml-comments-stripped) "comments stripped")
    (assert (test-toml-roundtrip) "roundtrip")
    (assert (test-toml-negative) "negative")
    true))
