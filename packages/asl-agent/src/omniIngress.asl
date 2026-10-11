(module aslAgent/omniIngress
  :x [IngressRequest NormalizedIntentFrame
      protoUnixSocket protoHttpRest protoTerminalCli protoVoiceStream
      resolveTargetEngine ingressNormalize ingressDispatch isIngressValid?]
  :i [(aslAgent/omniIntent :a oi)])

(schema IngressRequest
  (:f protocol Str)
  (:f endpoint Str)
  (:f rawPayload Str)
  (:f authHeader Str))

(schema NormalizedIntentFrame
  (:f domain Str)
  (:f sourceProtocol Str)
  (:f principalId Str)
  (:f intentPayload Str)
  (:f targetEngine Str)
  (:f timestamp I64))

fn protoUnixSocket -> Str
  "socket"

fn protoHttpRest -> Str
  "http"

fn protoTerminalCli -> Str
  "cli"

fn protoVoiceStream -> Str
  "voice"

fn resolveTargetEngine domain: Str -> Str
  (if (= domain ":codeTask")
    "worker-jail"
    (if (= domain ":research")
      "in-process-fiber"
      (if (= domain ":browserAction")
        "gateway-browser"
        (if (= domain ":ideaCapture")
          "memory-notes"
          (if (= domain ":crossProjectSync")
            "sync-protocol"
            (if (= domain ":systemControl")
              "daemon-control"
              "in-process-fiber"))))))

fn ingressNormalize req: IngressRequest timestamp: I64 -> NormalizedIntentFrame
  (let [(proto req.protocol)
        (payload req.rawPayload)
        (auth req.authHeader)
        (intent (oi/classifyOmniIntent payload))
        (domain (oi/domainToString intent.domain))
        (principal (if (> (stringLength auth) 0) auth "anonymous"))
        (engine (resolveTargetEngine domain))]
    (NormalizedIntentFrame
      :domain domain
      :sourceProtocol proto
      :principalId principal
      :intentPayload payload
      :targetEngine engine
      :timestamp timestamp))

fn ingressDispatch frame: NormalizedIntentFrame -> Str
  (str "(:ingress-receipt :protocol \"" frame.sourceProtocol
       "\" :domain \"" frame.domain
       "\" :target \"" frame.targetEngine
       "\" :status :routed)")

fn isIngressValid? req: IngressRequest -> Bool
  (and (> (stringLength req.protocol) 0)
       (> (stringLength req.rawPayload) 0))
