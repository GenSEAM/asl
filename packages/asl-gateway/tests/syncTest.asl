(module aslGateway/tests/syncTest
  :x (testProjectSync testResearchSync testChannelSync testAssetSync testContentHash testSyncReconciliation runTests)
  :i ((sync :a s)))

fn testProjectSync -> Bool
  (let ((p (s/ProjectSync
             :id "proj-001"
             :name "Viral Short Video"
             :intentions "Create high-retention technical breakdown"
             :stage "building"
             :projectType "video"
             :generationConfig "(:cfg :fps 30 :w 1080 :h 1920)"))
        (formatted (s/formatProjectSync p)))
    (do
      (assert (= p.id "proj-001") "Project ID must match")
      (assert (= p.stage "building") "Stage must match")
      (assert (not (s/isProjectComplete? p)) "Project in building stage is not complete")
      (assert (stringContains? formatted ":projectSync") "Must format as projectSync S-expression")
      (assert (stringContains? formatted "Viral Short Video") "Formatted string must contain name")
      true))

fn testResearchSync -> Bool
  (let ((r (s/ResearchSync
             :topic "Dyck-1 Parsing"
             :audienceSegment "Agentic Engineers"
             :depth "deep"
             :findings (list "O(1) counter" "zero pushdown")
             :claims (list "lossless roundtrip" "token efficient")
             :sources (list "ADR0081" "D102")
             :viralityScore 0.88
             :report "Formal verification proves Dyck-1 superior for M2M communication."))
        (formatted (s/formatResearchSync r)))
    (do
      (assert (= r.topic "Dyck-1 Parsing") "Topic must match")
      (assert (= (listLength r.claims) 2) "Claims count must be 2")
      (assert (stringContains? formatted ":researchSync") "Must format as researchSync S-expression")
      (assert (stringContains? formatted "Dyck-1 Parsing") "Formatted string must contain topic")
      true))

fn testChannelSync -> Bool
  (let ((c (s/ChannelSync
             :id "chan-tech-01"
             :name "AgentScript Tech"
             :platform "youtube"
             :styleGuide "(:font \"Inter\" :palette \"dark\")"))
        (formatted (s/formatChannelSync c)))
    (do
      (assert (= c.id "chan-tech-01") "Channel ID must match")
      (assert (= c.platform "youtube") "Platform must be youtube")
      (assert (stringContains? formatted ":channelSync") "Must format as channelSync")
      true))

fn testAssetSync -> Bool
  (let ((a (s/AssetSync
             :id "asset-999"
             :kind "video"
             :uri "storage://assets/out.mp4"
             :sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
             :sizeBytes 1048576))
        (formatted (s/formatAssetSync a)))
    (do
      (assert (= a.kind "video") "Asset kind must be video")
      (assert (= a.sizeBytes 1048576) "Asset size must be 1MB")
      (assert (stringContains? formatted ":assetSync") "Must format as assetSync")
      true))

fn testContentHash -> Bool
  (let ((h1 (s/computeContentHash "identical payload content"))
        (h2 (s/computeContentHash "identical payload content"))
        (h3 (s/computeContentHash "different payload content")))
    (do
      (assert (= h1 h2) "Deterministic hashing must produce equal hashes for identical content")
      (assert (not (= h1 h3)) "Distinct content must produce distinct hashes")
      true))

fn testSyncReconciliation -> Bool
  (let ((h1 "h25-1234567")
        (h2 "h25-1234567")
        (h3 "h30-9876543")
        (match (s/reconcileSync h1 h2))
        (mismatch (s/reconcileSync h1 h3))
        (receipt (s/createSyncReceipt "project" "proj-001" h1))
        (formattedReceipt (s/formatSyncReceipt receipt)))
    (do
      (assert (pairFirst match) "Identical hashes must reconcile as true")
      (assert (= (pairSecond match) "noop") "Identical hashes require noop")
      (assert (not (pairFirst mismatch)) "Different hashes must reconcile as false")
      (assert (= (pairSecond mismatch) "update") "Different hashes require update")
      (assert (= receipt.status "ok") "Receipt status must be ok")
      (assert (stringContains? formattedReceipt ":syncReceipt") "Receipt must format as S-expression")
      true))

fn runTests -> Bool
  (and (testProjectSync)
    (and (testResearchSync)
      (and (testChannelSync)
        (and (testAssetSync)
          (and (testContentHash)
            (testSyncReconciliation))))))
