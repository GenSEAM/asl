(module asl-help/toolRegistryTest
  :x [runTests]
  :i [(toolDescriptor :a td) (toolRegistry :a tr) (situations :a sit)])

fn testAll22ToolsPresent -> Bool
  (let [(tools (tr/canonicalTools))]
    (assert (= (listLength tools) 22) "Registry must contain exactly 22 canonical tools")
    (assert (= (tr/catalogSize) 22) "catalogSize must return 22")
    (assert (some? (tr/lookupTool "query")) "query tool must be present")
    (assert (some? (tr/lookupTool "read")) "read tool must be present")
    (assert (some? (tr/lookupTool "edit")) "edit tool must be present")
    (assert (some? (tr/lookupTool "diff")) "diff tool must be present")
    (assert (some? (tr/lookupTool "flush")) "flush tool must be present")
    (assert (some? (tr/lookupTool "discard")) "discard tool must be present")
    (assert (some? (tr/lookupTool "preflush")) "preflush tool must be present")
    (assert (some? (tr/lookupTool "consult")) "consult tool must be present")
    (assert (some? (tr/lookupTool "tree")) "tree tool must be present")
    (assert (some? (tr/lookupTool "doc")) "doc tool must be present")
    (assert (some? (tr/lookupTool "check")) "check tool must be present")
    (assert (some? (tr/lookupTool "test")) "test tool must be present")
    (assert (some? (tr/lookupTool "gate")) "gate tool must be present")
    (assert (some? (tr/lookupTool "doctor")) "doctor tool must be present")
    (assert (some? (tr/lookupTool "pack")) "pack tool must be present")
    (assert (some? (tr/lookupTool "consilium")) "consilium tool must be present")
    (assert (some? (tr/lookupTool "lens")) "lens tool must be present")
    (assert (some? (tr/lookupTool "note")) "note tool must be present")
    (assert (some? (tr/lookupTool "where")) "where tool must be present")
    (assert (some? (tr/lookupTool "tools")) "tools tool must be present")
    (assert (some? (tr/lookupTool "relay")) "relay tool must be present")
    (assert (some? (tr/lookupTool "mesh")) "mesh tool must be present")
    true)

fn testToolDescriptorContent -> Bool
  (let [(qOpt (tr/lookupTool "query"))
        (eOpt (tr/lookupTool "edit"))
        (wOpt (tr/lookupTool "where"))
        (q (optionOr qOpt (td/makeToolDescriptor "" "" "" "" (list) (list) "" "" "" (list) "")))
        (e (optionOr eOpt (td/makeToolDescriptor "" "" "" "" (list) (list) "" "" "" (list) "")))
        (w (optionOr wOpt (td/makeToolDescriptor "" "" "" "" (list) (list) "" "" "" (list) "")))]
    (assert (= q.contract "vector semantic search AST") "query contract must match")
    (assert (stringContains? q.whenToUse "exploration") "query whenToUse must explain exploration")
    (assert (stringContains? q.whenNotToUse "(:read)") "query whenNotToUse must recommend :read when path known")
    (assert (= e.contract "stage atomic string replacement") "edit contract must match")
    (assert (stringContains? e.whenToUse "RAM VFS") "edit whenToUse must explain RAM VFS staging")
    (assert (= w.contract "deliver situation slice & active invariants") "where contract must match")
    true)

fn testUnknownToolRefutations! -> Bool
  (let [(emptyOpt (tr/lookupTool ""))
        (bogusOpt (tr/lookupTool "bogusXYZ"))
        (bogusErr (tr/helpTool! "bogusXYZ"))]
    (assert (none? emptyOpt) "Lookup on empty tool string must return none")
    (assert (none? bogusOpt) "Lookup on unknown tool must return none")
    (assert (stringContains? bogusErr ":ERR_UNKNOWN_TOOL") "helpTool! on unknown tool must return :ERR_UNKNOWN_TOOL")
    true)

fn testTokenCeilingsAndBudgets -> Bool
  (let [(tools (tr/canonicalTools))]
    (fold (fn [(acc Bool) (tool td/ToolDescriptor)] -> Bool
            (let [(cCost (td/compactTokenCost tool))
                  (dCost (td/deepTokenCost tool))]
              (assert (<= cCost 60) "Compact entry token cost must be <= 60 tokens")
              (assert (<= dCost 150) "Deep descriptor token cost must be <= 150 tokens")
              (and acc (and (<= cCost 60) (<= dCost 150)))))
          true
          tools))

fn testCatalogFormattingAndDigest -> Bool
  (let [(summary (tr/formatCatalogSummary))]
    (assert (stringContains? summary ":catalogDigest") "Summary must include :catalogDigest")
    (assert (stringContains? summary "d81-tools-v1-600-canonical") "Digest must match canonical version")
    (assert (stringContains? summary ":catalog (") "Summary must use pure Dyck-1 :catalog (")
    (assert (stringContains? summary ":name \"query\"") "Summary must contain query tool")
    (assert (stringContains? summary ":name \"where\"") "Summary must contain where tool")
    true)

fn testSituationalGuidanceEngine -> Bool
  (let [(chgQ (sit/situationQuestion "change"))
        (chgTools (sit/situationRecommendedTools "change"))
        (orientTools (sit/situationRecommendedTools "orient"))
        (validChg (sit/isKnownSituation "change"))
        (invalidSit (sit/isKnownSituation "invalidSituation123"))
        (guidanceChg (sit/formatSituationalGuidance "change"))
        (guidanceErr (sit/formatSituationalGuidance "invalidSituation123"))]
    (assert (= chgQ "How do I modify a file safely?") "change question must match")
    (assert (sit/isKnownSituation "orient") "orient must be a known situation")
    (assert (sit/isKnownSituation "verify") "verify must be a known situation")
    (assert validChg "change must be known situation")
    (assert (not invalidSit) "invalidSituation123 must be refuted as unknown")
    (assert (stringContains? guidanceChg ":situation \"change\"") "Guidance must contain situation change")
    (assert (stringContains? guidanceChg "\"txn\"") "Guidance must highlight txn invariant")
    (assert (stringContains? guidanceErr ":ERR_UNKNOWN_SITUATION") "Guidance for invalid situation must return error")
    true)

fn ! runTests -> Bool
  (and (testAll22ToolsPresent)
       (and (testToolDescriptorContent)
            (and (testUnknownToolRefutations!)
                 (and (testTokenCeilingsAndBudgets)
                      (and (testCatalogFormattingAndDigest)
                           (testSituationalGuidanceEngine))))))
