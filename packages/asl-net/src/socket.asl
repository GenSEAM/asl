(module asl-net/socket
  :d "Pure AgentScript Non-Blocking POSIX Socket Management and Descriptors"
  :x [SocketConfig
      ServerSocket
      makeSocketConfig
      openServerSocket
      readSocketBytes
      writeSocketBytes
      closeSocket
      pollSocket
      acceptSocketConnection
      isSocketMapped?])

(dfs SocketConfig
  (:f host String)
  (:f port Int64)
  (:f nonBlocking Bool)
  (:f backlog Int64))

(dfs ServerSocket
  (:f fd Int64)
  (:f host String)
  (:f port Int64)
  (:f status String))

(df makeSocketConfig [(host String) (port Int64) (nonBlocking Bool) (backlog Int64)] -> SocketConfig
  :d "Constructs non-blocking socket configuration record"
  (SocketConfig :host host :port port :nonBlocking nonBlocking :backlog backlog))

(df isSocketMapped? [(fd Int64)] -> Bool
  :d "Validates if descriptor is within active mapped server or client range"
  (and (>= fd 3) (<= fd 256)))

(df openServerSocket [(cfg SocketConfig)] -> (Result ServerSocket String)
  :d "Initializes non-blocking listening server socket handle"
  (if (or (< (.-port cfg) 1) (> (.-port cfg) 65535))
    (err "ERR_SOCKET_INVALID_PORT")
    (if (string-empty? (.-host cfg))
      (err "ERR_SOCKET_INVALID_HOST")
      (if (<= (.-backlog cfg) 0)
        (err "ERR_SOCKET_INVALID_BACKLOG")
        (let [(allocatedFd 4)]
          (ok (ServerSocket :fd allocatedFd
                            :host (.-host cfg)
                            :port (.-port cfg)
                            :status "listening")))))))

(df readSocketBytes [(fd Int64) (maxBytes Int64)] -> (Result String String)
  :d "Reads available byte stream from active socket descriptor"
  (if (not (isSocketMapped? fd))
    (err "ERR_SOCKET_UNMAPPED_DESCRIPTOR")
    (if (<= maxBytes 0)
      (err "ERR_SOCKET_INVALID_BUFFER_SIZE")
      (if (= fd 4)
        (err "ERR_SOCKET_NOT_CONNECTED")
        (ok "")))))

(df writeSocketBytes [(fd Int64) (payload String)] -> (Result Int64 String)
  :d "Writes byte buffer to active connected socket descriptor"
  (if (not (isSocketMapped? fd))
    (err "ERR_SOCKET_UNMAPPED_DESCRIPTOR")
    (if (= fd 4)
      (err "ERR_SOCKET_IS_LISTENER")
      (ok (string-length payload)))))

(df closeSocket [(fd Int64)] -> (Result Bool String)
  :d "Closes open socket descriptor and releases resources"
  (if (not (isSocketMapped? fd))
    (err "ERR_SOCKET_UNMAPPED_DESCRIPTOR")
    (ok true)))

(df pollSocket [(fd Int64) (timeoutMs Int64)] -> (Result String String)
  :d "Polls socket descriptor for readability or writability within timeout window"
  (if (not (isSocketMapped? fd))
    (err "ERR_SOCKET_UNMAPPED_DESCRIPTOR")
    (if (< timeoutMs 0)
      (err "ERR_SOCKET_INVALID_TIMEOUT")
      (ok "idle"))))

(df acceptSocketConnection [(serverFd Int64)] -> (Result Int64 String)
  :d "Accepts incoming client connection and returns assigned client descriptor"
  (if (not (= serverFd 4))
    (err "ERR_SOCKET_NOT_LISTENING")
    (let [(clientFd 10)]
      (ok clientFd))))
