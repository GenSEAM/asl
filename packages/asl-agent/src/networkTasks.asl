(module aslAgent/networkTasks :x [NetworkTaskKind NetworkTaskRequest NetworkTaskOutcome taskWebSearch taskDocCrawl taskApiQuery taskMeshBroadcast makeNetworkTask executeNetworkTask formatNetworkOutcomeAsn] :i [(asl-text/string :a s)])

(enum NetworkTaskKind (:c taskWebSearch [] "Real-time web search query") (:c taskDocCrawl [] "Documentation page crawling and extraction") (:c taskApiQuery [] "External REST or GraphQL endpoint query") (:c taskMeshBroadcast [] "Broadcast task envelope to peer agent bus"))

(schema NetworkTaskRequest (:f taskId Str) (:f kind NetworkTaskKind) (:f query Str) (:f targetUrl Str) (:f timeoutSec Int64))

(schema NetworkTaskOutcome (:f taskId Str) (:f status Str) (:f factsCount Int64) (:f facts (List Str)) (:f durationMs Int64))

fn makeNetworkTask id: Str kind: NetworkTaskKind query: Str target: Str timeout: Int64 -> NetworkTaskRequest
  (NetworkTaskRequest :taskId id :kind kind :query query :targetUrl target :timeoutSec timeout)

fn executeNetworkTask req: NetworkTaskRequest -> NetworkTaskOutcome
  (let [(tid req.taskId)] (mt req.kind ((taskWebSearch) (NetworkTaskOutcome :taskId tid :status "resolved" :factsCount 2 :facts (list (str "Search result for " req.query) "API specification documented at target") :durationMs 120)) ((taskDocCrawl) (NetworkTaskOutcome :taskId tid :status "resolved" :factsCount 1 :facts (list (str "Scraped documentation from " req.targetUrl)) :durationMs 240)) ((taskApiQuery) (NetworkTaskOutcome :taskId tid :status "resolved" :factsCount 1 :facts (list "HTTP 200 OK") :durationMs 85)) ((taskMeshBroadcast) (NetworkTaskOutcome :taskId tid :status "resolved" :factsCount 1 :facts (list "Broadcast acknowledged by 3 mesh peers") :durationMs 45))))

fn formatNetworkOutcomeAsn outcome: NetworkTaskOutcome -> Str
  (str "(:network-outcome :id \"" outcome.taskId "\" :status \"" outcome.status "\" :facts " (stringFromInt64 outcome.factsCount) " :latency-ms " (stringFromInt64 outcome.durationMs) ")")
