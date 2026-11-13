(module asl-remote/target
  :x [Target Route profileRel parseOn parseProfile loadProfile! findProfile! localArgs routeOf remoteArgv timeoutOf onArgv promptLine]
  :i [])

; (:m :ref REMOTE-TARGET :do "a workspace may name a remote worktree its code lives in: .asl/target.asn holds (:target :exec remote :node NODE :wt UNIT), and then asl '<forms>', asl test and asl check run in NODE's worktree wt/UNIT over tools/remote (relay when configured, else ssh); asl --on NODE:UNIT routes one call the same way and asl --local ignores the profile; :node absent or default is the node of ~/.asl/remote.asn")
(schema Target (:f node String) (:f unit String))

(schema Route (:f node String) (:f unit String) (:f verb String) (:f args (List String)))

fn profileRel -> String
  ".asl/target.asn"

fn nameChar? c: String -> Bool
  (let [(n (bytesGet (stringToBytes c) 0))]
    (and (= (stringLength c) 1)
         (or (and (>= n 48) (<= n 57)) (or (and (>= n 65) (<= n 90)) (or (and (>= n 97) (<= n 122)) (= n 45))))))

fn name? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? nameChar? (stringChars s)))

fn checked node: String unit: String -> (Result Target String)
  (cond
    ((not (name? unit)) (err (str "ERR_TARGET the worktree unit must match [A-Za-z0-9-]+, got " unit)))
    ((and (not (stringEmpty? node)) (not (name? node))) (err (str "ERR_TARGET the node must match [A-Za-z0-9-]+, got " node)))
    (else (ok (Target :node (if (= node "default") "" node) :unit unit))))

fn parseOn spec: String -> (Result Target String)
  (let [(parts (stringSplit spec ":"))]
    (cond
      ((= (listLength parts) 1) (checked "" spec))
      ((= (listLength parts) 2) (checked (optionOr (listHead parts) "") (optionOr (listGet parts 1) "")))
      (else (err (str "ERR_TARGET --on takes NODE:UNIT or UNIT, got " spec)))))

fn wordAfter text: String key: String -> String
  (match (stringIndexOf text (str key " "))
    ((none) "")
    ((some i)
      (let [(tail (stringTrim (optionOr (stringSlice text (+ i (+ (stringLength key) 1)) (stringLength text)) "")))
            (word (optionOr (listHead (stringSplit (optionOr (listHead (stringLines tail)) "") " ")) ""))]
        (stringReplace (optionOr (listHead (stringSplit word ")")) "") "\"" ""))))

fn parseProfile text: String -> (Result (Option Target) String)
  (let [(t (stringTrim text))
        (exec (wordAfter t ":exec"))]
    (cond
      ((not (stringStartsWith? t "(:target")) (err "ERR_TARGET .asl/target.asn must be one (:target :exec remote|local ...) form"))
      ((= exec "local") (ok (none)))
      ((!= exec "remote") (err (str "ERR_TARGET :exec must be remote or local, got " exec)))
      (else (resultMap (checked (wordAfter t ":node") (wordAfter t ":wt")) (fn [(x Target)] -> (Option Target) (some x))))))

fn ! loadProfile! root: String -> (Result (Option Target) String)
  (match (fileReadString (str root "/" (profileRel)))
    ((err _) (ok (none)))
    ((ok text) (parseProfile text)))

fn parentOf dir: String -> String
  (let [(parts (stringSplit dir "/"))]
    (stringJoin (optionOr (listSlice parts 0 (- (listLength parts) 1)) (list)) "/"))

; (:m :ref REMOTE-TARGET :do "the profile of a directory is the .asl/target.asn of the nearest enclosing directory that has one, searched no higher than the first directory holding .asl.config.asn or .git, so a file above the workspace, ~/.asl among them, never retargets it")
fn ! findProfile! dir: String -> (Result (Option Target) String)
  (cond
    ((stringEmpty? dir) (ok (none)))
    ((fileExists? (str dir "/" (profileRel))) (loadProfile! dir))
    ((or (fileExists? (str dir "/.asl.config.asn")) (fileExists? (str dir "/.git"))) (ok (none)))
    (else (findProfile! (parentOf dir))))

fn restOf args: (List String) -> (List String)
  (optionOr (listTail args) (list))

fn formsLead? a: String -> Bool
  (let [(t (stringTrim a))] (or (stringStartsWith? t "(") (stringStartsWith? t ":")))

fn verbOf args: (List String) -> (Option Route)
  (let [(cmd (optionOr (listHead args) ""))]
    (cond
      ((formsLead? cmd) (some (Route :node "" :unit "" :verb "forms" :args (list (stringJoin args " ")))))
      ((= cmd "rpc") (some (Route :node "" :unit "" :verb "forms" :args (list (stringJoin (restOf args) " ")))))
      ((or (= cmd "test") (= cmd "check")) (some (Route :node "" :unit "" :verb cmd :args (restOf args))))
      (else (none))))

fn aimed r: Route t: Target -> Route
  (with r :node t.node :unit t.unit)

; (:m :ref REMOTE-TARGET :do "asl --local ARGS runs ARGS locally whatever the profile says: the leading --local is dropped before local dispatch")
fn localArgs args: (List String) -> (List String)
  (if (= (optionOr (listHead args) "") "--local") (optionOr (listTail args) (list)) args)

; (:m :ref REMOTE-TARGET :do "the routing decision (asl --local never reaches it: both CLI entries strip it with localArgs and skip the profile); --on SPEC routes forms, test and check and refuses any other verb; a remote profile routes forms, test and check and leaves every other verb local; ok none means run locally with the argv as it came minus --local")
fn routeOf args: (List String) profile: (Option Target) -> (Result (Option Route) String)
  (let [(lead (optionOr (listHead args) ""))]
    (cond
      ((= lead "--on")
        (match (parseOn (optionOr (listGet args 1) ""))
          ((err e) (err e))
          ((ok t) (match (verbOf (listDrop args 2))
                    ((none) (err "ERR_TARGET asl --on NODE:UNIT routes forms, test and check only"))
                    ((some r) (if (and (!= r.verb "forms") (listEmpty? r.args))
                                (err (str "ERR_TARGET asl --on ... " r.verb " needs file paths"))
                                (ok (some (aimed r t)))))))))
      (else
        (match profile
          ((none) (ok (none)))
          ((some t) (match (verbOf args)
                      ((none) (ok (none)))
                      ((some r) (if (and (!= r.verb "forms") (or (listEmpty? r.args) (listContains? r.args "--all")))
                                  (ok (none))
                                  (ok (some (aimed r t)))))))))))

; (:m :ref REMOTE-TARGET :do "the remote argv, run inside the worktree: forms travel as one argv element so the whole batch is one remote asl call; test and check run niced; ASL_ROOT and ASL_PRELUDE are unset so the worktree's own packages load")
fn remoteArgv r: Route -> (List String)
  (let [(clean (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE"))]
    (if (= r.verb "forms")
      (listAppend clean (list "./bin/asl" (optionOr (listHead r.args) "")))
      (listAppend clean (listAppend (list "nice" "-n" "10" "./bin/asl" r.verb) r.args))))

fn timeoutOf r: Route -> Int64
  (if (= r.verb "test") 1800 600)

fn onArgv root: String r: Route -> (List String)
  (listAppend (list (str root "/tools/remote/on.asl") (if (stringEmpty? r.node) "default" r.node) r.unit r.verb) r.args)

fn promptLine t: Target -> String
  (str "Your code lives in " (if (stringEmpty? t.node) "the default node" t.node) ":wt/" t.unit
       " (remote target, .asl/target.asn): read, edit and test it only through asl forms, asl test and asl check, which run there; local Read, Edit and shell see a stale tree.")
