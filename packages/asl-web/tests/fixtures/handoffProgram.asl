(module asl/packages/asl-web/tests/fixtures/handoffProgram :x [main] :i [(asl-net/socket :a sk) (asl-net/unix :a unix) (asl-net/handoff :a ho)])

fn ! line label: String good: Bool evidence: String -> Bool
  (do (println (if good (str label " ok") (str label " FAIL " evidence))) good)

fn ! errText r: (Result Int64 String) -> String
  (mt r ((ok v) (str "ok " v)) ((err e) e))

fn ! serverErr r: (Result unix/UnixServerSocket String) -> String
  (mt r ((ok s) (str "ok fd " s.fd)) ((err e) e))

fn ! echo listener: Int64 path: String -> String
  (mt (unix/connectUnixSocket path)
    ((err e) (str "connect " e))
    ((ok cfd)
      (mt (sk/acceptSocketConnection listener)
        ((err e) (do (sk/closeSocket cfd) (str "accept " e)))
        ((ok afd)
          (let [(wrote (sk/writeSocketBytes cfd "ping"))
                (got (mt (sk/readSocketBytes afd 4) ((ok s) s) ((err e) (str "read " e))))]
            (do (sk/closeSocket afd) (sk/closeSocket cfd)
                (mt wrote ((err e) (str "write " e)) ((ok _) got))))))))

fn ! roundTrip server: unix/UnixServerSocket -> Bool
  (mt (ho/openHandoffChannel)
    ((err e) (line "channel" false e))
    ((ok ch)
      (let [(sent (ho/handoffListeningSocket server ch.sender))
            (sentOk (line "handoff sends the listener" (= sent (ok server.fd)) (errText sent)))
            (adopted (ho/receiveListeningSocket ch.receiver server.path))
            (closed (sk/closeSocket server.fd))]
        (do (ho/closeHandoffEnd ch.sender) (ho/closeHandoffEnd ch.receiver)
            (mt adopted
              ((err e) (line "receive adopts the listener" false e))
              ((ok got)
                (let [(fresh (line "received descriptor is a new one" (not (= got.fd server.fd)) (str got.fd)))
                      (same (line "adopted server keeps path, status and permissions" (and (= got.path server.path) (and (= got.status "listening") (= got.permissions 432))) (str got.path " " got.status " " got.permissions)))
                      (echoed (echo got.fd got.path))
                      (accepted (line "adopted listener accepts after the original fd closed" (= echoed "ping") echoed))
                      (closedAll (unix/closeUnixSocket got))]
                  (and (and sentOk (ok? closed)) (and (and fresh same) (and accepted (ok? closedAll)))))))))))

fn ! errorContracts dir: String server: unix/UnixServerSocket -> Bool
  (let [(stopped (unix/UnixServerSocket :fd server.fd :path server.path :status "closed" :permissions 432))
        (notListening (line "handoff refuses a server that is not listening" (= (ho/handoffListeningSocket stopped 0) (err "ERR_UNIX_HANDOFF_NOT_LISTENING")) (errText (ho/handoffListeningSocket stopped 0))))
        (badSend (ho/handoffListeningSocket server -1))
        (badSendOk (line "handoff over channel -1 is an EINVAL send error" (= badSend (err "ERR_UNIX_HANDOFF_SEND: io:22")) (errText badSend)))
        (badRecv (ho/receiveListeningSocket -1 server.path))
        (badRecvOk (line "receive on channel -1 is an EINVAL receive error" (= (serverErr badRecv) "ERR_UNIX_HANDOFF_RECV: io:22") (serverErr badRecv)))]
    (mt (ho/openHandoffChannel)
      ((err e) (line "error channel" false e))
      ((ok ch)
        (let [(_ (ho/closeHandoffEnd ch.sender))
              (empty (serverErr (ho/receiveListeningSocket ch.receiver server.path)))
              (emptyOk (line "receive from a closed sender carries no descriptor" (and (stringStartsWith? empty "ERR_UNIX_HANDOFF_RECV: io:") (not (= empty "ERR_UNIX_HANDOFF_RECV: io:22"))) empty))
              (_ (ho/closeHandoffEnd ch.receiver))]
          (mt (ho/openHandoffChannel)
            ((err e) (line "path channel" false e))
            ((ok ch2)
              (let [(_ (ho/handoffListeningSocket server ch2.sender))
                    (notSock (serverErr (ho/receiveListeningSocket ch2.receiver dir)))
                    (notSockOk (line "receive refuses a path that is not a socket" (= notSock "ERR_UNIX_HANDOFF_PATH: not a socket") notSock))]
                (do (ho/closeHandoffEnd ch2.sender) (ho/closeHandoffEnd ch2.receiver)
                    (and (and notListening badSendOk) (and (and badRecvOk emptyOk) notSockOk))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(dir (optionOr (listHead args) "."))
        (cfg (unix/makeUnixSocketConfig (str dir "/proxy.sock") true 432))]
    (mt (unix/openUnixServerSocket cfg)
      ((err e) (do (line "listen" false e) (ok 1)))
      ((ok server)
        (let [(errorsOk (errorContracts dir server))
              (tripOk (roundTrip server))]
          (ok (if (and errorsOk tripOk) 0 1))))))
