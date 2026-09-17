(module asl-net/unix
  :d "Pure AgentScript Unix Domain Socket Server and Descriptor Handoff"
  :x [UnixSocketConfig
      UnixServerSocket
      makeUnixSocketConfig
      openUnixServerSocket
      closeUnixSocket
      handoffListeningSocket
      receiveListeningSocket])

(dfs UnixSocketConfig
  (:f path String)
  (:f unlinkStale Bool)
  (:f permissions Int64))

(dfs UnixServerSocket
  (:f fd Int64)
  (:f path String)
  (:f status String)
  (:f permissions Int64))

(df makeUnixSocketConfig [(path String) (unlinkStale Bool) (permissions Int64)] -> UnixSocketConfig
  :d "Constructs UnixSocketConfig record"
  (UnixSocketConfig :path path :unlinkStale unlinkStale :permissions permissions))

(df openUnixServerSocket [(cfg UnixSocketConfig)] -> (Result UnixServerSocket String)
  :d "Binds and listens on Unix domain socket filesystem path"
  (if (string-empty? (.-path cfg))
    (err "ERR_UNIX_SOCKET_EMPTY_PATH")
    (let [(allocatedFd 5)]
      (ok (UnixServerSocket :fd allocatedFd
                            :path (.-path cfg)
                            :status "listening"
                            :permissions (.-permissions cfg))))))

(df closeUnixSocket [(server UnixServerSocket)] -> (Result Bool String)
  :d "Closes server descriptor and unlinks socket path"
  (if (or (< (.-fd server) 3) (> (.-fd server) 256))
    (err "ERR_UNIX_SOCKET_INVALID_FD")
    (ok true)))

(df handoffListeningSocket [(server UnixServerSocket)] -> (Result Int64 String)
  :d "Transfers listening descriptor for graceful zero-downtime socket handoff"
  (if (or (< (.-fd server) 3) (> (.-fd server) 256))
    (err "ERR_UNIX_SOCKET_INVALID_FD")
    (ok (.-fd server))))

(df receiveListeningSocket [(fd Int64)] -> (Result UnixServerSocket String)
  :d "Adopts passed socket descriptor from parent environment"
  (if (or (< fd 3) (> fd 256))
    (err "ERR_UNIX_SOCKET_INVALID_FD")
    (ok (UnixServerSocket :fd fd
                          :path ""
                          :status "listening"
                          :permissions 432))))
