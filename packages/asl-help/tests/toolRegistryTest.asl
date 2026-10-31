(module asl-help/tests/toolRegistryTest :x [runTests] :i [(asl-help/toolRegistry :a reg)])

; (:m :ref COVBATCH2 :do "lookupTool, catalogDigest, formatCatalogSummary: every canonical tool is found, unknown and empty names are none, the summary carries the total and digest")
fn found? name: String -> Bool
  (some? (reg/lookupTool name))

fn runTests -> Bool
  (let [(tools (reg/canonicalTools))
        (summary (reg/formatCatalogSummary))]
    (do
      (assert (= (listLength tools) (reg/catalogSize)) "the catalog size matches the tool list")
      (assert (= (listLength (filter (fn [(t Any)] -> Bool (found? t.name)) tools)) (listLength tools)) "every canonical tool is found by its name")
      (assert (= (match (reg/lookupTool "query") ((some t) t.name) ((none) "")) "query") "lookup returns the tool with that name")
      (assert (none? (reg/lookupTool "")) "an empty name is none")
      (assert (none? (reg/lookupTool "noSuchTool")) "an unknown name is none")
      (assert (none? (reg/lookupTool "Query")) "lookup is case sensitive")
      (assert (= (reg/catalogDigest) "d81-tools-v1-600-canonical") "the digest names the catalog version")
      (assert (stringStartsWith? summary "(:receipt :op \"tools\" :status \"ok\" :total 22 ") "the summary opens with the total")
      (assert (stringContains? summary (str ":catalogDigest \"" (reg/catalogDigest) "\"")) "the summary carries the digest")
      (assert (stringEndsWith? summary "))") "the summary closes its catalog")
      (assert (= (reg/helpTool! "") summary) "no name asks for the summary")
      (assert (stringContains? (reg/formatToolDeepByName "noSuchTool") ":ERR_UNKNOWN_TOOL") "an unknown tool is an error receipt")
      (assert (stringContains? (reg/formatToolDeepByName "query") ":status \"ok\"") "a known tool is an ok receipt")
      true))
