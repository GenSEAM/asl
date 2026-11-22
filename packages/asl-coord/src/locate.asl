(module asl-coord/locate
  :x [contextAt! context! identity! callerUnit! repoScope scopeOfCommon vaultRootAt!]
  :i [(asl-store/types :a ty) (asl-store-fs/fs :a fs) (asl-coord/lease :a ls) (asl-coord/core :a co)])

; (:m :ref VS-COORD :do "the only module of asl-coord that reads the clock, the environment, files or processes: it resolves the vault root from the config row, the repository scope from the git common dir, the caller identity, and hands the pure rules a Ctx of plain functions and facts")
fn shellQ s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! commandOutput! cmd: String -> String
  (let [(o (processRun cmd))]
    (if (= o.exitCode 0) (stringTrim o.stdout) ""))

fn gitCommand root: String args: String -> String
  (str "git -C " (shellQ root) " " args)

fn ! envOr! name: String fallback: String -> String
  (optionOr (envGet name) fallback)

fn ! hostName! -> String
  (envOr! "HOSTNAME" (commandOutput! "hostname"))

fn ! nowMs! -> Int64
  (/ (nowNs) 1000000)

fn safeName s: String -> String
  (stringJoin (map (fn [(c String)] -> String (if (or (and (>= c "0") (<= c "9")) (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (or (= c ".") (or (= c "_") (= c "-")))))) c "-"))
                   (stringChars s)) "")

fn lastSegment p: String -> String
  (optionOr (listLast (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit p "/"))) "")

fn dropLeadingDots s: String -> String
  (if (stringStartsWith? s ".") (dropLeadingDots (optionOr (stringSlice s 1 (stringLength s)) "")) s)

; (:m :ref VS-COORD :do "the scope of a repository is its display name plus a hash of the real path of its git common dir, reduced to one valid store name: every worktree of one repository, and any agent working on it from another project, claims in the same scope, while two repositories that share a directory name in different parents do not")
fn scopeOfCommon common: String -> String
  (let [(trimmed (if (stringEndsWith? common "/") (optionOr (stringSlice common 0 (- (stringLength common) 1)) common) common))
        (base (lastSegment trimmed))
        (name (if (= base ".git")
                (lastSegment (optionOr (stringSlice trimmed 0 (- (stringLength trimmed) 5)) ""))
                (if (stringEndsWith? base ".git") (optionOr (stringSlice base 0 (- (stringLength base) 4)) base) base)))
        (clean (dropLeadingDots (safeName name)))]
    (str (if (stringEmpty? clean) "repo" clean) "-" (stringFromInt64 (& (fnv1a64 trimmed) 9223372036854775807))))

fn ! commonDir! workspace: String -> String
  (let [(raw (commandOutput! (gitCommand workspace "rev-parse --path-format=absolute --git-common-dir")))]
    (if (stringEmpty? raw) "" (resultOr (realPath raw) raw)))

fn repoScope common: String -> String
  (scopeOfCommon common)

fn ! homeDir! -> (Result String String)
  (match (envGet "HOME")
    ((some h) (if (stringEmpty? h) (err "HOME is empty") (ok h)))
    ((none) (err "HOME is not set")))

; (:m :ref VS-COORD :do "the vault root is the :vaultRoot string of ~/.asl/config.asn when that row exists (a leading ~/ means the home dir), else ~/.asl/vault; it is a config row, never an environment variable")
fn ! vaultRootAt! home: String -> String
  (let [(raw (resultOr (fileReadString (str home "/.asl/config.asn")) ""))
        (row (if (stringContains? raw ":vaultRoot") (ls/quotedField raw "vaultRoot") ""))]
    (cond
      ((stringEmpty? row) (str home "/.asl/vault"))
      ((stringStartsWith? row "~/") (str home "/" (optionOr (stringSlice row 2 (stringLength row)) "")))
      (else row)))

fn ! dirExists? p: String -> Bool
  (match (fileStat p) ((ok st) st.isDir) ((err _) false))

fn ! legacyRows! dir: String -> (List (Pair String Int64))
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (fold (fn [(acc (List (Pair String Int64))) (n String)] -> (List (Pair String Int64))
              (if (and (stringEndsWith? n ".asn") (and (!= n "log.asn") (not (stringStartsWith? n "retired"))))
                (match (fileReadString (str dir "/" n))
                  ((ok raw) (listAppend acc (list (pair raw (match (fileStat (str dir "/" n)) ((ok st) (/ st.mtimeNs 1000000)) ((err _) 0))))))
                  ((err _) acc))
                acc))
            (list) names)))

; (:m :ref VS-COORD :do "every lease file of the legacy directory, read on every call during the migration and parsed with the file mtime as its heartbeat, because old binaries keep writing there; CUTOVER-COORD-LEGACY removes this path once every binary is deployed")
fn ! legacyAll! dir: String -> (List ls/Lease)
  (filter (fn [(l ls/Lease)] -> Bool (and (not (stringEmpty? l.unit)) (not (stringEmpty? l.branch))))
    (map (fn [(row (Pair String Int64))] -> ls/Lease (with (ls/parseLease (pairFirst row)) :at (pairSecond row)))
         (legacyRows! dir)))

fn ! retireLegacyFile! dir: String unit: String -> Unit
  (let [(_ (pathRemove (str dir "/" unit ".asn")))] ())

fn ! worktreeListed? workspace: String path: String -> Bool
  (let [(o (processRun (gitCommand workspace "worktree list --porcelain")))
        (needle (str "worktree " path))]
    (listAny? (fn [(line String)] -> Bool (= line needle)) (stringSplit o.stdout "\n")))

fn ! merged? workspace: String branch: String -> Bool
  (let [(o (processRun (gitCommand workspace (str "merge-base --is-ancestor " (shellQ branch) " main"))))]
    (= o.exitCode 0))

; (:m :ref VS-COORD :do "a lease of another host is never judged gone from here; on this host it is gone when its worktree directory is missing, or, when that worktree belongs to this repository, when its branch is merged into main or git no longer lists the worktree")
fn ! goneProbe workspace: String common: String host: String -> (fn [ls/Lease] -> Bool)
  (fn [(lease ls/Lease)] -> Bool
    (cond
      ((!= lease.host host) false)
      ((not (dirExists? lease.worktree)) true)
      ((!= (commonDir! lease.worktree) common) false)
      (else (or (merged? workspace lease.branch) (not (worktreeListed? workspace lease.worktree))))))

fn ! aliveProbe host: String -> (fn [ls/Lease] -> Bool)
  (fn [(lease ls/Lease)] -> Bool
    (and (= lease.host host)
         (and (> lease.pid 0) (match (procAlive? lease.pid) ((ok b) b) ((err _) false)))))

fn ! buildCtx! workspace: String common: String root: String -> (Result co/Ctx String)
  (match (fs/fsOpen! root 1000)
    ((err e) (err e))
    ((ok store)
      (let [(host (hostName!))
            (ctx (co/Ctx :call (fn [(op ty/Op)] -> ty/Reply (fs/fsCall! store op))
                         :scope (scopeOfCommon common) :now (nowMs!)
                         :gone (goneProbe workspace common host) :alive (aliveProbe host) :legacy (list) :retireLegacy (fn [(u String)] -> Unit ())))]
        (if (dirExists? (str common "/asl/claims"))
          (match (if (co/legacyDone? ctx) (ok 0) (co/importLegacy ctx (legacyRows! (str common "/asl/claims"))))
            ((err e) (err e))
            ((ok _) (ok (with (with ctx :legacy (legacyAll! (str common "/asl/claims"))) :retireLegacy (fn [(u String)] -> Unit (retireLegacyFile! (str common "/asl/claims") u))))))
          (ok ctx)))))

; (:m :ref VS-COORD :do "a read finds nothing and creates nothing when neither the vault nor the old claims directory exists; a write opens (creates) the vault; the old lease files are imported on the first call that opens the vault and never again")
fn ! contextAt! workspace: String home: String forWrite: Bool -> (Result (Option co/Ctx) String)
  (let [(common (commonDir! workspace))]
    (if (stringEmpty? common)
      (err (str "cannot resolve git common directory for " workspace))
      (let [(root (vaultRootAt! home))
            (legacy (str common "/asl/claims"))]
        (if (and (not forWrite) (and (not (dirExists? root)) (not (dirExists? legacy))))
          (ok (none))
          (match (buildCtx! workspace common root)
            ((err e) (err e))
            ((ok ctx) (ok (some ctx))))))))

fn ! context! workspace: String forWrite: Bool -> (Result (Option co/Ctx) String)
  (match (homeDir!)
    ((err e) (err e))
    ((ok home) (contextAt! workspace home forWrite)))

fn ! branchOf! workspace: String -> String
  (commandOutput! (gitCommand workspace "branch --show-current"))

fn ! callerUnit! workspace: String given: String -> String
  (if (not (stringEmpty? given))
    given
    (let [(envUnit (envOr! "ASL_UNIT" ""))]
      (if (not (stringEmpty? envUnit))
        envUnit
        (let [(branch (branchOf! workspace))]
          (if (stringStartsWith? branch "sh/")
            (optionOr (stringSlice branch 3 (stringLength branch)) "")
            "")))))

fn ! identity! workspace: String unit: String owns: (List String) -> ls/Lease
  (ls/Lease :unit unit :owns owns
    :branch (branchOf! workspace)
    :worktree (resultOr (realPath workspace) workspace)
    :agent (envOr! "ASL_AGENT" (envOr! "ASL_SESSION" "unknown"))
    :host (hostName!)
    :pid (optionOr (stringToInt64 (envOr! "ASL_LEASE_PID" "0")) 0)
    :at (nowMs!) :ttl 7200)
