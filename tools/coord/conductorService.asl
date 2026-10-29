(module asl-tools/coord/conductorService
  :x [Layout layoutOf unitText devRepoSteps serviceSteps stepText main]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref COND3 :do "the VPS service of the conductor: a systemd --user unit asl-conductor running the main worktree's conductor with its store and a dev repo, written and installed from ASL (no shell): install --dry prints the unit and the steps, install runs them; the stop is cooperative (ExecStop writes the stop file the loop reads) and KillMode=process leaves stage children to the next start, which resumes them from the store rows")

(schema Layout (:f home String) (:f repo String) (:f devRepo String) (:f store String) (:f source String))

fn layoutOf home: String -> Layout
  (Layout :home home :repo (str home "/wt/main") :devRepo (str home "/asex-dev") :store (str home "/.asl/run/conductor") :source (str home "/asex"))

fn unitText lay: Layout -> String
  (str "[Unit]\nDescription=asl conductor (asl/tools/coord/conductor.asl)\nAfter=network-online.target\n\n[Service]\nWorkingDirectory=" lay.repo
       "\nExecStart=/usr/bin/nice -n 10 " lay.repo "/bin/asl run asl/tools/coord/conductor.asl run --store " lay.store " --repo " lay.repo " --dev-repo " lay.devRepo " --dev dev"
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

; (:m :ref COND3 :do "install [--home H] [--dry]: dry prints the unit file and every step and changes nothing; otherwise it makes the store dir, the dev repo clone if absent, writes ~/.config/systemd/user/asl-conductor.service and enables it; the VPS install is the lead's step")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (home (let [(i (listIndexOf args "--home"))] (match i ((some k) (optionOr (listGet args (+ k 1)) "") ) ((none) (resultOr (getHomeDir) ".")))))
        (lay (layoutOf home))
        (dry (listContains? args "--dry"))
        (unitPath (str home "/.config/systemd/user/asl-conductor.service"))
        (steps (listAppend (devRepoSteps lay) (serviceSteps lay)))]
    (cond
      ((= cmd "install")
        (if dry
          (do (println (str "(:install :dry true :unit " (str "\"" unitPath "\"") ")"))
              (println (unitText lay))
              (map (fn [(s (List String))] -> Unit (println (str "(:step :argv \"" (stepText s) "\")"))) steps)
              (ok 0))
          (let [(_ (dirCreate lay.store))
                (_ (dirCreate (str home "/.config/systemd/user")))
                (pre (runSteps! (devRepoSteps lay) home))]
            (if (!= pre 0) (ok pre)
              (match (fileWrite unitPath (unitText lay))
                ((err e) (do (eprintln e) (ok 1)))
                ((ok _) (ok (runSteps! (serviceSteps lay) home))))))))
      (else (do (eprintln "usage: conductorService install [--home H] [--dry]") (ok 2)))))
