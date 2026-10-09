(module aslWebApiSearch/quota :x [EngineQuota QuotaTier QuotaTracker inspectEngineQuota parseQuotaHeaders isQuotaAvailable? trackRequest makeQuotaTracker] :i [])

(enum QuotaTier (:c alwaysAvailable [] "Free, keyless, public rate limit tier") (:c keyedFree [] "Free tier with API key and quota ceiling") (:c keyedMetered [] "Metered paid API tier"))

(schema EngineQuota (:f engineName Str) (:f tier QuotaTier) (:f hasKey Bool) (:f remainingQuota I64) (:f resetTimeSec I64) (:f isExhausted Bool))

(schema QuotaTracker (:f quotas (List EngineQuota)) (:f defaultTier QuotaTier) (:f totalRequests I64) (:f lastUpdated I64))

fn makeQuotaTracker quotas: (List EngineQuota) -> QuotaTracker
  (QuotaTracker :quotas quotas :defaultTier (alwaysAvailable) :totalRequests 0 :lastUpdated 0)

fn inspectEngineQuota engine: Str hasKey: Bool remaining: I64 -> EngineQuota
  (let [(e (stringLower engine)) (isOpen (or (= e "ddg") (or (= e "wikipedia") (or (= e "github") (or (= e "arxiv") (or (= e "hackernews") (= e "searxng")))))))] (if isOpen (EngineQuota :engineName engine :tier (alwaysAvailable) :hasKey true :remainingQuota -1 :resetTimeSec 0 :isExhausted false) (EngineQuota :engineName engine :tier (keyedFree) :hasKey hasKey :remainingQuota remaining :resetTimeSec 0 :isExhausted (or (not hasKey) (= remaining 0)))))

fn parseQuotaHeaders headers: (List Str) -> I64
  (if (listEmpty? headers) -1 (let [(h (optionOr (listHead headers) "")) (rest (optionOr (listTail headers) (list))) (lowerH (stringLower h))] (if (or (stringStartsWith? lowerH "x-ratelimit-remaining:") (stringStartsWith? lowerH "ratelimit-remaining:")) (let [(parts (stringSplit h ":")) (valPart (if (> (listLength parts) 1) (stringTrim (optionOr (listHead (listDrop parts 1)) "")) ""))] (optionOr (stringToInt64 valPart) -1)) (parseQuotaHeaders rest))))

fn isQuotaAvailable? quota: EngineQuota -> Bool
  (and quota.hasKey (not quota.isExhausted))

fn trackRequest tracker: QuotaTracker engine: Str timestamp: I64 -> QuotaTracker
  (let [(updatedQuotas (map (fn [(q EngineQuota)] -> EngineQuota (if (= q.engineName engine) (let [(rem q.remainingQuota) (newRem (if (> rem 0) (- rem 1) rem)) (exhausted (or q.isExhausted (and (> rem 0) (= newRem 0))))] (EngineQuota :engineName q.engineName :tier q.tier :hasKey q.hasKey :remainingQuota newRem :resetTimeSec q.resetTimeSec :isExhausted exhausted)) q)) tracker.quotas))] (with tracker :quotas updatedQuotas :totalRequests (+ tracker.totalRequests 1) :lastUpdated timestamp))
