(module asl-tools/hub/main
  :x [HubCfg hubAsnString hubCfgFrom hubCfg! hubMkdirs! hubLock! hubServe! hubStatus! main]
  :i [(aslGateway/server :a srv)])

; (:m :ref ORCH-HUB-DAEMON :do "one daemon per node holds the only buckets and breakers: it is the gateway server loop listening on a unix socket (mode 0600) whose path comes from ~/.asl/hub.asn, never from env; a lock file next to the socket keeps it to one instance, a live socket refuses a second")
(schema HubCfg
  (:f sock String)
  (:f lock String)
  (:f upstream String))

; (:m :ref ORCH-HUB-DAEMON :do "the value of the quoted string after :key in an ASN text, the fallback when the key is absent")
fn hubAsnString text: String key: String fallback: String -> String
  (match (stringIndexOf text (str ":" key " \""))
    ((none) fallback)
    ((some at)
      (let [(start (+ at (+ 3 (stringLength key))))
            (rest (optionOr (stringSlice text start (stringLength text)) ""))]
        (match (stringIndexOf rest "\"")
          ((none) fallback)
          ((some end) (optionOr (stringSlice rest 0 end) fallback))))))

fn hubCfgFrom home: String text: String -> HubCfg
  (let [(sock (hubAsnString text "sock" (str home "/.asl/run/hub/hub.sock")))]
    (HubCfg :sock sock
      :lock (hubAsnString text "lock" (str sock ".lock"))
      :upstream (hubAsnString text "upstream" "http://127.0.0.1:1")))

fn ! hubCfg! -> (Result HubCfg String)
  (match (envGet "HOME")
    ((none) (err "ERR_HUB_NO_HOME"))
    ((some home)
      (ok (hubCfgFrom home (resultOr (fileReadString (str home "/.asl/hub.asn")) "")))))

fn ! hubMkdirs! dir: String -> Bool
  (if (or (stringEmpty? dir) (fileExists? dir)) true
    (match (stringIndexOf (stringReverse dir) "/")
      ((none) (ok? (dirCreate dir)))
      ((some back)
        (let [(parent (optionOr (stringSlice dir 0 (- (stringLength dir) (+ back 1))) ""))]
          (do (hubMkdirs! parent) (ok? (dirCreate dir)))))))

fn hubDirOf path: String -> String
  (match (stringIndexOf (stringReverse path) "/")
    ((none) "")
    ((some back) (optionOr (stringSlice path 0 (- (stringLength path) (+ back 1))) "")))

; (:m :ref ORCH-HUB-DAEMON :do "the lock fd stays open for the life of the process; the OS drops it on exit, so a crash never leaves a stale lock")
fn ! hubLock! cfg: HubCfg -> (Result Int64 String)
  (do (hubMkdirs! (hubDirOf cfg.lock))
    (match (fileLock cfg.lock true)
      ((ok fd) (ok fd))
      ((err e) (if (= e "busy") (err "ERR_HUB_RUNNING: another hub holds the lock") (err e)))))

fn ! flagAfter args: (List String) flag: String -> String
  (match (listIndexOf args flag)
    ((none) "")
    ((some i) (optionOr (listGet args (+ i 1)) "")))

fn ! hubServe! args: (List String) -> (Result Int64 String)
  (match (hubCfg!)
    ((err e) (err e))
    ((ok cfg)
      (match (hubLock! cfg)
        ((err e) (err e))
        ((ok _)
          (let [(ready (flagAfter args "--ready"))
                (serveArgs (listAppend (list "serve" "--unix" cfg.sock "--upstream" cfg.upstream)
                             (if (stringEmpty? ready) (list) (list "--ready" ready))))]
            (srv/mainWith serveArgs "asl/tools/hub/main.asl" (list)))))))

fn ! hubStatus! -> (Result Int64 String)
  (match (hubCfg!)
    ((err e) (err e))
    ((ok cfg)
      (match (unixConnect cfg.sock)
        ((err _) (do (println (str "(:hub :status :stopped :sock \"" cfg.sock "\")")) (ok 1)))
        ((ok fd) (do (fdClose fd) (println (str "(:hub :status :running :sock \"" cfg.sock "\")")) (ok 0))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listHead args) ""))]
    (cond
      ((= mode "serve") (hubServe! args))
      ((= mode "status") (hubStatus!))
      (else (do (println (str "(:hub :status :unsupported :command \"" mode "\")")) (ok 2)))))
