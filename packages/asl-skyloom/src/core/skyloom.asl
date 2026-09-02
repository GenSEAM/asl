(module asl-skyloom/core
  :doc "SkyLoom protocol algebraic types and core frame logic."
  :export [Dialect FrameType ErrorCode is-control-frame requires-ack error-code-to-int is-nano-dialect default-wire-dialect])

(defenum Dialect
  (:case native-asl    [] "ASL S-expression AST format")
  (:case coord-asl     [] "ASL Coordination and Handoff AST dialect")
  (:case compact-token [] "High-density positional token stream")
  (:case polyglot-json [] "Conversational JSON with self-describing preamble"))

(defenum FrameType
  (:case handshake   [] "Peer capability and dialect negotiation")
  (:case data        [] "Application-level payload")
  (:case handoff     [] "Context-isolated task delegation and handoff")
  (:case yield       [] "Handoff completion, status, and artifact return")
  (:case spawn       [] "Direct agent process execution within scoped directory")
  (:case ack         [] "Positive delivery acknowledgement")
  (:case nack        [] "Negative delivery acknowledgement")
  (:case ping        [] "Liveness check")
  (:case pong        [] "Liveness response")
  (:case rendezvous  [] "Lonely-agent mailbox check and announcement")
  (:case leave       [] "Graceful departure"))

(defenum ErrorCode
  (:case peer-unreachable    [] "Target peer not found in registry")
  (:case lonely-queued       [] "No peers listening; message spooled in mailbox")
  (:case dialect-unsupported [] "Peer cannot decode requested wire dialect")
  (:case decode-failed       [] "Malformed frame or checksum failure")
  (:case type-mismatch       [] "Payload does not conform to expected schema")
  (:case timeout             [] "No response received within deadline")
  (:case stalled             [] "Peer heartbeat ceased mid-execution")
  (:case dead-letter         [] "Maximum retry attempts exceeded")
  (:case scope-violation     [] "Agent attempted access outside permitted directory scope")
  (:case handoff-rejected    [] "Target agent declined handoff contract"))

(defun is-control-frame [(ft FrameType)] -> Bool
  :doc "Returns true if the frame is a control frame rather than application data."
  (match ft
    ((data)    false)
    ((handoff) false)
    ((yield)   false)
    (_         true)))

(defun requires-ack [(ft FrameType)] -> Bool
  :doc "Returns true if this frame type mandates an acknowledgement."
  (match ft
    ((data)      true)
    ((handoff)   true)
    ((spawn)     true)
    ((handshake) true)
    (_           false)))

(defun error-code-to-int [(err ErrorCode)] -> Int64
  :doc "Converts error code to standard numeric wire code."
  (match err
    ((peer-unreachable)    1001)
    ((lonely-queued)       1002)
    ((dialect-unsupported) 1003)
    ((decode-failed)       1004)
    ((type-mismatch)       1005)
    ((timeout)             1006)
    ((stalled)             1007)
    ((dead-letter)         1008)
    ((scope-violation)     1009)
    ((handoff-rejected)    1010)))

(defun is-nano-dialect [(d Dialect)] -> Bool
  :doc "Returns true if dialect is a dense nano-format (compact positional or coord AST)."
  (match d
    ((compact-token) true)
    ((coord-asl)     true)
    (_               false)))

(defun default-wire-dialect [] -> Dialect
  :doc "Returns the default primary wire dialect for all agent-to-agent transmissions."
  (compact-token))
