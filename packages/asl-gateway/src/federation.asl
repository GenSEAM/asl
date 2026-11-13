(module aslGateway/federation
  :x [RemoteGateway remoteChatPath remoteRequest remoteStart! remoteFinish! remoteForward! federationAuth asnQuote serveTokenId secretsEnvOverlay! serveAuthError serveAuthOn? withoutAuthorization]
  :i [(aslGateway/upstream :a u) (aslGateway/secrets :a s)])

; (:m :ref GW-FEDERATION-20261027 :do "a provider whose upstream is another asl gateway: the request is an OpenAI-compatible chat call with the bearer token read from the secrets file by id; replies and errors come back as ASN receipts that name the provider and never a secret value, because every error text passes secretsRedact; the serving side checks the same bearer with federationAuth")

(schema RemoteGateway
  (:f id String)
  (:f base String)
  (:f secret String)
  (:f aslGateway Bool :default false))

fn remoteChatPath -> String
  "/v1/chat/completions"

fn asnQuote text: String -> String
  (str "\"" (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"") "\"")

; (:m :ref GWLOWS-LOWS :do "the client Accept goes back on only when the remote is declared an asl gateway (:aslGateway true); any other base is treated as a provider and keeps upstreamRequest's stripped headers, so a provider never sees application/asn+sexpr")
fn withClientAccept req: u/UpstreamRequest rg: RemoteGateway clientHeaders: (List (Pair String String)) -> u/UpstreamRequest
  (if rg.aslGateway
    (match (u/headerGet clientHeaders "Accept")
      ((some accept) (with req :headers (u/headerPut req.headers "Accept" accept)))
      ((none) req))
    req)

; (:m :ref ZAIACCEPT-LOWS :do "the hop to a remote asl gateway is the one upstream that speaks the gateway's own formats, so the client's Accept (application/asn+sexpr for an ASN reply) is put back after upstreamRequest strips it for providers")
fn remoteRequest store: s/SecretStore rg: RemoteGateway data: String clientHeaders: (List (Pair String String)) -> (Result u/UpstreamRequest String)
  (match (s/secretsGet store rg.secret)
    ((err e) (err e))
    ((ok token)
      (match (u/upstreamRequest rg.base (remoteChatPath) token data (u/headerPut clientHeaders "Content-Type" "application/json"))
        ((err e) (err (str "(:err :code ERR_REMOTE_REQUEST :provider " rg.id " :why " (asnQuote (s/secretsRedact store e)) ")")))
        ((ok req) (ok (withClientAccept req rg clientHeaders))))))

fn ! remoteStart! store: s/SecretStore rg: RemoteGateway data: String clientHeaders: (List (Pair String String)) env: (Map String String) timeoutSec: Float64 -> (Result u/UpstreamCall String)
  (match (remoteRequest store rg data clientHeaders)
    ((err e) (err e))
    ((ok req)
      (match (u/upstreamCallStart! req env timeoutSec)
        ((err f) (err (failureReceipt store rg f)))
        ((ok call) (ok call)))))

fn failureReceipt store: s/SecretStore rg: RemoteGateway f: u/UpstreamFailure -> String
  (match f
    ((u/toolAbsent tool detail) (str "(:err :code ERR_REMOTE_TOOL :provider " rg.id " :tool " tool " :why " (asnQuote (s/secretsRedact store detail)) ")"))
    ((u/transportFailure code errText) (str "(:err :code ERR_REMOTE_TRANSPORT :provider " rg.id " :exit " (stringFromInt64 code) " :why " (asnQuote (s/secretsRedact store errText)) ")"))
    ((u/httpFailure status reason body _) (str "(:err :code ERR_REMOTE_HTTP :provider " rg.id " :status " (stringFromInt64 status) " :reason " (asnQuote (s/secretsRedact store reason)) " :body " (asnQuote (s/secretsRedact store body)) ")"))
    ((u/protocolFailure detail) (str "(:err :code ERR_REMOTE_PROTOCOL :provider " rg.id " :why " (asnQuote (s/secretsRedact store detail)) ")")))

fn replyReceipt store: s/SecretStore rg: RemoteGateway r: u/UpstreamResponse -> String
  (str "(:remoteReply :provider " rg.id " :status " (stringFromInt64 r.status) " :body " (asnQuote (s/secretsRedact store r.body)) ")")

fn ! remoteFinish! store: s/SecretStore rg: RemoteGateway call: u/UpstreamCall deadlineSec: Float64 -> String
  (match (u/upstreamCallLoop! call (+ (u/wallSeconds!) deadlineSec))
    ((ok r) (replyReceipt store rg r))
    ((err f) (failureReceipt store rg f)))

fn ! remoteForward! store: s/SecretStore rg: RemoteGateway data: String clientHeaders: (List (Pair String String)) env: (Map String String) timeoutSec: Float64 -> String
  (match (remoteStart! store rg data clientHeaders env timeoutSec)
    ((err e) e)
    ((ok call) (remoteFinish! store rg call timeoutSec)))

fn federationAuth headers: (List (Pair String String)) expected: String -> (Result Unit String)
  (match (u/headerGet headers "Authorization")
    ((none) (err "(:err :code ERR_AUTH :status 401 :why missingBearer)"))
    ((some v)
      (if (and (not (stringEmpty? expected)) (s/secretsEqual? v (str "Bearer " expected))) (ok ())
        (err "(:err :code ERR_AUTH :status 401 :why badBearer)"))))

fn serveTokenId -> String
  "gatewayServeToken"

fn ! secretsEnvOverlay! path: String env: (Map String String) -> (Result (Map String String) String)
  (if (not (fileExists? path)) (ok env)
    (match (s/secretsLoad! path)
      ((err e) (err e))
      ((ok store) (ok (fold (fn [(acc (Map String String)) (id String)] -> (Map String String) (mapSet acc (s/secretEnvName id) (resultOr (s/secretsGet store id) ""))) env (s/secretsIds store))))))

; (:m :ref AUDIT12-B10 :do "true when a serve token is loaded, so the proxy fallback must not hand the caller's bearer on to the upstream")
fn serveAuthOn? env: (Map String String) -> Bool
  (mapHas? env (s/secretEnvName (serveTokenId)))

; (:m :ref AUDIT12-B10 :do "a raw HTTP request without its Authorization header lines; the body and every other header are untouched")
fn withoutAuthorization raw: String -> String
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) raw)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (rest (optionOr (stringSlice raw end (stringLength raw)) ""))]
        (str (stringJoin (filter (fn [(line String)] -> Bool (not (stringStartsWith? (stringLower line) "authorization:"))) (stringSplit head "\r\n")) "\r\n") rest))))

fn serveAuthError env: (Map String String) headers: (List (Pair String String)) -> (Option String)
  (match (mapGet env (s/secretEnvName (serveTokenId)))
    ((none) none)
    ((some token) (match (federationAuth headers token) ((err e) (some e)) ((ok _) none))))
