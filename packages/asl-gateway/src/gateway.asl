(module aslGateway/gateway
  :x [GatewayConfig GatewayResponse makeGatewayConfig rateLimitCheck rateLimitCheckWithTime quarantineThinkingTags dispatchGatewayRequest]
  :i [(server :a srv)
      (wire :a wire)])

(schema GatewayConfig
  (:f maxRequestsPerMinute Int64)
  (:f burstLimit Int64)
  (:f currentTokens Int64)
  (:f upstreamMeshUrl String)
  (:f requireAuth Bool)
  (:f lastRefillTimestamp Int64))

(schema GatewayResponse
  (:f status Int64)
  (:f body String)
  (:f headers (List String))
  (:f quarantinedThink String)
  (:f isRateLimited Bool))

fn makeGatewayConfig maxRpm: Int64 burst: Int64 upstream: String auth: Bool -> GatewayConfig
  (let [(boundedRpm (if (<= maxRpm 0) 60 maxRpm))
        (boundedBurst (if (<= burst 0) 10 burst))]
    (GatewayConfig
      :maxRequestsPerMinute boundedRpm
      :burstLimit boundedBurst
      :currentTokens boundedBurst
      :upstreamMeshUrl upstream
      :requireAuth auth
      :lastRefillTimestamp 0))

fn rateLimitCheckWithTime cfg: GatewayConfig cost: Int64 now: Int64 -> (Pair GatewayConfig Bool)
  (let [(lastRefill cfg.lastRefillTimestamp)
        (elapsed (if (> now lastRefill) (- now lastRefill) 0))
        (tokensToAdd (/ (* elapsed cfg.maxRequestsPerMinute) 60))
        (refilled (min (+ cfg.currentTokens tokensToAdd) cfg.burstLimit))
        (nextRefill (if (> tokensToAdd 0) now lastRefill))]
    (if (>= refilled cost)
      (let [(updatedCfg (with cfg :currentTokens (- refilled cost) :lastRefillTimestamp nextRefill))]
        (pair updatedCfg true))
      (pair (with cfg :currentTokens refilled :lastRefillTimestamp nextRefill) false)))

fn rateLimitCheck cfg: GatewayConfig cost: Int64 -> (Pair GatewayConfig Bool)
  (let [(cur cfg.currentTokens)]
    (if (>= cur cost)
      (let [(updatedCfg (with cfg :currentTokens (- cur cost)))]
        (pair updatedCfg true))
      (pair cfg false)))

fn quarantineThinkingTags text: String -> (Pair String String)
  (srv/extractThinkBlocks text)

fn dispatchGatewayRequest cfg: GatewayConfig path: String rawPayload: String apiKey: String -> (Pair GatewayConfig GatewayResponse)
  (if (and cfg.requireAuth (stringEmpty? apiKey))
    (pair cfg (GatewayResponse
                :status 401
                :body "(:error :code 401 :message \"Unauthorized: missing API key\")"
                :headers (list "Content-Type: application/asn+sexpr")
                :quarantinedThink ""
                :isRateLimited false))
    (let [(rlCheck (rateLimitCheck cfg 1))
          (nextCfg (pairFirst rlCheck))
          (isAllowed (pairSecond rlCheck))]
      (if (not isAllowed)
        (pair nextCfg (GatewayResponse
                        :status 429
                        :body "(:error :code 429 :message \"Too Many Requests: rate limit exceeded\")"
                        :headers (list "Content-Type: application/asn+sexpr" "Retry-After: 60")
                        :quarantinedThink ""
                        :isRateLimited true))
        (let [(quarantine (quarantineThinkingTags rawPayload))
              (thinkBlock (pairFirst quarantine))
              (cleanPayload (pairSecond quarantine))
              (meshResponse (str "(:mesh-response :upstream \"" cfg.upstreamMeshUrl "\" :path \"" path "\" :payload \"" cleanPayload "\")"))]
          (pair nextCfg (GatewayResponse
                          :status 200
                          :body meshResponse
                          :headers (list "Content-Type: application/asn+sexpr" "X-Gateway-Tier: L7-Edge")
                          :quarantinedThink thinkBlock
                          :isRateLimited false))))))
