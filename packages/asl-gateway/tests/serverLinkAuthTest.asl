(module aslGateway/tests/serverLinkAuthTest
  :x [runTests]
  :i [(server :a srv)])

; (:m :ref GW-LINK-AUTH-TRUSTED :do "the in-process link has no socket, so it is trusted: with gatewayServeToken in the secrets file linkSend! gets the routed answer, not the 401 serve auth gives a socket request")
fn ! drop! dir: String -> Bool
  (let [(_ (map (fn [(sub String)] -> Bool (ok? (pathRemove (str dir "/" sub)))) (list ".asl/gateway.asn" ".asl/secrets.asn" ".asl")))]
    (ok? (pathRemove dir)))

fn ! testLinkTrusted -> Bool
  (let [(dir (str "/tmp/gwLinkAuth-" (procSelf) "-" (nowNs)))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (_3 (fileWrite (str dir "/.asl/gateway.asn") "(:gateway :v 2 :providers ((:provider :id fixa :kind openai :base \"http://127.0.0.1:9/v1\" :keyEnv FIXA_KEY)) :models ((:model :id mA :provider fixa :name \"m-a\" :tier free)) :profiles ((:profile :id default :routes ((:intent any :chain (mA))))) :uses ((:use :for default :profile default)))\n"))
        (_4 (do (fileWrite (str dir "/.asl/secrets.asn") "(:secret :id gatewayServeToken :value \"linkTok-DDDD4444\")\n") (fileChmod (str dir "/.asl/secrets.asn") 384) true))
        (env (mapSet (mapEmpty) "HOME" dir))
        (opened (srv/linkOpen! env dir dir (list)))]
    (match opened
      ((err e) (do (drop! dir) (assert false (str "link opened: " e)) false))
      ((ok loop)
        (let [(sent (srv/linkSend! loop "GET" "/v1/models" (list) "" 5000))
              (answer (match (pairSecond sent) ((ok t) t) ((err e) e)))
              (cleaned (drop! dir))]
          (do
            (assert (not (stringContains? answer "ERR_AUTH")) (str "the in-process link is not asked for the serve token: " answer))
            (assert (not (stringContains? answer "401")) (str "no 401 on the link: " answer))
            (assert (not (stringContains? answer "linkTok-DDDD4444")) "the answer does not carry the token")
            cleaned)))))

; (:m :ref GW-UNPARSEABLE-CONFIG-LINK :do "linkOpen! on a HOME with no config keeps the default secrets path and then fails on the missing config itself (ERR_GATEWAY_NO_CONFIG); a config naming a missing :secretsFile is refused before any wiring (ERR_SECRETS_MISSING)")
fn ! testLinkRefusals -> Bool
  (let [(bare (str "/tmp/gwLinkBare-" (procSelf) "-" (nowNs)))
        (_ (dirCreate bare))
        (noConfig (srv/linkOpen! (mapSet (mapEmpty) "HOME" bare) bare bare (list)))
        (_2 (pathRemove bare))
        (gone (str "/tmp/gwLinkGone-" (procSelf) "-" (nowNs)))
        (_3 (dirCreate gone))
        (_4 (dirCreate (str gone "/.asl")))
        (_5 (fileWrite (str gone "/.asl/gateway.asn") "(:gateway :v 2 :secretsFile \"/tmp/gwLinkGone-no-such.asn\" :providers () :models () :profiles () :uses ())\n"))
        (missing (srv/linkOpen! (mapSet (mapEmpty) "HOME" gone) gone gone (list)))
        (_6 (do (pathRemove (str gone "/.asl/gateway.asn")) (pathRemove (str gone "/.asl")) (pathRemove gone) true))]
    (do
      (assert (match noConfig ((err e) (stringContains? e "ERR_GATEWAY_NO_CONFIG")) (_ false)) "no config at all: the default secrets path is kept and the missing config is the error")
      (assert (match missing ((err e) (stringContains? e "ERR_SECRETS_MISSING")) (_ false)) "a missing :secretsFile file refuses the link")
      true))

fn ! runTests -> Bool
  (let [(a (testLinkTrusted))
        (b (testLinkRefusals))]
    (and a b))
