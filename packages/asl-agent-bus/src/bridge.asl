(module aslAgentBus/bridge :x [ExternalToolCommand bridgeConnectExternal formatExternalToolSchema dispatchExternalCommand makeBridgeEvent] :i [(presence :a p)])

(schema ExternalToolCommand (:f action Str) (:f agentId Str) (:f roomName Str) (:f payload Str))

fn bridgeConnectExternal agentId: Str role: Str room: Str caps: (List Str) -> p/SwarmPeer
  (p/SwarmPeer :agentId agentId :role role :room room :status (p/statusIdle) :capabilities caps :lastPingEpoch 1757160000 :claims (list))

fn formatExternalToolSchema -> Str
  (str "{\n" "  \"name\": \"asl_swarm_bus\",\n" "  \"description\": \"Single entry point to connect, discover peers, and negotiate tasks on the ASL Swarm Bus\",\n" "  \"parameters\": {\n" "    \"type\": \"object\",\n" "    \"properties\": {\n" "      \"action\": { \"type\": \"string\", \"enum\": [\"join-room\", \"list-peers\", \"propose-task\", \"accept-task\", \"decline-task\"] },\n" "      \"room_name\": { \"type\": \"string\" },\n" "      \"payload\": { \"type\": \"string\" }\n" "    },\n" "    \"required\": [\"action\", \"room_name\"]\n" "  }\n" "}")

fn dispatchExternalCommand room: p/SwarmRoom cmd: ExternalToolCommand -> Str
  (let [(action cmd.action)] (cond ((= action "list-peers") (p/formatPresenceRoster room)) ((= action "join-room") (let [(peer (bridgeConnectExternal cmd.agentId "external-worker" cmd.roomName (list "general-tasks")))] (str "Successfully joined room " cmd.roomName " as " cmd.agentId))) (else (str "Acknowledged " action " for " cmd.agentId))))

(schema BridgeEvent (:f id Str) (:f src Str) (:f dst Str) (:f payload Str))

fn makeBridgeEvent id: Str src: Str dst: Str payload: Str -> BridgeEvent
  (BridgeEvent :id id :src src :dst dst :payload payload)
