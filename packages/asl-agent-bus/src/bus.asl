(module asl-agent-bus/bus
  :d "Inter-Agent Swarm Bus Protocol in ASL"
  :x [AgentMessage BusEvent format-sse-event is-broadcast]
  :i [(core/strings :a s)])

(dfs AgentMessage
  (:f sender Str "sender id")
  (:f target Str "target id")
  (:f payload Str "ast payload")
  (:f timestamp I64 "unix epoch"))

(dfe BusEvent
  (:c direct [(msg AgentMessage)] "direct message")
  (:c broadcast [(msg AgentMessage)] "broadcast message")
  (:c ping [] "ping event"))

(df format-sse-event [(event-name Str) (data Str)] -> Str
  :d "Formats SSE event payload"
  (s/concat (s/concat (s/concat "event: " event-name) "\ndata: ") (s/concat data "\n\n")))

(df is-broadcast [(event BusEvent)] -> Bool
  :d "Checks if event is broadcast"
  (mt event
    ((broadcast msg) true)
    (_ false)))
