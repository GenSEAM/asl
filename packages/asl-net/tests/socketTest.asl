(module asl-net/tests/socketTest
  :x [runTests]
  :i [(asl-net/socket :a sock)
      (asl-net/unix :a unx)])

fn readExactly! fd: Int64 size: Int64 acc: String -> (Result String String)
  (if (>= (stringLength acc) size)
    (ok acc)
    (mt (sock/pollSocket fd 5000)
      ((err e) (err e))
      ((ok state)
        (if (= state "idle")
          (err (str "no bytes within 5 s after " (stringFromInt64 (stringLength acc)) " bytes"))
          (mt (sock/readSocketBytes fd (- size (stringLength acc)))
            ((err e) (err e))
            ((ok chunk)
              (if (= (stringLength chunk) 0)
                (err (str "end of stream after " (stringFromInt64 (stringLength acc)) " bytes"))
                (readExactly! fd size (str acc chunk)))))))))

fn openErr res: (Result sock/ServerSocket String) -> String
  (mt res ((ok _) "") ((err e) e))

fn unixErr res: (Result unx/UnixServerSocket String) -> String
  (mt res ((ok _) "") ((err e) e))

fn ! unixPath tag: String -> String
  (str "/tmp/asl-net-" (stringFromInt64 (procSelf)) "-" tag ".sock")

fn testLoopbackEcho! -> Bool
  (mt (sock/openServerSocket (sock/makeSocketConfig "127.0.0.1" 0 false))
    ((err e) (do (assert false (str "openServerSocket on an ephemeral loopback port: " e)) false))
    ((ok srv)
      (do
        (assert (> srv.port 0) "the listener reports the kernel-assigned port")
        (mt (sock/connectSocket srv.port)
          ((err e) (do (sock/closeSocket srv.fd) (assert false (str "connectSocket: " e)) false))
          ((ok client)
            (mt (sock/acceptSocketConnection srv.fd)
              ((err e) (do (sock/closeSocket client) (sock/closeSocket srv.fd) (assert false (str "acceptSocketConnection: " e)) false))
              ((ok conn)
                (let [(payload "asl-net loopback echo 0123456789\n")
                      (sent (sock/writeSocketBytes client payload))
                      (got (readExactly! conn (stringLength payload) ""))
                      (back (sock/writeSocketBytes conn (resultOr got "")))
                      (echoed (readExactly! client (stringLength payload) ""))
                      (_c (sock/closeSocket client))
                      (eof (sock/readSocketBytes conn 64))
                      (_s (sock/closeSocket conn))
                      (_l (sock/closeSocket srv.fd))]
                  (do
                    (assert (= (resultOr sent 0) (stringLength payload)) "client write reports every payload byte")
                    (assert (= (resultOr got "") payload) (str "server reads the bytes the client wrote: " (mt got ((ok s) s) ((err e) e))))
                    (assert (= (resultOr back 0) (stringLength payload)) "server write reports every echoed byte")
                    (assert (= (resultOr echoed "") payload) "client reads back the bytes the server echoed")
                    (assert (= (resultOr eof "unread") "") "server read after the client closed returns end of stream")
                    true)))))))))

fn testReadBound! -> Bool
  (mt (sock/openServerSocket (sock/makeSocketConfig "127.0.0.1" 0 false))
    ((err e) (do (assert false (str "openServerSocket: " e)) false))
    ((ok srv)
      (mt (sock/connectSocket srv.port)
        ((err e) (do (sock/closeSocket srv.fd) (assert false (str "connectSocket: " e)) false))
        ((ok client)
          (mt (sock/acceptSocketConnection srv.fd)
            ((err e) (do (sock/closeSocket client) (sock/closeSocket srv.fd) (assert false (str "acceptSocketConnection: " e)) false))
            ((ok conn)
              (let [(sent (sock/writeSocketBytes client "abcdef"))
                    (_c (sock/closeSocket client))
                    (_p (sock/pollSocket conn 5000))
                    (head (sock/readSocketBytes conn 2))
                    (rest (readExactly! conn 4 ""))
                    (_s (sock/closeSocket conn))
                    (_l (sock/closeSocket srv.fd))]
                (do
                  (assert (= (resultOr sent 0) 6) "client writes six bytes")
                  (assert (= (resultOr head "") "ab") (str "a 2-byte read returns the first 2 buffered bytes only: " (mt head ((ok s) s) ((err e) e))))
                  (assert (= (resultOr rest "") "cdef") (str "the remaining bytes stay buffered for the next read: " (mt rest ((ok s) s) ((err e) e))))
                  true))))))))

fn testPollAndNonBlockingAccept! -> Bool
  (mt (sock/openServerSocket (sock/makeSocketConfig "localhost" 0 true))
    ((err e) (do (assert false (str "openServerSocket non-blocking: " e)) false))
    ((ok srv)
      (let [(lfd srv.fd)]
        (do
          (assert (= (resultOr (sock/pollSocket lfd 0) "") "idle") "a listener with no pending connection polls idle")
          (assert (err? (sock/pollSocket lfd -1)) "a negative poll timeout is rejected")
          (assert (err? (sock/acceptSocketConnection lfd)) "a non-blocking listener fails accept with nothing pending instead of blocking")
          (mt (sock/connectSocket srv.port)
            ((err e) (do (sock/closeSocket lfd) (assert false (str "connectSocket: " e)) false))
            ((ok client)
              (do
                (assert (= (resultOr (sock/pollSocket lfd 1000) "") "readable") "a pending connection makes the listener readable")
                (mt (sock/acceptSocketConnection lfd)
                  ((err e) (do (sock/closeSocket client) (sock/closeSocket lfd) (assert false (str "accept after poll: " e)) false))
                  ((ok conn)
                    (let [(idle (sock/pollSocket conn 0))
                          (_w (sock/writeSocketBytes client "x"))
                          (ready (sock/pollSocket conn 1000))
                          (_c (sock/closeSocket client))
                          (_s (sock/closeSocket conn))
                          (_l (sock/closeSocket lfd))]
                      (do
                        (assert (= (resultOr idle "") "idle") "an accepted socket with no data polls idle")
                        (assert (= (resultOr ready "") "readable") "a written byte makes the peer readable")
                        true)))))))))))

fn testClosedDescriptorErrors! -> Bool
  (mt (sock/openServerSocket (sock/makeSocketConfig "127.0.0.1" 0 false))
    ((err e) (do (assert false (str "openServerSocket: " e)) false))
    ((ok srv)
      (let [(fd srv.fd)
            (sizeErr (mt (sock/readSocketBytes fd 0) ((ok _) "") ((err e) e)))
            (firstClose (sock/closeSocket fd))]
        (do
          (assert (= sizeErr "ERR_SOCKET_INVALID_BUFFER_SIZE") "a non-positive read size is rejected")
          (assert (resultOr firstClose false) "closing an open listener succeeds")
          (assert (err? (sock/readSocketBytes fd 16)) "reading a closed descriptor fails")
          (assert (err? (sock/writeSocketBytes fd "x")) "writing a closed descriptor fails")
          (assert (err? (sock/acceptSocketConnection fd)) "accepting on a closed descriptor fails")
          (assert (err? (sock/closeSocket fd)) "closing a descriptor twice fails")
          (assert (= (resultOr (sock/pollSocket fd 0) "") "error") "polling a closed descriptor reports the error branch, not idle or readable")
          true))))

fn ! testConfigValidation -> Bool
  (do
    (assert (= (openErr (sock/openServerSocket (sock/makeSocketConfig "127.0.0.1" 99999 false))) "ERR_SOCKET_INVALID_PORT") "a port above 65535 is rejected")
    (assert (= (openErr (sock/openServerSocket (sock/makeSocketConfig "127.0.0.1" -1 false))) "ERR_SOCKET_INVALID_PORT") "a negative port is rejected")
    (assert (= (openErr (sock/openServerSocket (sock/makeSocketConfig "" 0 false))) "ERR_SOCKET_INVALID_HOST") "an empty host is rejected")
    (assert (= (openErr (sock/openServerSocket (sock/makeSocketConfig "10.1.2.3" 0 false))) "ERR_SOCKET_UNSUPPORTED_HOST") "a host the loopback-only listener cannot bind is rejected")
    true)

fn testUnixEcho! -> Bool
  (let [(path (unixPath "echo"))]
    (mt (unx/openUnixServerSocket (unx/makeUnixSocketConfig path true 432))
      ((err e) (do (assert false (str "openUnixServerSocket: " e)) false))
      ((ok srv)
        (do
          (assert (= srv.path path) "the server records its socket path")
          (assert (= (mt (fileStat path) ((ok st) (mod st.mode 512)) ((err _) -1)) 432) "the socket file carries the configured 0660 mode")
          (mt (unx/connectUnixSocket path)
            ((err e) (do (unx/closeUnixSocket srv) (assert false (str "connectUnixSocket: " e)) false))
            ((ok client)
              (mt (sock/acceptSocketConnection srv.fd)
                ((err e) (do (sock/closeSocket client) (unx/closeUnixSocket srv) (assert false (str "accept on unix listener: " e)) false))
                ((ok conn)
                  (let [(payload "unix echo\n")
                        (_w (sock/writeSocketBytes client payload))
                        (got (readExactly! conn (stringLength payload) ""))
                        (_b (sock/writeSocketBytes conn (resultOr got "")))
                        (echoed (readExactly! client (stringLength payload) ""))
                        (_c (sock/closeSocket client))
                        (_s (sock/closeSocket conn))
                        (closed (unx/closeUnixSocket srv))]
                    (do
                      (assert (= (resultOr got "") payload) "the unix server reads the client bytes")
                      (assert (= (resultOr echoed "") payload) "the unix client reads the echo")
                      (assert (resultOr closed false) "closeUnixSocket succeeds")
                      (assert (not (fileExists? path)) "closeUnixSocket removes the socket path")
                      true))))))))))

fn testUnixStalePath! -> Bool
  (let [(path (unixPath "stale"))
        (plain (unixPath "plain"))]
    (mt (unx/openUnixServerSocket (unx/makeUnixSocketConfig path true 384))
      ((err e) (do (assert false (str "openUnixServerSocket: " e)) false))
      ((ok first)
        (let [(_f (sock/closeSocket first.fd))
              (kept (unx/openUnixServerSocket (unx/makeUnixSocketConfig path false 384)))
              (again (unx/openUnixServerSocket (unx/makeUnixSocketConfig path true 384)))
              (_p (fileWrite plain "not a socket"))
              (onPlain (unx/openUnixServerSocket (unx/makeUnixSocketConfig plain true 384)))
              (plainKept (fileExists? plain))
              (_r (pathRemove plain))]
          (do
            (assert (fileExists? path) "closing only the descriptor leaves the socket path behind")
            (assert (err? kept) "a stale socket path without unlinkStale fails to bind")
            (assert (ok? again) "unlinkStale removes the stale socket and binds again")
            (assert (err? onPlain) "unlinkStale does not remove a path that is not a socket")
            (assert plainKept "the non-socket file is left in place")
            (assert (= (unixErr (unx/openUnixServerSocket (unx/makeUnixSocketConfig "" true 384))) "ERR_UNIX_SOCKET_EMPTY_PATH") "an empty unix socket path is rejected")
            (assert (= (unixErr (unx/openUnixServerSocket (unx/makeUnixSocketConfig (unixPath "mode") true 4096))) "ERR_UNIX_SOCKET_INVALID_PERMISSIONS") "permissions beyond 0777 are rejected")
            (mt again
              ((ok s) (assert (resultOr (unx/closeUnixSocket s) false) "the rebound socket closes"))
              ((err _) (do (pathRemove path) ())))
            true)))))

fn ! runTests -> Bool
  (do
    (assert (testLoopbackEcho!) "testLoopbackEcho passed")
    (assert (testReadBound!) "testReadBound passed")
    (assert (testPollAndNonBlockingAccept!) "testPollAndNonBlockingAccept passed")
    (assert (testClosedDescriptorErrors!) "testClosedDescriptorErrors passed")
    (assert (testConfigValidation) "testConfigValidation passed")
    (assert (testUnixEcho!) "testUnixEcho passed")
    (assert (testUnixStalePath!) "testUnixStalePath passed")
    true)
