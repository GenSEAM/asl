(module asl-net/unix :x [UnixSocketConfig UnixServerSocket makeUnixSocketConfig openUnixServerSocket connectUnixSocket closeUnixSocket])

(schema UnixSocketConfig (:f path String) (:f unlinkStale Bool) (:f permissions Int64))

(schema UnixServerSocket (:f fd Int64) (:f path String) (:f status String) (:f permissions Int64))

fn makeUnixSocketConfig path: String unlinkStale: Bool permissions: Int64 -> UnixSocketConfig
  (UnixSocketConfig :path path :unlinkStale unlinkStale :permissions permissions)

fn socketMode? mode: Int64 -> Bool
  (= (mod (/ mode 4096) 16) 12)

fn ! removeStaleSocket! cfg: UnixSocketConfig -> (Result Bool String)
  (if (not cfg.unlinkStale)
    (ok false)
    (mt (fileLstat cfg.path)
      ((err _) (ok false))
      ((ok st)
        (if (not (socketMode? st.mode))
          (ok false)
          (mt (pathRemove cfg.path)
            ((err e) (err (str "ERR_UNIX_SOCKET_UNLINK: " e)))
            ((ok _) (ok true)))))))

fn ! openUnixServerSocket cfg: UnixSocketConfig -> (Result UnixServerSocket String)
  (cond
    ((stringEmpty? cfg.path) (err "ERR_UNIX_SOCKET_EMPTY_PATH"))
    ((or (< cfg.permissions 0) (> cfg.permissions 511)) (err "ERR_UNIX_SOCKET_INVALID_PERMISSIONS"))
    (else
      (mt (removeStaleSocket! cfg)
        ((err e) (err e))
        ((ok _)
          (mt (unixListen cfg.path)
            ((err e) (err (str "ERR_UNIX_SOCKET_LISTEN: " e)))
            ((ok fd)
              (mt (fileChmod cfg.path cfg.permissions)
                ((err e) (do (fdClose fd) (pathRemove cfg.path) (err (str "ERR_UNIX_SOCKET_CHMOD: " e))))
                ((ok _) (ok (UnixServerSocket :fd fd :path cfg.path :status "listening" :permissions cfg.permissions))))))))))

fn ! connectUnixSocket path: String -> (Result Int64 String)
  (if (stringEmpty? path)
    (err "ERR_UNIX_SOCKET_EMPTY_PATH")
    (mt (unixConnect path)
      ((err e) (err (str "ERR_UNIX_SOCKET_CONNECT: " e)))
      ((ok fd) (ok fd))))

fn ! closeUnixSocket server: UnixServerSocket -> (Result Bool String)
  (mt (fdClose server.fd)
    ((err e) (err e))
    ((ok _)
      (mt (pathRemove server.path)
        ((err e) (err (str "ERR_UNIX_SOCKET_UNLINK: " e)))
        ((ok _) (ok true)))))
