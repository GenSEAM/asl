(module aslGateway/sync
  :x (ProjectSync ResearchSync ChannelSync AssetSync SyncReceipt computeContentHash formatProjectSync formatResearchSync formatChannelSync formatAssetSync formatSyncReceipt createSyncReceipt reconcileSync isProjectComplete?)
  :i ())

(schema ProjectSync
  (:f id Str)
  (:f name Str)
  (:f intentions Str)
  (:f stage Str)
  (:f projectType Str)
  (:f generationConfig Str))

(schema ResearchSync
  (:f topic Str)
  (:f audienceSegment Str)
  (:f depth Str)
  (:f findings (List Str))
  (:f claims (List Str))
  (:f sources (List Str))
  (:f viralityScore F64)
  (:f report Str))

(schema ChannelSync
  (:f id Str)
  (:f name Str)
  (:f platform Str)
  (:f styleGuide Str))

(schema AssetSync
  (:f id Str)
  (:f kind Str)
  (:f uri Str)
  (:f sha256 Str)
  (:f sizeBytes I64))

(schema SyncReceipt
  (:f status Str)
  (:f entityType Str)
  (:f entityId Str)
  (:f contentHash Str)
  (:f timestamp I64))

fn hashStep text: Str idx: I64 h: I64 -> I64
  (if (>= idx (stringLength text))
    h
    (let [(c (optionOr (stringSlice text idx (+ idx 1)) ""))
          (code (charCode c))
          (nextH (mod (+ (* (mod h 1000000007) 31) (+ idx code)) 1000000007))]
      (hashStep text (+ idx 1) nextH)))

fn computeContentHash text: Str -> Str
  (let [(len (stringLength text))
        (seed (hashStep text 0 5381))]
    (str "h" len "-" seed))

fn formatProjectSync p: ProjectSync -> Str
  (str "(:projectSync :id \"" p.id "\" :name \"" p.name "\" :intentions \"" p.intentions "\" :stage \"" p.stage "\" :projectType \"" p.projectType "\" :config \"" p.generationConfig "\")")

fn formatResearchSync r: ResearchSync -> Str
  (str "(:researchSync :topic \"" r.topic "\" :audience \"" r.audienceSegment "\" :depth \"" r.depth "\" :claims " (listLength r.claims) " :virality " r.viralityScore " :report \"" r.report "\")")

fn formatChannelSync c: ChannelSync -> Str
  (str "(:channelSync :id \"" c.id "\" :name \"" c.name "\" :platform \"" c.platform "\" :style \"" c.styleGuide "\")")

fn formatAssetSync a: AssetSync -> Str
  (str "(:assetSync :id \"" a.id "\" :kind \"" a.kind "\" :uri \"" a.uri "\" :sha256 \"" a.sha256 "\" :size " a.sizeBytes ")")

fn formatSyncReceipt r: SyncReceipt -> Str
  (str "(:syncReceipt :status :" r.status " :entity :" r.entityType " :id \"" r.entityId "\" :hash \"" r.contentHash "\" :ts " r.timestamp ")")

fn createSyncReceipt entityType: Str entityId: Str hash: Str -> SyncReceipt
  (SyncReceipt
    :status "ok"
    :entityType entityType
    :entityId entityId
    :contentHash hash
    :timestamp 1774137600)

fn reconcileSync localHash: Str incomingHash: Str -> (Pair Bool Str)
  (if (= localHash incomingHash)
    (pair true "noop")
    (pair false "update"))

fn isProjectComplete? p: ProjectSync -> Bool
  (= p.stage "complete")
