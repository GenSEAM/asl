(module asl-tools/remote/transport
  :x [Config configPath parseConfig loadConfig! shQuote sshArgv sshLine privateDir! scratchFile! scratchDrop! ssh! run! scratchDir!]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/remote/form :a fm)])

(schema Config
  (:f host String)
  (:f ssh String)
  (:f connectTimeout Int64)
  (:f timeoutS Int64)
  (:f controlPath String))

fn shQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! configPath -> String
  (str (resultOr (getHomeDir) "/tmp") "/.asl/remote.asn")

fn intOr node: (Option fm/Node) key: Int64 -> Int64
  (match node ((some n) (optionOr (fm/formInt n) key)) ((none) key))

fn textOr node: (Option fm/Node) fallback: String -> String
  (match node ((some n) (optionOr (fm/formText n) fallback)) ((none) fallback))

; (:m :ref REMOTE-CONFIG :do "settings live in ~/.asl/remote.asn, never in env; a missing or unreadable file, a form that does not parse and a config with no :host are all (err ...) so a caller reports them instead of crashing")
fn parseConfig text: String -> (Result Config String)
  (match (fm/parseForm text)
    ((err e) (err (str "ERR_REMOTE_CONFIG parse: " e)))
    ((ok node)
      (let [(host (textOr (fm/formGet node ":host") ""))]
        (if (stringEmpty? host)
          (err "ERR_REMOTE_CONFIG no :host")
          (ok (Config :host host
                      :ssh (textOr (fm/formGet node ":ssh") "ssh")
                      :connectTimeout (intOr (fm/formGet node ":connectTimeout") 10)
                      :timeoutS (intOr (fm/formGet node ":timeout") 120)
                      :controlPath (textOr (fm/formGet node ":controlPath") "")))))))

fn ! loadConfig! path: String -> (Result Config String)
  (match (fileReadString path)
    ((err _) (err (str "ERR_REMOTE_NO_CONFIG " path)))
    ((ok text) (parseConfig text)))

fn ! controlPathOf cfg: Config -> String
  (if (stringEmpty? cfg.controlPath)
    (str (resultOr (getHomeDir) "/tmp") "/.asl/run/remote-%C")
    cfg.controlPath)

fn ! sshArgv cfg: Config command: String -> (List String)
  (list cfg.ssh
        "-o" "BatchMode=yes"
        "-o" (str "ConnectTimeout=" cfg.connectTimeout)
        "-o" "ControlMaster=auto"
        "-o" "ControlPersist=60"
        "-o" (str "ControlPath=" (controlPathOf cfg))
        cfg.host command)

fn sshLine argv: (List String) stdinPath: String -> String
  (str "exec " (stringJoin (map shQuote argv) " ") " < " (shQuote stdinPath))

fn ! scratchDir! -> String
  (resultOr (realPath (optionOr (envGet "TMPDIR") "/tmp")) "/tmp")

fn ! privateDir! tag: String -> (Result String String)
  (let [(dir (str (scratchDir!) "/remote-" tag "-" (procSelf) "-" (nowNs)))]
    (match (dirCreate dir)
      ((err e) (err e))
      ((ok _) (match (fileChmod dir 448) ((err e) (err e)) ((ok _) (ok dir))))))

fn ! scratchFile! tag: String content: String -> (Result String String)
  (match (privateDir! tag)
    ((err e) (err e))
    ((ok dir)
      (let [(path (str dir "/data"))]
        (match (fileCreateExclusive path content)
          ((err e) (err e))
          ((ok _) (do (fileChmod path 384) (ok path)))))))

fn ! scratchDrop! path: String -> Bool
  (ok? (pathRemove (optionOr (stringSlice path 0 (- (stringLength path) 5)) path)))

; (:m :ref REMOTE-SPAWN :do "the only child this module starts is the ssh client, through runGuarded with a timeout and a descendant limit (spawnSafety); the command is a list of dispatcher tokens, each re-checked against the token allowlist, and stdin travels as a file so no payload byte reaches a shell")
fn ! run! argv: (List String) timeoutS: Int64 -> fr/ProcOut
  (fr/runGuarded argv "." (fr/childEnv (list)) (fr/limits timeoutS 16))

fn ! ssh! cfg: Config tokens: (List String) stdin: String -> (Result String String)
  (if (not (listAll? fm/safeToken? tokens))
    (err "ERR_REMOTE_TOKEN a command token holds a character outside the allowlist")
    (match (scratchFile! "in" stdin)
      ((err e) (err (str "ERR_REMOTE_SCRATCH " e)))
      ((ok inPath)
        (let [(argv (sshArgv cfg (stringJoin tokens " ")))
              (d (run! (list "/bin/sh" "-c" (sshLine argv inPath)) cfg.timeoutS))
              (_ (scratchDrop! inPath))]
          (if (or (= d.exitCode 0) (stringStartsWith? (stringTrim d.stdout) "(:err "))
            (ok d.stdout)
            (err (str "ERR_REMOTE_SSH exit " d.exitCode ": " (stringTrim d.stderr))))))))
