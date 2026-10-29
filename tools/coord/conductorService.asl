(module asl-tools/coord/conductorService
  :x [Layout ServiceConfig noConfig configOf layoutOf unitText devRepoSteps serviceSteps stepText main]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/coord/store :a st)])

; (:m :ref COND3 :do "the VPS service of the conductor: a systemd --user unit asl-conductor running the main worktree's conductor with its store and a dev repo, written and installed from ASL (no shell): install --dry prints the unit and the steps, install runs them; the stop is cooperative (ExecStop writes the stop file the loop reads) and KillMode=process leaves stage children to the next start, which resumes them from the store rows")

(schema Layout (:f home String) (:f repo String) (:f devRepo String) (:f store String) (:f source String))

; (:m :do "optional ExecStart values of a node, empty string means absent: an install flag wins over the first row of ~/.asl/conductor/service.asn")
(schema ServiceConfig (:f lanes String) (:f profile String) (:f keys String) (:f ledger String) (:f ledgerBase String))

fn noConfig -> ServiceConfig
  (ServiceConfig :lanes "" :profile "" :keys "" :ledger "" :ledgerBase "")

fn configOf args: (List String) rowText: String -> ServiceConfig
  (let [(fs (match (st/rowFields rowText "conductorService") ((ok f) f) ((err _) (list))))
        (pick (fn [(flag String) (key String)] -> String (st/opt args flag (st/textField fs key))))]
    (ServiceConfig :lanes (pick "lanes" "lanes") :profile (pick "profile" "profile") :keys (pick "keys" "keys") :ledger (pick "ledger" "ledger") :ledgerBase (pick "ledger-base" "ledgerBase")))

fn flagText flag: String value: String -> String
  (if (stringEmpty? value) "" (str " --" flag " " value))

fn layoutOf home: String -> Layout
  (Layout :home home :repo (str home "/wt/main") :devRepo (str home "/asex-dev") :store (str home "/.asl/run/conductor") :source (str home "/asex"))

fn unitText lay: Layout cfg: ServiceConfig -> String
  (str "[Unit]\nDescription=asl conductor (asl/tools/coord/conductor.asl)\nAfter=network-online.target\n\n[Service]\nWorkingDirectory=" lay.repo
       "\nExecStart=/usr/bin/nice -n 10 " lay.repo "/bin/asl run asl/tools/coord/conductor.asl run --store " lay.store " --repo " lay.repo " --dev-repo " lay.devRepo " --dev dev"
       (flagText "lanes" cfg.lanes) (flagText "profile" cfg.profile) (flagText "keys" cfg.keys) (flagText "ledger" cfg.ledger) (flagText "ledger-base" cfg.ledgerBase)
       "\nExecStop=" lay.repo "/bin/asl run asl/tools/coord/conductor.asl stop --store " lay.store
       "\nUnsetEnvironment=ASL_ROOT ASL_PRELUDE\nKillMode=process\nRestart=always\nRestartSec=10\nTimeoutStopSec=120"
       "\nStandardOutput=append:" lay.store "/conductor.log\nStandardError=append:" lay.store "/conductor.log"
       "\n\n[Install]\nWantedBy=default.target\n")

; (:m :do "the dev repo: a clone of the source repo with a dev branch from main, made only when it is absent; main of the source repo is never checked out or written")
fn devRepoSteps lay: Layout -> (List (List String))
  (if (fileExists? (str lay.devRepo "/.git")) (list)
    (list (list "git" "clone" "--quiet" lay.source lay.devRepo)
          (list "git" "-C" lay.devRepo "checkout" "--quiet" "-b" "dev" "origin/main")))

fn serviceSteps lay: Layout -> (List (List String))
  (list (list "systemctl" "--user" "daemon-reload")
        (list "systemctl" "--user" "enable" "--now" "asl-conductor.service"))

fn stepText argv: (List String) -> String
  (stringJoin argv " ")

fn ! runStep! argv: (List String) cwd: String -> Int64
  (let [(d (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits 600 64)))
        (_ (println (str "(:step :argv " (stringJoin (map (fn [(a String)] -> String (str "\"" a "\"")) argv) " ") " :exit " (stringFromInt64 d.exit) ")")))]
    d.exit)

fn ! runSteps! steps: (List (List String)) cwd: String -> Int64
  (match (listHead steps)
    ((none) 0)
    ((some s) (let [(code (runStep! s cwd))]
                (if (!= code 0) code (runSteps! (optionOr (listTail steps) (list)) cwd)))))

; (:m :ref COND3 :do "install [--home H] [--dry] [--lanes P] [--profile N] [--keys P] [--ledger P] [--ledger-base REF]: dry prints the unit file and every step and changes nothing; otherwise it makes the store dir, the dev repo clone if absent, writes ~/.config/systemd/user/asl-conductor.service and enables it; the VPS install is the lead's step")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (home (let [(i (listIndexOf args "--home"))] (match i ((some k) (optionOr (listGet args (+ k 1)) "") ) ((none) (resultOr (getHomeDir) ".")))))
        (lay (layoutOf home))
        (dry (listContains? args "--dry"))
        (cfgPath (str home "/.asl/conductor/service.asn"))
        (cfg (configOf args (match (fileReadString cfgPath) ((ok raw) raw) ((err _) ""))))
        (unitPath (str home "/.config/systemd/user/asl-conductor.service"))
        (steps (listAppend (devRepoSteps lay) (serviceSteps lay)))]
    (cond
      ((= cmd "install")
        (if dry
          (do (println (str "(:install :dry true :unit " (str "\"" unitPath "\"") ")"))
              (println (unitText lay cfg))
              (map (fn [(s (List String))] -> Unit (println (str "(:step :argv \"" (stepText s) "\")"))) steps)
              (ok 0))
          (let [(_ (dirCreate lay.store))
                (_ (dirCreate (str home "/.config/systemd/user")))
                (pre (runSteps! (devRepoSteps lay) home))]
            (if (!= pre 0) (ok pre)
              (match (fileWrite unitPath (unitText lay cfg))
                ((err e) (do (eprintln e) (ok 1)))
                ((ok _) (ok (runSteps! (serviceSteps lay) home))))))))
      (else (do (eprintln "usage: conductorService install [--home H] [--dry] [--lanes P] [--profile N] [--keys P] [--ledger P] [--ledger-base REF]") (ok 2)))))
