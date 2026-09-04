(module asl-harness/core
  :d "Epistemic core types, source documents, and cache definitions for ASL harness."
  :x [SourceDocument ClaimCitation VerificationResult CacheEntry
      make-source-document find-document]
  :i [])

(dfs SourceDocument
  (:f doc-id Str "Unique document identifier or URL")
  (:f uri Str "Origin URI or file path")
  (:f content Str "Full extracted textual content of the document")
  (:f timestamp-epoch I64 "Epoch timestamp of document retrieval"))

(dfs ClaimCitation
  (:f claim-text Str "Factual assertion statement made by agent or model")
  (:f doc-id Str "Identifier of referenced source document")
  (:f exact-quote Str "Verbatim snippet quoted from source document")
  (:f confidence F64 "Confidence rating between 0.0 and 1.0"))

(dfs VerificationResult
  (:f verified Bool "True if claim is strictly grounded in source quote")
  (:f citation ClaimCitation "Evaluated claim citation")
  (:f failure-reason Str "Reason for verification failure or empty on success"))

(dfs CacheEntry
  (:f namespace Str "Namespace isolating prompt and response context")
  (:f key Str "Cache key identifier")
  (:f prompt-hash Str "Hash or signature of the prompt")
  (:f response Str "Cached model response text")
  (:f ttl-seconds I64 "Time to live in seconds"))

(df make-source-document [(doc-id Str) (uri Str) (content Str) (timestamp-epoch I64)] -> SourceDocument
  :d "Factory for creating a verified SourceDocument."
  (SourceDocument
    :doc-id doc-id
    :uri uri
    :content content
    :timestamp-epoch timestamp-epoch))

(df find-document [(docs (List SourceDocument)) (target-id Str)] -> (Option SourceDocument)
  :d "Finds source document by identifier."
  (let [(matches (filter (fn [(d SourceDocument)] -> Bool (= (.-doc-id d) target-id)) docs))]
    (list-head matches)))
