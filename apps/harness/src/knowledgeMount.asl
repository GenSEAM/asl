(module aslHarness/knowledgeMount :x [KnowledgeSource MountedKnowledge makeKnowledgeSource makeMountedKnowledge clampKnowledgePayload mountKnowledgeSource unmountKnowledgeSource isKnowledgeMounted? findMountedKnowledge toContextBlock toContextBlocks formatMountedKnowledgeAsn] :i [(contextAssembler :a ca) (asl-text/text :a txt)])

(schema KnowledgeSource (:f sourceId Str) (:f kind Str) (:f uri Str) (:f rawContent Str) (:f clampedTokens I64))

(schema MountedKnowledge (:f sourceId Str) (:f kind Str) (:f uri Str) (:f active Bool) (:f clampedPayload Str) (:f tokens I64) (:f pointerUri Str))

fn makeKnowledgeSource id: Str kind: Str uri: Str content: Str clampedTokens: I64 -> KnowledgeSource
  (let [(tokens (if (> clampedTokens 0) clampedTokens 350))] (KnowledgeSource :sourceId id :kind kind :uri uri :rawContent content :clampedTokens tokens))

fn makeMountedKnowledge id: Str kind: Str uri: Str active: Bool payload: Str tokens: I64 pointer: Str -> MountedKnowledge
  (MountedKnowledge :sourceId id :kind kind :uri uri :active active :clampedPayload payload :tokens tokens :pointerUri pointer)

fn clampKnowledgePayload content: Str uri: Str tokenCeiling: I64 -> MountedKnowledge
  (let [(ceiling (if (> tokenCeiling 0) tokenCeiling 350)) (rawTok (txt/estimateTokens content))] (if (<= rawTok ceiling) (MountedKnowledge :sourceId "" :kind "knowledge" :uri uri :active true :clampedPayload content :tokens rawTok :pointerUri "") (let [(maxChars (* ceiling 4)) (truncated (optionOr (stringSlice content 0 maxChars) content)) (ptr (str "(:ptr :uri \"" uri "\" :tokens " (stringFromInt64 rawTok) ")")) (clampedBody (str truncated "\n... [TRUNCATED - use (:ptr :uri \"" uri "\") for full slice]")) (clampedTok (txt/estimateTokens clampedBody))] (MountedKnowledge :sourceId "" :kind "knowledge" :uri uri :active true :clampedPayload clampedBody :tokens clampedTok :pointerUri ptr))))

fn mountKnowledgeSource mounted: (List MountedKnowledge) src: KnowledgeSource -> (List MountedKnowledge)
  (let [(id src.sourceId) (filtered (filter (fn [(mk MountedKnowledge)] -> Bool (not (= mk.sourceId id))) mounted)) (clamped (clampKnowledgePayload src.rawContent src.uri src.clampedTokens)) (newMounted (MountedKnowledge :sourceId id :kind src.kind :uri src.uri :active true :clampedPayload clamped.clampedPayload :tokens clamped.tokens :pointerUri clamped.pointerUri))] (listAppend filtered (list newMounted)))

fn unmountKnowledgeSource mounted: (List MountedKnowledge) sourceId: Str -> (List MountedKnowledge)
  (filter (fn [(mk MountedKnowledge)] -> Bool (not (= mk.sourceId sourceId))) mounted)

fn isKnowledgeMounted? mounted: (List MountedKnowledge) sourceId: Str -> Bool
  (if (listEmpty? mounted) false (let [(headMk (optionOr (listHead mounted) (makeMountedKnowledge "" "" "" false "" 0 ""))) (tailMk (optionOr (listTail mounted) (list)))] (if (and (= headMk.sourceId sourceId) headMk.active) true (isKnowledgeMounted? tailMk sourceId))))

fn findMountedKnowledge mounted: (List MountedKnowledge) sourceId: Str -> (Option MountedKnowledge)
  (if (listEmpty? mounted) (none) (let [(headMk (optionOr (listHead mounted) (makeMountedKnowledge "" "" "" false "" 0 ""))) (tailMk (optionOr (listTail mounted) (list)))] (if (= headMk.sourceId sourceId) (some headMk) (findMountedKnowledge tailMk sourceId))))

fn toContextBlock mk: MountedKnowledge -> ca/ContextBlock
  (let [(blockId (str "k-" mk.sourceId)) (content (if (stringEmpty? mk.pointerUri) mk.clampedPayload (str mk.clampedPayload "\n" mk.pointerUri))) (tok (txt/estimateTokens content))] (ca/makeContextBlock blockId "knowledge" tok content))

fn toContextBlocks mounted: (List MountedKnowledge) -> (List ca/ContextBlock)
  (map (fn [(mk MountedKnowledge)] -> ca/ContextBlock (toContextBlock mk)) (filter (fn [(mk MountedKnowledge)] -> Bool mk.active) mounted))

fn formatMountedKnowledgeAsn mk: MountedKnowledge -> Str
  (let [(escPtr (stringReplace mk.pointerUri "\"" "\\\""))] (str "(:mounted-knowledge\n" "  :source-id \"" mk.sourceId "\"\n" "  :kind \"" mk.kind "\"\n" "  :uri \"" mk.uri "\"\n" "  :active " (if mk.active "true" "false") "\n" "  :tokens " (stringFromInt64 mk.tokens) "\n" "  :pointer-uri \"" escPtr "\"\n" ")"))
