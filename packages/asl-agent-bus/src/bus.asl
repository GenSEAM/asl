(module asl-agent-bus/bus
  :doc "Inter-Agent Swarm Bus Protocol in ASL Nano"
  :export [AgentMessage BusEvent format-sse-event is-broadcast]
  :import [(core/strings :as s)])

(dfs AgentMessage
  (:field sender Str "sender id")
  (:field target Str "target id")
  (:field payload Str "ast payload")
  (:field timestamp I64 "unix epoch"))

(dfe BusEvent
  (:case direct [(msg AgentMessage)] "direct message")
  (:case broadcast [(msg AgentMessage)] "broadcast message")
  (:case ping [] "ping event"))

(df format-sse-event [(event-name Str) (data Str)] -> Str
  :doc "Formats SSE event payload"
  (s/concat (s/concat (s/concat "event: " event-name) "\ndata: ") (s/concat data "\n\n")))

(df is-broadcast [(event BusEvent)] -> Bool
  :doc "Checks if event is broadcast"
  (match event
    ((broadcast msg) true)
    (_ false)))
