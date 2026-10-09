(module aslGateway/tests/omniIngressTest
  :x [testMultiProtocolNormalization testTargetEngineResolution testIngressDispatchAndValidation runTests]
  :i [(aslGateway/omniIngress :a oi)])

fn testMultiProtocolNormalization -> Bool
  (let [(reqSocket (oi/IngressRequest :protocol (oi/protoUnixSocket) :endpoint "/tmp/asl-engine.sock" :rawPayload "git commit -m 'fix buffer'" :authHeader "bearer-admin"))
        (reqHttp (oi/IngressRequest :protocol (oi/protoHttpRest) :endpoint "/api/asl/tasks" :rawPayload "search for symbols in fastKnowledgeCache" :authHeader "token-slm"))
        (reqCli (oi/IngressRequest :protocol (oi/protoTerminalCli) :endpoint "stdin" :rawPayload "daemon status" :authHeader ""))
        (reqVoice (oi/IngressRequest :protocol (oi/protoVoiceStream) :endpoint "mic0" :rawPayload "open browser and checkout cart" :authHeader "voice-print-user"))
        (frameSocket (oi/ingressNormalize reqSocket 10001))
        (frameHttp (oi/ingressNormalize reqHttp 10002))
        (frameCli (oi/ingressNormalize reqCli 10003))
        (frameVoice (oi/ingressNormalize reqVoice 10004))]
    (assert (= frameSocket.sourceProtocol "socket") "Socket source protocol matches")
    (assert (= frameSocket.domain ":codeTask") "Code task classified from socket")
    (assert (= frameSocket.targetEngine "worker-jail") "Target is worker jail for code modification")
    (assert (= frameSocket.principalId "bearer-admin") "Principal token preserved")

    (assert (= frameHttp.sourceProtocol "http") "HTTP source protocol matches")
    (assert (= frameHttp.domain ":research") "Research domain classified from HTTP")
    (assert (= frameHttp.targetEngine "in-process-fiber") "Target is in-process fiber for research")

    (assert (= frameCli.sourceProtocol "cli") "CLI source protocol matches")
    (assert (= frameCli.domain ":systemControl") "System control classified from CLI")
    (assert (= frameCli.targetEngine "daemon-control") "Target is daemon control for CLI")
    (assert (= frameCli.principalId "anonymous") "Anonymous principal when no auth header")

    (assert (= frameVoice.sourceProtocol "voice") "Voice source protocol matches")
    (assert (= frameVoice.domain ":browserAction") "Browser action classified from voice")
    (assert (= frameVoice.targetEngine "gateway-browser") "Target is gateway browser")
    true)

fn testTargetEngineResolution -> Bool
  (let [(eCode (oi/resolveTargetEngine ":codeTask"))
        (eRes (oi/resolveTargetEngine ":research"))
        (eBrowser (oi/resolveTargetEngine ":browserAction"))
        (eIdea (oi/resolveTargetEngine ":ideaCapture"))
        (eSync (oi/resolveTargetEngine ":crossProjectSync"))
        (eSys (oi/resolveTargetEngine ":systemControl"))]
    (assert (= eCode "worker-jail") "Code task targets worker-jail")
    (assert (= eRes "in-process-fiber") "Research targets in-process-fiber")
    (assert (= eBrowser "gateway-browser") "Browser targets gateway-browser")
    (assert (= eIdea "memory-notes") "Idea capture targets memory-notes")
    (assert (= eSync "sync-protocol") "Sync targets sync-protocol")
    (assert (= eSys "daemon-control") "System targets daemon-control")
    true)

fn testIngressDispatchAndValidation -> Bool
  (let [(validReq (oi/IngressRequest :protocol "http" :endpoint "/api/asl/notes" :rawPayload "note: remember to optimize AST cache" :authHeader "user1"))
        (invalidReq (oi/IngressRequest :protocol "" :endpoint "/api" :rawPayload "" :authHeader ""))
        (frame (oi/ingressNormalize validReq 20001))
        (receipt (oi/ingressDispatch frame))]
    (assert (oi/isIngressValid? validReq) "Valid request passes validation")
    (assert (not (oi/isIngressValid? invalidReq)) "Empty request fails validation")
    (assert (> (stringLength receipt) 0) "Dispatch receipt generated")
    (assert (= frame.domain ":ideaCapture") "Note classified as ideaCapture")
    (assert (= frame.targetEngine "memory-notes") "Idea routed to memory-notes")
    true)

fn runTests -> Bool
  (do
    (assert (testMultiProtocolNormalization) "Multi-protocol normalization must pass")
    (assert (testTargetEngineResolution) "Target engine resolution must pass")
    (assert (testIngressDispatchAndValidation) "Ingress dispatch and validation must pass")
    true)
