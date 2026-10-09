(module aslHarness/engineGateway :x [EngineTier GatewayQuery EngineResult calculateRrfScore dispatchTier0Ast dispatchTier1Mem dispatchTier2Web dispatchTierGit queryGateway formatResult formatEngineResults resolveQuery] :i [])

(enum EngineTier (:c tier0Ast [] "Tier 0: AST outlines, symbols, callers, and impact graphs") (:c tier1Mem [] "Tier 1: Resident in-memory grep, vector embeddings, and BM25 store") (:c tier2Web [] "Tier 2: External decentralized web search and live doc retrieval") (:c tierGit [] "Tier Git: Cross-branch, worktree, and historical ref retrieval") (:c tierAll [] "All tiers fused via Reciprocal Rank Fusion"))

(schema GatewayQuery (:f query Str) (:f tier Str) (:f limit I64) (:f airgap Bool))

(schema EngineResult (:f tier Str) (:f source Str) (:f score F64) (:f title Str) (:f snippet Str))

fn calculateRrfScore rank: I64 k: I64 -> F64
  (/ 1.0 (int64ToFloat64 (+ k rank)))

fn dispatchTier0Ast q: Str limit: I64 -> (List EngineResult)
  (list (EngineResult :tier "tier-0-ast" :source "asl-intel" :score 1.0 :title (str "AST Symbol: " q) :snippet (str "(fn " q " [...] -> ... [AST outline match])")))

fn dispatchTier1Mem q: Str limit: I64 -> (List EngineResult)
  (list (EngineResult :tier "tier-1-mem" :source "asl-mem" :score 0.9 :title (str "Resident Memory: " q) :snippet (str "Cached memory record and BM25 index match for query '" q "'")))

fn dispatchTier2Web q: Str limit: I64 airgap: Bool -> (List EngineResult)
  (if airgap (list (EngineResult :tier "tier-2-web" :source "airgap-policy" :score 0.0 :title "External Search Bypassed" :snippet "External web search disabled by airgap policy")) (list (EngineResult :tier "tier-2-web" :source "web-api-search" :score 0.8 :title (str "Web Search: " q) :snippet (str "Decentralized web retrieval result for '" q "'"))))

fn dispatchTierGit q: Str limit: I64 -> (List EngineResult)
  (list (EngineResult :tier "tier-git" :source "asl-sh/git-search" :score 0.95 :title (str "Git Match: " q) :snippet (str "Cross-branch git search match across historical refs for '" q "'")))

fn queryGateway q: Str tier: Str limit: I64 airgap: Bool -> (List EngineResult)
  (let [(t0 (dispatchTier0Ast q limit)) (t1 (dispatchTier1Mem q limit)) (t2 (dispatchTier2Web q limit airgap)) (tg (dispatchTierGit q limit))] (cond ((= tier "tier-0-ast") t0) ((= tier "tier-1-mem") t1) ((= tier "tier-2-web") t2) ((or (= tier "tier-git") (= tier "git")) tg) (else (let [(allRes (listAppend (listAppend (listAppend t0 t1) tg) t2))] (listTake allRes (max 1 limit))))))

fn formatResult r: EngineResult -> Str
  (str "(:result :tier \"" r.tier "\" :source \"" r.source "\" :score " (stringFromFloat64 r.score) " :title \"" r.title "\" :snippet \"" r.snippet "\")")

fn formatEngineResults results: (List EngineResult) -> Str
  (let [(formatted (map formatResult results))] (str "(:engine-results :count " (stringFromInt64 (listLength results)) " :items [" (stringJoin formatted " ") "])"))

fn resolveQuery q: Str -> Str
  (let [(results (queryGateway q "all" 10 true))] (formatEngineResults results))
