(module aslAgent/copilot :x [PointerKind PointerRef StagedProposal ptrDom ptrLog ptrAst ptrVision makePointer dereferencePointer! makeProposal stageProposal commitStagedProposal intentRecord intentQuery traceVerify!] :i [])

(enum PointerKind (:c ptrDom [] "HTML/VDOM tree perceptual pointer") (:c ptrLog [] "Subprocess or build execution log pointer") (:c ptrAst [] "Full file AST representation pointer") (:c ptrVision [] "Diagram or screenshot visual pointer"))

(schema PointerRef (:f id Str) (:f kind PointerKind) (:f summary Str) (:f blobHash Str))

(schema StagedProposal (:f branchId Str) (:f fileTarget Str) (:f proposalPayload Str) (:f isCommitted Bool))

fn makePointer id: Str kind: PointerKind summary: Str hash: Str -> PointerRef
  (PointerRef :id id :kind kind :summary summary :blobHash hash)

fn dereferencePointer! ptr: PointerRef query: Str -> Str
  (let [(actualData (fileRead ptr.id)) (hasMatch (stringContains? (stringLower (resultOr actualData "")) (stringLower query))) (resVal (if hasMatch "matched" "resolved"))] (str "(:fact :ptr \"" ptr.id "\" :query \"" query "\" :val \"" resVal "\" :summary \"" ptr.summary "\")"))

fn makeProposal branch: Str target: Str payload: Str -> StagedProposal
  (StagedProposal :branchId branch :fileTarget target :proposalPayload payload :isCommitted false)

fn stageProposal proposal: StagedProposal -> Str
  (str ".eddie/staging/" proposal.branchId "/" proposal.fileTarget)

fn commitStagedProposal proposal: StagedProposal -> StagedProposal
  (with proposal :isCommitted true)

fn intentRecord kind: Str id: Str title: Str anchor: Str -> Str
  (str "(:entity :id \"" id "\" :kind :" kind " :title \"" title "\" :anchor \"" anchor "\")")

fn intentQuery entityId: Str relation: Str -> Str
  (str "(:edge :src \"" entityId "\" :rel :" relation " :dst \"req:deterministic\")")

fn traceVerify! symbol: Str -> Bool
  (let [(intentData (fileRead ".asl/mem/intent.asn"))] (stringContains? (mt intentData ((ok s) s) ((err _) "")) symbol))
