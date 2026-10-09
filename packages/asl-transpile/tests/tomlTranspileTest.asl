(module asl-transpile/tomlTranspileTest :x [testTomlBasicKv testTomlSections testTomlInlineArrays testTomlArrayOfTables testTomlCommentsStripped testTomlRoundtrip testTomlNegative runTests] :i [(asl-transpile/tomlTranspile :a tt)])

fn testTomlBasicKv -> Bool
  (let [(res (tt/tomlToAsn "name = \"asex\"\nversion = \"0.1.0\"\nactive = true\ntokens = 1200"))] (assert res.success "basic toml succeeds") (assert (stringContains? res.output ":name \"asex\"") "contains name") (assert (stringContains? res.output ":version \"0.1.0\"") "contains version") (assert (stringContains? res.output ":active true") "contains boolean active") (assert (stringContains? res.output ":tokens 1200") "contains integer tokens") (assert (>= res.savingsPercent 20.0) "savings >= 20%") true)

fn testTomlSections -> Bool
  (let [(tomlPayload "[package]\nname = \"asex\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = \"1.0\"\ntokio = \"1.28\"") (res (tt/tomlToAsn tomlPayload))] (assert res.success "sectioned toml succeeds") (assert (stringContains? res.output ":package (") "contains package section record") (assert (stringContains? res.output ":dependencies (") "contains dependencies section record") (assert (stringContains? res.output ":serde \"1.0\"") "contains serde dependency") (assert (stringContains? res.output ":tokio \"1.28\"") "contains tokio dependency") true)

fn testTomlInlineArrays -> Bool
  (let [(tomlPayload "[server]\nhost = \"localhost\"\nports = [8001, 8002, 8003]") (res (tt/tomlToAsn tomlPayload))] (assert res.success "inline array toml succeeds") (assert (stringContains? res.output ":ports [8001 8002 8003]") "contains compact ports vector") true)

fn testTomlArrayOfTables -> Bool
  (let [(tomlPayload "[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\nname = \"Nail\"\nsku = 284758393") (res (tt/tomlToAsn tomlPayload))] (assert res.success "array of tables succeeds") (assert (stringContains? res.output ":products [") "contains products array") (assert (stringContains? res.output "(:name \"Hammer\" :sku 738594937)") "contains first product record") (assert (stringContains? res.output "(:name \"Nail\" :sku 284758393)") "contains second product record") true)

fn testTomlCommentsStripped -> Bool
  (let [(tomlPayload "# Application Configuration\nname = \"asex\" # inline comment\nversion = \"1.0.0\"") (res (tt/tomlToAsn tomlPayload))] (assert res.success "commented toml succeeds") (assert (stringContains? res.output ":name \"asex\"") "preserves name value") (assert (not (stringContains? res.output "#")) "strips comment characters") true)

fn testTomlRoundtrip -> Bool
  (let [(asnPayload "(:package (:name \"asex\" :version \"0.1.0\") :dependencies (:serde \"1.0\"))") (res (tt/asnToToml asnPayload))] (assert res.success "asn to toml succeeds") (assert (stringContains? res.output "[package]") "contains package section header") (assert (stringContains? res.output "name = \"asex\"") "contains name assignment") (assert (stringContains? res.output "version = \"0.1.0\"") "contains version assignment") (assert (stringContains? res.output "[dependencies]") "contains dependencies section header") (assert (stringContains? res.output "serde = \"1.0\"") "contains serde assignment") true)

fn testTomlNegative -> Bool
  (let [(rEmptyT (tt/tomlToAsn "")) (rEmptyA (tt/asnToToml "")) (rBadA (tt/asnToToml "not an asn"))] (assert (not rEmptyT.success) "empty toml rejected") (assert (not rEmptyA.success) "empty asn rejected") (assert (not rBadA.success) "invalid asn root rejected") true)

fn runTests -> Bool
  (do (assert (testTomlBasicKv) "basic kv") (assert (testTomlSections) "sections") (assert (testTomlInlineArrays) "inline arrays") (assert (testTomlArrayOfTables) "array of tables") (assert (testTomlCommentsStripped) "comments stripped") (assert (testTomlRoundtrip) "roundtrip") (assert (testTomlNegative) "negative") true)
