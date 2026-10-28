(module aslGateway/tests/serverLinkAuthTest
  :x [runTests]
  :i [(server :a srv)])

; (:m :ref GW-LINK-AUTH-TRUSTED :do "the in-process link has no socket, so it is trusted: with gatewayServeToken in the secrets file linkSend! gets the routed answer, not the 401 serve auth gives a socket request")
fn ! drop! dir: String -> Bool
  (let [(_ (map (fn [(sub String)] -> Bool (ok? (pathRemove (str dir "/" sub)))) (list ".asl/gateway.asn" ".asl/secrets.asn" ".asl")))]
    (ok? (pathRemove dir)))

fn ! runTests -> Bool
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
