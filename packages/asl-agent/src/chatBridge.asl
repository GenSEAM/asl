(module aslAgent/chatBridge :x [ChatIngressEnvelope ChatBridgeState makeChatIngress initChatBridge streamVoiceToChat triggerBargeInAbort resolveAnaphoraDirective formatChatIngressAsn renderChatTelemetryAsn] :i [(asl-text/string :a s)])

(schema ChatIngressEnvelope (:f sessionId Str) (:f sourceVoice Bool) (:f rawTranscript Str) (:f cleanedPrompt Str) (:f detectedLocale Str) (:f intentArchetype Str) (:f anaphoraResolved Str) (:f timestampMs Int64))

(schema ChatBridgeState (:f activeSessionId Str) (:f isStreaming Bool) (:f bargeInCount Int64) (:f promptHistory (List ChatIngressEnvelope)))

fn makeChatIngress sessionId: Str raw: Str cleaned: Str locale: Str intent: Str anaphora: Str ts: Int64 -> ChatIngressEnvelope
  (ChatIngressEnvelope :sessionId sessionId :sourceVoice true :rawTranscript raw :cleanedPrompt cleaned :detectedLocale locale :intentArchetype intent :anaphoraResolved anaphora :timestampMs ts)

fn initChatBridge sessionId: Str -> ChatBridgeState
  (ChatBridgeState :activeSessionId sessionId :isStreaming false :bargeInCount 0 :promptHistory (list))

fn resolveAnaphoraDirective raw: Str lastPrompt: Str -> Str
  (let [(low (stringLower (stringTrim raw)))] (cond ((or (= low "run that again") (or (= low "запусти это снова") (or (= low "повтори") (= low "retry")))) lastPrompt) ((or (stringContains? low "fix it") (stringContains? low "исправь это")) (str "fix: " lastPrompt)) ((or (stringContains? low "apply it") (stringContains? low "примени это")) (str "apply: " lastPrompt)) (else raw)))

fn streamVoiceToChat bridge: ChatBridgeState envelope: ChatIngressEnvelope -> ChatBridgeState
  (let [(current bridge.promptHistory) (appended (listAppend current (list envelope))) (appendedLen (listLength appended)) (retained (if (> appendedLen 10) (listDrop appended (- appendedLen 10)) appended))] (with bridge :isStreaming true :promptHistory retained))

fn triggerBargeInAbort bridge: ChatBridgeState -> ChatBridgeState
  (with bridge :isStreaming false :bargeInCount (+ bridge.bargeInCount 1))

fn formatChatIngressAsn envelope: ChatIngressEnvelope -> Str
  (str "(:chat-ingress :session \"" envelope.sessionId "\" :intent \"" envelope.intentArchetype "\" :locale \"" envelope.detectedLocale "\" :prompt \"" envelope.anaphoraResolved "\")")

fn renderChatTelemetryAsn bridge: ChatBridgeState -> Str
  (let [(histLen (stringFromInt64 (listLength bridge.promptHistory))) (bCount (stringFromInt64 bridge.bargeInCount)) (streamStr (if bridge.isStreaming "true" "false"))] (str "(:chat-bridge :session \"" bridge.activeSessionId "\" :streaming " streamStr " :history-count " histLen " :barge-ins " bCount ")"))
