(module asl-skyloom/core
  :d "SkyLoom protocol algebraic types and core frame logic."
  :x [Dialect FrameType ErrorCode is-control-frame requires-ack error-code-to-int is-nano-dialect default-wire-dialect])

(dfe Dialect
  (:c native-asl    [] "ASL S-expression AST format")
  (:c coord-asl     [] "ASL Coordination and Handoff AST dialect")
  (:c compact-token [] "High-density positional token stream")
  (:c polyglot-json [] "Conversational JSON with self-describing preamble"))

(dfe FrameType
  (:c handshake   [] "Peer capability and dialect negotiation")
  (:c data        [] "Application-level payload")
  (:c handoff     [] "Context-isolated task delegation and handoff")
  (:c yield       [] "Handoff completion, status, and artifact return")
  (:c spawn       [] "Direct agent process execution within scoped directory")
  (:c ack         [] "Positive delivery acknowledgement")
  (:c nack        [] "Negative delivery acknowledgement")
  (:c ping        [] "Liveness check")
  (:c pong        [] "Liveness response")
  (:c rendezvous  [] "Lonely-agent mailbox check and announcement")
  (:c leave       [] "Graceful departure"))

(dfe ErrorCode
  (:c peer-unreachable    [] "Target peer not found in registry")
  (:c lonely-queued       [] "No peers listening; message spooled in mailbox")
  (:c dialect-unsupported [] "Peer cannot decode requested wire dialect")
  (:c decode-failed       [] "Malformed frame or checksum failure")
  (:c type-mismatch       [] "Payload does not conform to expected schema")
  (:c timeout             [] "No response received within deadline")
  (:c stalled             [] "Peer heartbeat ceased mid-execution")
  (:c dead-letter         [] "Maximum retry attempts exceeded")
  (:c scope-violation     [] "Agent attempted access outside permitted directory scope")
  (:c handoff-rejected    [] "Target agent declined handoff contract"))

(df is-control-frame [(ft FrameType)] -> Bool
  :d "Returns true if the frame is a control frame rather than application data."
  (mt ft
    ((data)    false)
    ((handoff) false)
    ((yield)   false)
    (_         true)))

(df requires-ack [(ft FrameType)] -> Bool
  :d "Returns true if this frame type mandates an acknowledgement."
  (mt ft
    ((data)      true)
    ((handoff)   true)
    ((spawn)     true)
    ((handshake) true)
    (_           false)))

(df error-code-to-int [(err ErrorCode)] -> Int64
  :d "Converts error code to standard numeric wire code."
  (mt err
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

(df is-nano-dialect [(d Dialect)] -> Bool
  :d "Returns true if dialect is a dense nano-format (compact positional or coord AST)."
  (mt d
    ((compact-token) true)
    ((coord-asl)     true)
    (_               false)))

(df default-wire-dialect [] -> Dialect
  :d "Returns the default primary wire dialect for all agent-to-agent transmissions."
  (compact-token))
