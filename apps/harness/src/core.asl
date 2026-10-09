(module aslHarness/core :x [SourceDocument ClaimCitation VerificationResult CacheEntry makeSourceDocument findDocument] :i [])

(schema SourceDocument (:f docId Str) (:f uri Str) (:f content Str) (:f timestampEpoch I64))

(schema ClaimCitation (:f claimText Str) (:f docId Str) (:f exactQuote Str) (:f confidence F64))

(schema VerificationResult (:f verified Bool) (:f citation ClaimCitation) (:f failureReason Str))

(schema CacheEntry (:f namespace Str) (:f key Str) (:f promptHash Str) (:f response Str) (:f ttlSeconds I64))

fn makeSourceDocument docId: Str uri: Str content: Str timestampEpoch: I64 -> SourceDocument
  (SourceDocument :docId docId :uri uri :content content :timestampEpoch timestampEpoch)

fn findDocument docs: (List SourceDocument) targetId: Str -> (Option SourceDocument)
  (let [(matches (filter (fn [(d SourceDocument)] -> Bool (= d.docId targetId)) docs))] (listHead matches))
