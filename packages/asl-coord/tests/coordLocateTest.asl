(module asl-coord/tests/coordLocateTest
  :x [runTests]
  :i [(asl-coord/locate :a loc) (asl-coord/core :a co) (asl-coord/lease :a ls) (asl-tools/fleet/run :a fr)])

; (:m :ref VS-COORD :do "locate is probed in-process against a throwaway git repository and a scratch HOME passed as an argument, so nothing under the real ~/.asl is read or written; the repository is made with plain git, never with the host binary")
fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/coordLocateTest-" (stringFromInt64 (procSelf)))

fn ! rmTree! p: String -> Unit
  (match (fileStat p)
    ((err _) ())
    ((ok st) (let [(_ (if st.isDir (map (fn [(n String)] -> Unit (rmTree! (str p "/" n))) (resultOr (dirList p) (list))) (list)))
                   (_ (pathRemove p))]
               ())))

fn ! gitInit! dir: String -> Int64
  (let [(made (dirCreate dir))
        (done (fr/runOneLimited (fr/job (list "git" "-C" dir "init" "-q" "-b" "main") "." (fr/childEnv (list))) (fr/limits 60 8)))]
    (if (ok? made) done.exit 1))

fn newLease -> String
  "(:lease :unit \"NEW\" :owns (\"q/r\") :branch \"sh/NEW\" :worktree \"/nonexistent/NEW\" :agent \"ag\" :host \"elsewhere\" :pid 0 :at 0 :ttl 7200)\n"

fn legacyLease -> String
  "(:lease :unit \"OLD\" :owns (\"x/y\") :branch \"sh/OLD\" :worktree \"/nonexistent/OLD\" :agent \"ag\" :host \"elsewhere\" :pid 0 :at 1790000000000000000 :ttl 7200)\n"

fn ! heldCount! found: (Result (Option co/Ctx) String) -> Int64
  (match found
    ((ok some1)
      (match some1
        ((some ctx) (match (co/claimsOf ctx) ((ok h) (listLength h)) ((err _) -1)))
        ((none) -2)))
    ((err _) -3))

fn ! runTests -> Bool
  (let [(base (scratch))
        (_ (rmTree! base))
        (repo (str base "/proj/seed"))
        (home (str base "/home"))
        (homeMade (dirCreate (str home "/.asl")))
        (setup (gitInit! repo))
        (readNone (loc/contextAt! repo home false))
        (noVault (not (fileExists? (str home "/.asl/vault"))))
        (writeCtx (loc/contextAt! repo home true))
        (vaultMade (fileExists? (str home "/.asl/vault/kv")))
        (_ (fileWrite (str home "/.asl/config.asn") (stringToBytes "(:aslGlobalConfig :vaultRoot \"~/custom\" )\n")))
        (customRoot (loc/vaultRootAt! home))
        (_ (pathRemove (str home "/.asl/config.asn")))
        (defaultRoot (loc/vaultRootAt! home))
        (claimsDir (dirCreate (str repo "/.git/asl/claims")))
        (mk (fileWrite (str repo "/.git/asl/claims/OLD.asn") (stringToBytes (legacyLease))))
        (home2 (str base "/home2"))
        (mk2 (dirCreate (str home2 "/.asl")))
        (readLegacy (loc/contextAt! repo home2 false))
        (importedCount (heldCount! readLegacy))
        (legacyKept (fileExists? (str repo "/.git/asl/claims/OLD.asn")))
        (seedScope (loc/scopeOfCommon (resultOr (realPath (str repo "/.git")) "")))
        (rowThere (fileExists? (str home2 "/.asl/vault/kv/claims/" seedScope "/OLD.row")))
        (_ (pathRemove (str home2 "/.asl/vault/kv/claims/" seedScope "/OLD.row")))
        (_ (loc/contextAt! repo home2 false))
        (again (fileExists? (str home2 "/.asl/vault/kv/claims/" seedScope "/OLD.row")))
        (_ (sleepMs 30))
        (newWritten (fileWrite (str repo "/.git/asl/claims/NEW.asn") (stringToBytes (newLease))))
        (afterImport (match (loc/contextAt! repo home2 true) ((ok o) (match o ((some ctx) (co/claimLease ctx (with (loc/identity! repo "BLK" (list "q/r/s")) :branch "sh/BLK"))) ((none) (err "none")))) ((err e) (err e))))
        (rtLease (with (loc/identity! repo "RT" (list "rt/x")) :branch "sh/RT"))
        (rtFile (fileWrite (str repo "/.git/asl/claims/RT.asn") (stringToBytes (ls/leaseContent rtLease))))
        (rtClaim (match (loc/contextAt! repo home2 true) ((ok o) (match o ((some ctx) (co/claimLease ctx rtLease)) ((none) (err "none")))) ((err e) (err e))))
        (rtGone (not (fileExists? (str repo "/.git/asl/claims/RT.asn"))))
        (twin (str base "/other/seed"))
        (mkTwin (gitInit! twin))
        (twinA (loc/contextAt! repo home true))
        (twinB (loc/contextAt! twin home true))
        (twinClaims (match twinA ((ok a) (match twinB ((ok b) (match a ((some ca) (match b ((some cb) (pair (co/claimLease ca (with (loc/identity! repo "TW1" (list "src/x")) :branch "sh/TW1")) (co/claimLease cb (with (loc/identity! twin "TW2" (list "src/x")) :branch "sh/TW2")))) ((none) (pair (err "none") (err "none"))))) ((none) (pair (err "none") (err "none"))))) ((err e) (pair (err e) (err e))))) ((err e) (pair (err e) (err e)))))
        (noRepo (loc/contextAt! "/" home false))
        (cleaned (rmTree! base))]
    (do
      (assert (= setup 0) "the throwaway repository is created")
      (assert (match readNone ((ok o) (none? o)) ((err _) false)) "a read with no vault and no old claims finds nothing")
      (assert noVault "a read creates no vault")
      (assert (match writeCtx ((ok o) (some? o)) ((err _) false)) "a write opens the vault")
      (assert vaultMade "the vault is created under the HOME given")
      (assert (stringStartsWith? (loc/scopeOfCommon "/Users/x/projects/asex/.git") "asex-") "the scope is led by the name of the directory holding .git")
      (assert (and (not (= (loc/scopeOfCommon "/p1/seed/.git") (loc/scopeOfCommon "/p2/seed/.git"))) (= (loc/scopeOfCommon "/p1/seed/.git") (loc/scopeOfCommon "/p1/seed/.git/"))) "same-named repositories in different parents get different scopes, one path one scope")
      (assert (stringStartsWith? (loc/scopeOfCommon "/srv/git/asl.git/") "asl-") "a bare repository is named without .git")
      (assert (stringStartsWith? (loc/scopeOfCommon "/a/.hidden/.git") "hidden-") "a leading dot is dropped")
      (assert (stringStartsWith? (loc/scopeOfCommon "/a/my repo/.git") "my-repo-") "characters outside a store name become -")
      (assert (= customRoot (str home "/custom")) "the :vaultRoot row of config.asn sets the root, ~/ meaning the home")
      (assert (= defaultRoot (str home "/.asl/vault")) "with no row the root is ~/.asl/vault")
      (assert (and (ok? claimsDir) (ok? mk)) "an old lease file is planted")
      (assert (= importedCount 1) "a read finding old lease files imports them once")
      (assert (and legacyKept rowThere) "the old file is left in place and the lease is a vault row")
      (assert (not again) "the import does not run again, a deleted row stays deleted")
      (assert (and (ok? newWritten) (match afterImport ((err e) (stringContains? e ":by \"NEW\"")) ((ok _) false))) "a lease file written by an old binary after the import blocks an overlapping claim")
      (assert (and (ok? rtFile) (ok? rtClaim) rtGone) "claiming a unit held in a legacy file by the same owner succeeds and retires the file")
      (assert (and (= mkTwin 0) (ok? (pairFirst twinClaims)) (ok? (pairSecond twinClaims))) "two repositories named seed under different parents claim the same path without conflict")
      (assert (match noRepo ((err e) (stringContains? e "cannot resolve git common directory")) ((ok _) false)) "a directory outside any repository is reported")
      (assert (not (fileExists? base)) "the scratch tree is removed")
      true))
