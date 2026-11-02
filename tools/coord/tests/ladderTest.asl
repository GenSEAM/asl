(module asl/tools/coord/tests/ladderTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/grade :a g)])

fn lane alias: String tier: String n: Int64 -> l/Lane
  (l/Lane :alias alias :tier tier :allowance n :quality 0)

fn pool -> (List l/Lane)
  (list (lane "flashLow" "free" 5) (lane "orNemotronUltraFree" "free" 5) (lane "nimNemotronUltra" "free" 5) (lane "ocLongcat" "free" 5)
        (lane "ocDeepseekFlash" "paid" 5) (lane "tgGlm53Flash" "paid" 5)
        (lane "ccKimi31Pro" "strong" 5))

fn unit risk: String closure: Bool -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task "fix the bound in listTake" :risk risk :closureChanged closure :writerAlias "flashHigh" :writerChannel "agy"
                :startRung "" :fixesUsed 0 :prior (list))

fn goodGates -> String
  (str "(:receipt U1 :gates ((:gate ladderTest :exit 0 :executed 12)) :redBefore ((:gate ladderTest :exit 1 :executed 0)))")

fn noRedGates -> String
  (str "(:receipt U1 :gates ((:gate ladderTest :exit 0 :executed 12)))")

fn passReply -> String
  "(:verdict :pass :defects () :model m)"

fn failReply -> String
  "(:verdict :fail :defects (\"listTake overruns the slice in clip\") :model m)"

fn lookup replies: (List (Pair String String)) alias: String -> String
  (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) alias)) replies))
    ((some p) (pairSecond p))
    ((none) "no reply"))

fn run u: l/ReviewUnit gates: String lanes: (List l/Lane) replies: (List (Pair String String)) -> l/Ruling
  (match (l/review u "+ a\n- b" gates lanes (fn [(a String) (p String)] -> (Result String String) (ok (lookup replies a))))
    ((ok r) r)
    ((err e) (l/Ruling :action "error" :rung "" :defects (list) :awaitLane "" :rows (list) :verdicts (list) :why e)))

fn models r: l/Ruling -> (List String)
  (map (fn [(v l/Verdict)] -> String v.model) r.verdicts)

fn rungs r: l/Ruling -> (List String)
  (map (fn [(v l/Verdict)] -> String v.rung) r.verdicts)

fn rows -> (List rd)
  (list)

fn testFamilies -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))]
    (do (assert (= (l/familyIn rs "ocDeepseekFlash") "deepseek") "deepseek flash is deepseek not google")
        (assert (= (l/familyIn rs "orDsFlash0731") "deepseek") "or ds alias is deepseek")
        (assert (= (l/familyIn rs "flashHigh") "google") "agy flash alias is google")
        (assert (= (l/familyIn rs "claude-opus-5-5") "anthropic") "model names map too")
        (assert (= (l/familyIn rs "ccKimi31Pro") "moonshot") "kimi is moonshot")
        (assert (= (l/familyIn rs "ocCatJam") "") "an unknown alias has no family")
        (assert (= (listLength (l/familyRows "(:families")) 0) "a broken table yields no rows")
        true))

fn testSelect -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))
        (fam (fn [(a String)] -> String (l/familyIn rs a)))]
    (do (match (l/selectFree rs "flashHigh" (pool))
          ((l/pickOk ls)
            (do (assert (= (listLength ls) 2) "R1 picks two reviewers")
                (assert (not (listContains? (map (fn [(x l/Lane)] -> String (fam x.alias)) ls) "google")) "R1 never picks the writer's family")
                (assert (let [(fs (map (fn [(x l/Lane)] -> String (fam x.alias)) ls))] (!= (optionOr (listGet fs 0) "") (optionOr (listGet fs 1) ""))) "R1 reviewers are of different families")
                true))
          ((l/pickAwait a w) (do (assert false "R1 should pick") true)))
        (match (l/selectOne rs "ocDeepseekFlash" "paid" (pool))
          ((l/pickOk ls) (assert (= (optionOr (listHead (map (fn [(x l/Lane)] -> String x.alias) ls)) "") "tgGlm53Flash") "R2 skips the writer's family"))
          ((l/pickAwait a w) (assert false "R2 should pick")))
        (match (l/selectOne rs "ccKimi31Pro" "strong" (pool))
          ((l/pickOk ls) (assert false "R3 must not pick the writer's own family"))
          ((l/pickAwait a w) (assert (= a "strong") "R3 waits on the strong tier when its only lane is the writer family")))
        (match (l/selectFree rs "mimoMimoV26Pro+olGptOss120b+ccInclusionaiLing31Flash" (pool))
          ((l/pickOk ls) (assert (= (listLength ls) 2) "R1 picks two non-overlapping reviewers when writer used a multi-family profile"))
          ((l/pickAwait a w) (assert false "multi-family writer profile must not stall on writerFamily")))
        true))

fn testVerdicts -> Bool
  (let [(v (fn [(t String)] -> l/Verdict (l/parseVerdict t "m" "R1")))]
    (do (assert (= (v (passReply)).outcome "pass") "well formed pass")
        (assert (= (v (failReply)).outcome "fail") "fail with a defect")
        (assert (= (v "```\n(:verdict :pass :defects () :model m)\n```").outcome "pass") "a fenced reply parses")
        (assert (= (v "looks good to me").outcome "abstain") "prose is abstain, not pass")
        (assert (= (v "(:verdict :pass").outcome "abstain") "unbalanced is abstain")
        (assert (= (v "(:verdict :fail :defects ())").outcome "abstain") "fail without a defect is abstain")
        (assert (= (v "(:verdict :pass :fail)").outcome "abstain") "both pass and fail is abstain")
        (assert (= (v "(:verdict :maybe)").outcome "abstain") "unknown outcome is abstain")
        (assert (= (v "").outcome "abstain") "empty is abstain")
        true))

fn testMerge -> Bool
  (let [(r (run (unit "low" false) (goodGates) (pool) (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)))))]
    (do (assert (= r.action "merge") "R1 both pass with red-before gates and low risk merges")
        (assert (= (listLength r.verdicts) 2) "two R1 verdicts")
        (assert (not (listContains? (models r) "flashLow")) "the writer's family is never asked")
        (assert (listEmpty? (g/statsProblems (optionOr (listHead r.rows) ""))) "the merge row is a valid grade row")
        (assert (stringContains? (optionOr (listHead r.rows) "") ":verdict accept") "merge is an accept grade")
        (let [(m (run (unit "med" false) (goodGates) (pool) (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)))))
              (n (run (unit "low" false) (noRedGates) (pool) (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)))))]
          (do (assert (= m.action "merge") "med risk with both pass merges per the plan row")
              (assert (= n.action "fix") "gates not proven red-before go back to the writer, never merge")
              true))))

fn testSplitAndAbstain -> Bool
  (let [(split (run (unit "low" false) (goodGates) (pool)
                 (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" (passReply)))))
        (junk (run (unit "low" false) (goodGates) (pool)
                 (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" "LGTM") (pair "ocDeepseekFlash" "LGTM") (pair "ccKimi31Pro" "LGTM"))))
        (bothFail (run (unit "low" false) (goodGates) (pool)
                 (list (pair "orNemotronUltraFree" (failReply)) (pair "ocLongcat" (failReply)))))]
    (do (assert (= (rungs split) (list "R1" "R1" "R2")) "a split at R1 escalates to R2")
        (assert (= split.action "merge") "R2 tie-break pass makes the majority")
        (assert (= split.rung "R2") "merged on R2")
        (assert (!= junk.action "merge") "an abstaining reviewer never counts as a pass")
        (assert (= junk.action "blocked") "abstains all the way up end blocked")
        (assert (= bothFail.action "fix") "both fail with defects goes back to the writer")
        (assert (not (listEmpty? bothFail.defects)) "the fix round carries the defects")
        true))

fn testFixCap -> Bool
  (let [(u (l/ReviewUnit :id "U1" :task "t" :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "" :fixesUsed 1 :prior (list)))
        (r (run u (goodGates) (pool) (list (pair "orNemotronUltraFree" (failReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" (failReply)) (pair "ccKimi31Pro" (failReply)))))]
    (do (assert (= (rungs r) (list "R1" "R1" "R2")) "R1 failing after its fix round climbs to R2 instead of a second R1 fix")
        (assert (and (= r.action "fix") (= r.rung "R2")) "the fresh rung gets its own single fix round")
        (let [(u3 (l/ReviewUnit :id "U1" :task "t" :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "R3" :fixesUsed 1 :prior (list)))
              (r3 (run u3 (goodGates) (pool) (list (pair "ccKimi31Pro" (failReply)))))]
          (assert (= r3.action "blocked") "a fail at R3 after its fix round is blocked"))
        true))

fn testRisk -> Bool
  (let [(high (run (unit "high" false) (goodGates) (pool) (list (pair "ocDeepseekFlash" (passReply)))))
        (closure (run (unit "low" true) (goodGates) (pool)
                   (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (passReply)) (pair "ocDeepseekFlash" (passReply)))))]
    (do (assert (= (rungs high) (list "R2")) "high risk skips R1 and asks only R2")
        (assert (= high.action "merge") "a single R2 pass merges at high risk")
        (assert (= (rungs closure) (list "R1" "R1" "R2")) "a closure change escalates one rung even when R1 passes")
        (assert (= closure.action "merge") "closure change merges after R2 passes")
        true))

fn testAwait -> Bool
  (let [(none (list (lane "flashLow" "free" 5) (lane "orNemotronUltraFree" "free" 0) (lane "ocLongcat" "free" 0) (lane "ocDeepseekFlash" "paid" 5)))
        (one (list (lane "orNemotronUltraFree" "free" 5) (lane "nimNemotronUltra" "free" 5) (lane "ocLongcat" "free" 0)))
        (a (run (unit "low" false) (goodGates) none (list)))
        (b (run (unit "low" false) (goodGates) one (list)))
        (c (run (unit "high" false) (goodGates) (list (lane "ocDeepseekFlash" "paid" 0)) (list)))
        (d (run (unit "low" false) (goodGates) (list (lane "orNemotronUltraFree" "free" 5) (lane "ocLongcat" "free" 5) (lane "ocDeepseekFlash" "paid" 0))
                (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)))))]
    (do (assert (and (= a.action "await") (= a.awaitLane "orNemotronUltraFree")) "no free allowance awaits the first out-of-allowance eligible free lane")
        (assert (and (= b.action "await") (= b.awaitLane "ocLongcat")) "one family left awaits the lane of a second family")
        (assert (and (= c.action "await") (= c.awaitLane "ocDeepseekFlash") (= c.rung "R2")) "high risk with no paid allowance awaits the paid lane at R2")
        (assert (and (= d.action "await") (= d.rung "R2") (= (listLength d.verdicts) 2)) "a split with no R2 allowance awaits R2 and keeps the R1 verdicts")
        true))

fn testBlocked -> Bool
  (let [(r (run (unit "low" false) (goodGates) (pool)
             (list (pair "orNemotronUltraFree" (passReply)) (pair "ocLongcat" (failReply)) (pair "ocDeepseekFlash" "garbled") (pair "ccKimi31Pro" "garbled"))))
        (row (optionOr (listHead (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:escalate")) r.rows)) ""))]
    (do (assert (= r.action "blocked") "an R3 split is blocked for Claude")
        (assert (= r.rung "R3") "blocked at R3")
        (assert (stringStartsWith? row "(:escalate :unit U1") "an escalate row is emitted")
        (assert (stringContains? row ":disagree") "the escalate row names the disagreement")
        (assert (and (stringContains? row "orNemotronUltraFree pass") (stringContains? row "ocLongcat fail")) "the disagreement names both reviewers' verdicts")
        (assert (stringContains? row ":seen") "the escalate row names what was seen")
        (assert (and (stringContains? row ":to queue ") (not (stringContains? row ":to claude")) (stringContains? row ":tiers (claude)")) (str "the escalation goes to the queue with Claude as the last tier once the strong lane has been asked: " row))
        true))

fn testBrief -> Bool
  (let [(u (l/ReviewUnit :id "U1" :task "fix bound\nsee .asl/mem/plan.asn\nkey sk-or-abc123" :risk "low" :closureChanged false :writerAlias "x" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list)))
        (b (l/reviewBrief u "+ ok line\n+ TOKEN=abc\n+ path .asl/mem/x\n- gone" "(:receipt U1 :gates ())"))]
    (do (assert (stringContains? b "fix bound") "unit text is kept")
        (assert (stringContains? b "+ ok line") "diff excerpt is kept")
        (assert (not (stringContains? b ".asl/mem")) "no memory path or contents go out")
        (assert (not (stringContains? b "sk-or-")) "no key-looking text goes out")
        (assert (not (stringContains? b "TOKEN=")) "no token line goes out")
        (assert (listContains? (l/scrubLines "+ (let [toks (tokenize text)]" 10 120) "+ (let [toks (tokenize text)]") "tokenize identifier is not scrubbed as a secret")
        (assert (not (stringContains? b "\n")) "the brief is a single line")
        (assert (stringStartsWith? b "(:review :unit \"U1\"") "the brief is an ASN form")
        true))

fn gatewayAliases -> (List String)
  (stringSplit (stringJoin (list "flashLow flashHigh flashMedium opus astra agyOpus geminiApiFlash geminiApiFlashLite lagunaS ocGlmFlash"
    "ocMimoFlash ocDeepseekFlash ocKimi31Pro ccKimi31Pro orKimi31Pro vcKimi31Pro vcNemotronLightningFree"
    "vcLagunaFree vcBeamFree orNemotronUltraFree orNemotronSuperFree orGemma431Free ocMuse ocLongcat ocCatJam"
    "ocDeepseekPro ocGlm53 ocMinimaxM3 ccDeepseekFlash ccGlmFlash ccLingFlash ccLaguna ccMimoPro ccBeam ocBeam"
    "ccMinimaxFlash ccGlyph orLaguna orNorthCode orMinimaxFlash orNemotronLightning orNemotronSuperVl orDots3"
    "nimNemotronUltra nimNemotronLightning nimGlm53 nimGlm53Flash orNemotronUltra groqQwen mimoPro mimoFlash"
    "groqGptOss tgGlm53Flash tgBonsai ifmK2Horizon orDsFlash0731 orDs41Flash"
    "orNvidiaNemotron3NanoOmni30bA3bReasoningFree orOpenrouterFree orRecursiveFlintV10Free gmGemini3FlashPreview"
    "gmGemini31FlashLite gmGemini31FlashLitePreview gmGemini35Flash gmGemini36Flash gmGeminiFlashLiteLatest"
    "gmGemma426bA4bIt nimNvidiaNemotron3NanoOmni30bA3bReasoning nimNvidiaNemotron35BoltE4b"
    "nimNvidiaNemotron35SuperVl120bA12b nimOpenaiGptOss20b vcReflectionBeam ocClaudeHaiku55 ocGemini4Argon ocGlm51"
    "ocGlm52 ocGpt56Luna ocGpt6Luna ocGrok46 ocGrok47 ocHy3 ocHy4Preview ocIcemanContributorFree ocLongcat20"
    "ocMimoV25 ocMimoV26Pro ocMinimaxM25 ocMinimaxM27 ocMinimaxM31Flash ocMuseSpark12Contributor ocOmenAlpha"
    "ocQwen36Plus ocQwen37Max ocQwen37Plus ocQwen38Flash ocQwen38Max ocStep5Preview ccDeepseekDeepseekV4Flash"
    "ccDeepseekDeepseekV4FlashFast ccDeepseekDeepseekV4FlashVisionExp ccDeepseekDeepseekV4Pro"
    "ccDeepseekDeepseekV41FlashFast ccGoogleGemini37Flash ccGoogleGemini38Flash ccGpt56Luna ccGpt56Sol ccGpt6Luna"
    "ccMeituanLongcat20 ccMetaMuseSpark12 ccMetaMuseSpark12Contributor ccMetaMuseSpark13"
    "ccMetaMuseSpark13Contributor ccMetaMuseSparkOpen ccMinimaxMinimaxM31Flash ccMinimaxaiMinimaxM25"
    "ccMinimaxaiMinimaxM3 ccMistralMistralLarge4 ccMoonshotaiKimiK25 ccMoonshotaiKimiK26 ccMoonshotaiKimiK27Code"
    "ccMoonshotaiKimiK27CodeHighspeed ccMoonshotaiKimiK3 ccNvidiaNemotron3Ultra550bA55b ccNvidiaNemotron35SuperVl"
    "ccOrnithOrnith15122b ccQwenQwen36Plus ccQwenQwen37Flash ccQwenQwen37Max ccQwenQwen37Plus ccQwenQwen3827b"
    "ccQwenQwen38Flash ccQwenQwen38Max ccQwenQwen38Max0902 ccQwenQwen38MaxPrime ccQwenQwen38OmniFlash"
    "ccStepfunStep37Flash ccStepfunStep5Preview ccTencentHy4Preview ccXaiGrok45 ccXaiGrok46 ccXaiGrok47"
    "ccXiaomiMimoV26Flash ccXiaomiMimoV26ProUltraspeed ccZAiGlm53Flashx ccZaiOrgGlm5 ccZaiOrgGlm52"
    "ccZaiOrgGlm52Fast ccZaiOrgGlm53 ifmIfmJais3Mova36bA4b olBeam olGemma431b olGptOss120b olGptOss20b"
    "olNemotron3Nano30b olNemotron3Super olNemotron3Ultra") " ") " ")

fn unknownAliases -> (List String)
  (list "ocCatJam" "ocIcemanContributorFree" "ocOmenAlpha" "ccGlyph" "ccOrnithOrnith15122b" "orOpenrouterFree" "orRecursiveFlintV10Free" "orDots3")

fn testTokens -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))]
    (do (assert (= (l/tokensOf "ocDeepseekFlash") (list "oc" "deepseek" "flash")) "camelCase splits")
        (assert (= (l/tokensOf "claude-opus-5-5") (list "claude" "opus" "5" "5")) "separators and digits split")
        (assert (= (l/tokensOf "orDsFlash0731") (list "or" "ds" "flash" "0731")) "letter digit boundary splits")
        (assert (= (l/tokensOf "ccNvidiaNemotron35SuperVl") (list "cc" "nvidia" "nemotron" "35" "super" "vl")) "short acronym is one token")
        (assert (= (l/familyIn rs "ocWordsX") "") "ds inside words is not deepseek")
        (assert (= (l/familyIn rs "ocBeamer") "") "beam inside beamer is not reflection")
        (assert (= (l/familyIn rs "ocDarling") "") "ling inside darling is not inclusionai")
        (assert (= (l/familyIn rs "ocLing") "inclusionai") "ling as a whole token is")
        (assert (= (l/familyIn rs "ocGlmDeepseek") "") "two families make an alias unknown")
        (assert (= (l/familyIn rs "ocGpt6Luna") "openai") "two rows of one family resolve")
        true))

fn testCoverage -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))
        (all (l/coverageProblems rs (gatewayAliases) (unknownAliases)))]
    (do (assert (> (listLength (gatewayAliases)) 100) "the fixture holds the gateway alias list")
        (assert (listEmpty? all) (str "every gateway alias resolves to one family or is listed unknown: " (stringJoin all "; ")))
        (assert (not (listEmpty? (l/coverageProblems rs (list "ocMysteryModel") (list)))) "an unlisted unknown alias is a problem")
        (assert (not (listEmpty? (l/coverageProblems rs (list "ocGlmDeepseek") (list "ocGlmDeepseek")))) "an ambiguous alias is a problem even when listed")
        (assert (not (listEmpty? (l/coverageProblems rs (list "ocGlm53") (list "ocGlm53")))) "a stale unknown entry is a problem")
        true))

fn testRank -> Bool
  (let [(rs (l/familyRows (l/familyTableAsn)))
        (ls (list (l/Lane :alias "ocLongcat" :tier "free" :allowance 5 :quality 0)
                  (l/Lane :alias "orNemotronUltraFree" :tier "free" :allowance 5 :quality 7)
                  (l/Lane :alias "orGemma431Free" :tier "free" :allowance 5 :quality 9)
                  (l/Lane :alias "groqQwen" :tier "free" :allowance 5 :quality 7)))]
    (do (assert (= (map (fn [(x l/Lane)] -> String x.alias) (l/rankLanes ls)) (list "orGemma431Free" "orNemotronUltraFree" "groqQwen" "ocLongcat")) "higher quality first, ties keep caller order")
        (match (l/selectFree rs "flashHigh" ls)
          ((l/pickOk ps) (assert (= (map (fn [(x l/Lane)] -> String x.alias) ps) (list "orNemotronUltraFree" "groqQwen")) "R1 takes the best non-writer-family reviewers (gemma is the writer's family)"))
          ((l/pickAwait a w) (assert false "R1 should pick")))
        (match (l/selectFree rs "ocDeepseekFlash" ls)
          ((l/pickOk ps) (assert (= (map (fn [(x l/Lane)] -> String x.alias) ps) (list "orGemma431Free" "orNemotronUltraFree")) "R1 takes the two best quality lanes of different families"))
          ((l/pickAwait a w) (assert false "R1 should pick")))
        true))

fn ! runTests -> Bool
  (do (assert (testFamilies) "families")
      (assert (testTokens) "tokens")
      (assert (testCoverage) "coverage")
      (assert (testRank) "rank")
      (assert (testSelect) "selection")
      (assert (testVerdicts) "verdict parsing")
      (assert (testMerge) "merge rules")
      (assert (testSplitAndAbstain) "split and abstain")
      (assert (testFixCap) "fix cap")
      (assert (testRisk) "risk and closure")
      (assert (testAwait) "await")
      (assert (testBlocked) "blocked")
      (assert (testBrief) "brief")
      true)
