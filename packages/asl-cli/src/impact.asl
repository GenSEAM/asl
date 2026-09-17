(module asl-cli/impact
  :d "Pure ASL CLI impact command handler and sub-80-token blast radius query dispatcher under ADR D94."
  :x [runImpactCommand
      formatImpactHelp
      executeImpactQuery]
  :i [(asl-hypergraph :a hyper)
      (asl-hypergraph/model :a model)])

(df formatImpactHelp [] -> Str
  :d "Returns usage manual for asl impact subcommand."
  (str "Usage: asl impact <symbol>\n\n"
       "Analyzes blast radius, direct callers, test dependencies, and type signatures.\n\n"
       "Arguments:\n"
       "  <symbol>    Target function, struct, or type identifier (Module:symbol or symbol)\n\n"
       "[Teleology] Principle: GroundTruthOverReport (ADR D94)\n"
       "  \"Codebase hypergraph queries bound perceptual tokens (<80 tokens) with zero line numbers.\"\n\n"
       "[Assistive Ontology] Enforces High-SNR Compact Perceptions:\n"
       "  • Truncated Callers: High fan-in symbols truncated to max 5 direct callers\n"
       "  • Test Linkage: Direct and transitive test suite blast radius mapping\n"
       "  • Zero-Line-Number Invariant: Code addressed strictly by Module:symbol and :anchor\n"))

(df defaultModulesCorpus [] -> (List (Pair Str Str))
  :d "Provides standard fallback module pairs for in-memory index construction."
  (list (pair "asl-ir/patch"
              (str "(module asl-ir/patch :d \"AST patch algebra\"\n"
                   "  :x [parsePatch applyPatch invertPatch computeAstDigest])\n"
                   "(df parsePatch [(text Str)] -> (Result Str Str) text)\n"
                   "(df applyPatch [(p Str) (src Str)] -> (Result Str Str) src)\n"
                   "(df invertPatch [(p Str)] -> Str p)\n"
                   "(df computeAstDigest [(src Str)] -> Str src)\n"))
        (pair "asl-cli/patch"
              (str "(module asl-cli/patch :d \"CLI patch handler\"\n"
                   "  :x [runPatchCommand executePatchApply executePatchCheck executePatchRollback])\n"
                   "(df executePatchApply [(pPath Str) (tPath (Option Str))] -> Str (parsePatch pPath))\n"
                   "(df executePatchCheck [(pPath Str) (tPath (Option Str))] -> Str (parsePatch pPath))\n"
                   "(df executePatchRollback [(cnt (Option Int64))] -> Str (applyPatch \"inv\" \"src\"))\n"
                   "(df runPatchCommand [(args (List Str))] -> Str (executePatchApply \"p\" (none)))\n"))
        (pair "tests/acceptance/d81/Task53601"
              (str "(module tests/acceptance/d81/Task53601 :d \"Acceptance test 53601\"\n"
                   "  :x [runTests])\n"
                   "(df ! testPatchOperations [] -> Bool (do (parsePatch \"test\") (applyPatch \"p\" \"s\") true))\n"
                   "(df ! runTests [] -> Bool (testPatchOperations))\n"))
        (pair "tests/acceptance/d81/Task53602"
              (str "(module tests/acceptance/d81/Task53602 :d \"Acceptance test 53602\"\n"
                   "  :x [runTests])\n"
                   "(df ! testCliDispatch [] -> Bool (do (runPatchCommand (list)) true))\n"
                   "(df ! runTests [] -> Bool (testCliDispatch))\n"))))

(df executeImpactQuery [(targetSym Str)] -> (Result Str Str)
  :d "Executes blast-radius impact analysis for target symbol and returns formatted ASN receipt."
  (let [(indexPath ".asl/mem/hyper.idx")
        (idx (hyper/loadOrBuildHyperIndex indexPath (defaultModulesCorpus)))
        (receipt (hyper/querySymbolImpact idx targetSym))
        (formatted (hyper/formatImpactReceipt receipt))]
    (ok formatted)))

(df runImpactCommand [(args (List Str))] -> (Result Str Str)
  :d "Top-level command dispatcher for asl impact subcommand."
  (if (list-empty? args)
      (ok (formatImpactHelp))
      (let [(firstArg (option-or (list-head args) ""))]
        (if (or (= firstArg "--help") (or (= firstArg "-h") (= firstArg "help")))
            (ok (formatImpactHelp))
            (executeImpactQuery firstArg)))))
