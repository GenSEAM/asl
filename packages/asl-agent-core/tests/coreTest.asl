(module agent-core/test :x [runTests] :i [(core :a core)])

fn testAgentContext -> Bool
  (let [(ctx (core/makeAgentContext "agent-1" "session-1" "sys prompt"))] (assert (= ctx.agentId "agent-1") "") (refute (!= ctx.agentId "agent-1") "Agent ID must refute mismatch") (assert (= ctx.sessionId "session-1") "") (refute (!= ctx.sessionId "session-1") "Session ID must refute mismatch") (assert (= ctx.systemPrompt "sys prompt") "") (assert (= (listLength ctx.messages) 0) "") (refute (> (listLength ctx.messages) 0) "Initial messages must refute non-empty") true)

fn testAddMessage -> Bool
  (let [(ctx (core/makeAgentContext "agent-1" "session-1" "sys prompt"))
        (msg (core/makeMessage "user" "hello" "u1"))
        (ctx2 (core/addMessage ctx msg))
        (firstMsg (optionOr (listGet ctx2.messages 0) (core/makeMessage "" "" "")))]
    (assert (= (listLength ctx2.messages) 1) "")
    (refute (= (listLength ctx2.messages) 0) "Messages must refute empty after add")
    (assert (= firstMsg.role "user") "")
    (refute (!= firstMsg.role "user") "Message role must refute non-user")
    (assert (= firstMsg.content "hello") "")
    (refute (!= firstMsg.content "hello") "Message content must refute divergence")
    true)

fn testEventBus -> Bool
  (let [(bus (core/emptyEventBus))
        (bus2 (core/publishEvent bus "topic1" "payload1"))
        (firstEvent (optionOr (listGet bus2.eventLog 0) ""))]
    (assert (= (listLength bus2.eventLog) 1) "")
    (refute (= (listLength bus2.eventLog) 0) "Event log must refute empty after publish")
    (assert (stringContains? firstEvent "topic1") "")
    (assert (stringContains? firstEvent "payload1") "")
    (refute (stringContains? firstEvent "topic2") "Event log must refute unpublished topic")
    true)

fn runTests -> Bool
  (and (testAgentContext) (and (testAddMessage) (testEventBus)))
