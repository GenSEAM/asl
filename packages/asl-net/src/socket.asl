(module asl-net/socket :x [SocketConfig ServerSocket makeSocketConfig openServerSocket connectSocket acceptSocketConnection readSocketBytes writeSocketBytes closeSocket pollSocket])

(schema SocketConfig (:f host String) (:f port Int64) (:f nonBlocking Bool))

(schema ServerSocket (:f fd Int64) (:f host String) (:f port Int64) (:f status String))

fn makeSocketConfig host: String port: Int64 nonBlocking: Bool -> SocketConfig
  (SocketConfig :host host :port port :nonBlocking nonBlocking)

fn loopbackHost? host: String -> Bool
  (or (= host "127.0.0.1") (= host "localhost"))

fn ! applyBlocking fd: Int64 nonBlocking: Bool -> (Result Bool String)
  (if (not nonBlocking)
    (ok true)
    (mt (fdNonBlocking fd true)
      ((err e) (err (str "ERR_SOCKET_NONBLOCK: " e)))
      ((ok _) (ok true))))

fn ! openServerSocket cfg: SocketConfig -> (Result ServerSocket String)
  (cond
    ((or (< cfg.port 0) (> cfg.port 65535)) (err "ERR_SOCKET_INVALID_PORT"))
    ((stringEmpty? cfg.host) (err "ERR_SOCKET_INVALID_HOST"))
    ((not (loopbackHost? cfg.host)) (err "ERR_SOCKET_UNSUPPORTED_HOST"))
    (else
      (mt (tcpListen cfg.port)
        ((err e) (err (str "ERR_SOCKET_LISTEN: " e)))
        ((ok fd)
          (mt (sockLocalPort fd)
            ((err e) (do (fdClose fd) (err (str "ERR_SOCKET_LOCAL_PORT: " e))))
            ((ok bound)
              (mt (applyBlocking fd cfg.nonBlocking)
                ((err e) (do (fdClose fd) (err e)))
                ((ok _) (ok (ServerSocket :fd fd :host cfg.host :port bound :status "listening"))))))))))

fn ! connectSocket port: Int64 -> (Result Int64 String)
  (mt (tcpConnect port)
    ((err e) (err (str "ERR_SOCKET_CONNECT: " e)))
    ((ok fd) (ok fd)))

fn ! acceptSocketConnection serverFd: Int64 -> (Result Int64 String)
  (sockAccept serverFd)

fn ! readSocketBytes fd: Int64 maxBytes: Int64 -> (Result String String)
  (if (<= maxBytes 0)
    (err "ERR_SOCKET_INVALID_BUFFER_SIZE")
    (fdRead fd maxBytes))

fn ! writeSocketBytes fd: Int64 payload: String -> (Result Int64 String)
  (fdWrite fd payload)

fn ! closeSocket fd: Int64 -> (Result Bool String)
  (mt (fdClose fd)
    ((err e) (err e))
    ((ok _) (ok true)))

fn ! pollSocket fd: Int64 timeoutMs: Int64 -> (Result String String)
  (if (< timeoutMs 0)
    (err "ERR_SOCKET_INVALID_TIMEOUT")
    (mt (fdPoll (list (pair fd 1)) timeoutMs)
      ((err e) (err e))
      ((ok ready)
        (mt (listHead ready)
          ((none) (ok "idle"))
          ((some p) (ok (if (= (pairSecond p) 4) "error" "readable")))))))
