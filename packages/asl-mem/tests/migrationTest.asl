(module aslMem/migrationTest :x [testMigratePcpYaml testQueryMemoryShortcode testSerializeLedgerAsn testMigrationTokenSavings testEmptyMigration runMigrationTests runTests] :i [(migration :a mig) (records :a rec)])

fn sampleYamlConstitution -> Str
  (str "name: workspace-constitution\n" "version: 1.0.0\n" "rules:\n" "  - code: l-0001\n" "    title: Pure AgentScript Invariant\n" "    why: Zero foreign files allowed in packages\n" "    status: active\n" "  - code: D0042\n" "    title: Native S-Expression Memory Storage\n" "    why: Eliminates markdown file parsing overhead and context drowning\n" "    status: active\n" "  - code: C0007\n" "    title: No Subagent Context Duplication\n" "    why: Internalize steps protocol to save tokens and eliminate latency\n" "    status: active\n")

fn testMigratePcpYaml -> Bool
  (let [(res (mig/migratePcpConstitution (sampleYamlConstitution)))] (assert res.success "migration succeeds") (assert (= res.totalRules 3) "total rules is 3") true)

fn testQueryMemoryShortcode -> Bool
  (let [(res (mig/migratePcpConstitution (sampleYamlConstitution))) (rules res.migratedRules) (codes (map (fn [(r rec/AdrRule)] -> Str r.code) rules)) (ledger (rec/RecordsLedger :rules rules :shortcodes codes)) (found (mig/queryMemoryShortcode ledger "l-0001"))] (mt found ((none) (do (assert false "rule not found") false)) ((some rule) (do (assert (= rule.code "l-0001") "code matches") (assert (= rule.title "Pure AgentScript Invariant") "title matches") true))))

fn testSerializeLedgerAsn -> Bool
  (let [(res (mig/migratePcpConstitution (sampleYamlConstitution))) (rules res.migratedRules) (codes (map (fn [(r rec/AdrRule)] -> Str r.code) rules)) (ledger (rec/RecordsLedger :rules rules :shortcodes codes)) (asnStr (mig/serializeLedgerAsn ledger))] (assert (stringContains? asnStr "(:asl-mem-ledger") "contains ledger tag") (assert (stringContains? asnStr "(:rule :code \"l-0001\"") "contains rule l-0001") (assert (stringContains? asnStr "(:rule :code \"D0042\"") "contains rule D0042") true)

fn testMigrationTokenSavings -> Bool
  (let [(res (mig/migratePcpConstitution (sampleYamlConstitution)))] (assert res.success "success true") (assert (> res.rawTokens 0) "raw tokens > 0") true)

fn testEmptyMigration -> Bool
  (let [(res (mig/migratePcpConstitution ""))] (assert (not res.success) "empty input fails") (assert (= res.totalRules 0) "empty input total rules is 0") true)

fn runMigrationTests -> Bool
  (and (testMigratePcpYaml) (and (testQueryMemoryShortcode) (and (testSerializeLedgerAsn) (and (testMigrationTokenSavings) (testEmptyMigration)))))

fn runTests -> Bool
  (runMigrationTests)
