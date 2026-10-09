(module aslBrowserPlugin/meshClient :x [MeshNodeInfo MeshCommandPacket formatNodeRegistration formatMeshResponse parseMeshCommand] :i [(aslAgentBus/mesh :a m)])

(schema MeshNodeInfo (:f nodeId Str) (:f role Str) (:f transport Str) (:f capabilities (List Str)))

(schema MeshCommandPacket (:f fromNode Str) (:f toNode Str) (:f commandId Str) (:f actionName Str) (:f payload Str))

fn formatNodeRegistration nodeId: Str role: Str -> MeshNodeInfo
  (MeshNodeInfo :nodeId nodeId :role role :transport "wasm-channel" :capabilities (list "list-tabs" "get-dom" "search-tab" "crawl-links" "extract-text"))

fn formatMeshResponse cmdId: Str status: Str data: Str -> Str
  (str "(:mesh-response :command-id \"" cmdId "\" :status \"" status "\" :data \"" data "\")")

fn parseMeshCommand from: Str to: Str cmdId: Str act: Str payload: Str -> MeshCommandPacket
  (MeshCommandPacket :fromNode from :toNode to :commandId cmdId :actionName act :payload payload)
