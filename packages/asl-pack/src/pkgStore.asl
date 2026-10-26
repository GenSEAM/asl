(module aslPack/pkgStore
  :x [Ctx LockRow Staged Plan makeCtx withCaps begin! finish! startIdOf! copyFile! hostTriple safeEntry? tarListsOk pkgsRoot lockPath currentPath treeDigest! readLock! writeLock! fetch! readIndex! resolveOne pickVersion planInstall install! update! remove! verify! installed! available! info!]
  :i [(pkgIndex :a ix) (asl-tools/fleet/run :a fr) (asl-parser/reader :a rd) (release :a rel)])

(schema Ctx (:f home String) (:f indexUrl String) (:f triple String) (:f aslBin String) (:f timeoutS Int64) (:f maxBytes Int64) (:f maxEntries Int64))
(schema LockRow (:f name String) (:f version String) (:f how String) (:f sha256 String) (:f tree String) (:f deps (List ix/Dep)))
(schema Staged (:f row LockRow) (:f dir String))
(schema Plan (:f chosen (List (Pair String ix/Version))) (:f order (List String)))

fn makeCtx home: String indexUrl: String triple: String aslBin: String -> Ctx
  (Ctx :home home :indexUrl indexUrl :triple triple :aslBin aslBin :timeoutS 120 :maxBytes 268435456 :maxEntries 10000)

; (:m :ref PKG-CLIENT :do "default caps are 256 MiB unpacked and 10000 entries per package; withCaps lowers them for a test or a tighter config")
fn withCaps ctx: Ctx bytes: Int64 entries: Int64 -> Ctx
  (Ctx :home ctx.home :indexUrl ctx.indexUrl :triple ctx.triple :aslBin ctx.aslBin :timeoutS ctx.timeoutS :maxBytes bytes :maxEntries entries)

fn ! rawTriple -> String
  (match (platformInfo)
    ((err _) "unknown")
    ((ok p)
     (str (cond ((= p.os "Darwin") "darwin") ((= p.os "Linux") "linux") (else (stringLower p.os)))
          "-"
          (cond ((or (= p.machine "arm64") (= p.machine "aarch64")) "arm64") ((or (= p.machine "x86_64") (= p.machine "amd64")) "x64") (else p.machine)))))

; (:m :ref PKG-CLIENT :do "artefact triples are the release plan target names (release.asl targetPlatforms, the asl-VERSION-TARGET.tar.gz naming), so a host outside that list is unknown rather than guessed")
fn ! hostTriple -> String
  (let [(t (rawTriple))]
    (if (listContains? (rel/makeReleasePlan "0.0.0").targetPlatforms t) t "unknown"))

fn pkgsRoot ctx: Ctx -> String
  (str ctx.home "/.asl/pkgs")

fn lockPath ctx: Ctx -> String
  (str ctx.home "/.asl/pkgs.asn")

fn pkgDir ctx: Ctx name: String -> String
  (str (pkgsRoot ctx) "/" name)

fn verDir ctx: Ctx name: String v: String -> String
  (str (pkgDir ctx name) "/" v)

fn currentPath ctx: Ctx name: String -> String
  (str (pkgDir ctx name) "/current")

fn parentOf path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ioErr what: String e: String -> String
  (str "ERR_PKG_IO: " what ": " e)

fn removeQuiet! path: String -> Unit
  (match (pathRemove path) ((ok _) ()) ((err _) ()))

; (:m :ref PKG-CLIENT :do "lock rows are one (:pkg ...) line each in ~/.asl/pkgs.asn, replaced as a whole file by write-then-rename so a crash leaves the previous lock")
fn lockRowText r: LockRow -> String
  (str "(:pkg :name \"" r.name "\" :version \"" r.version "\" :how \"" r.how "\" :sha256 \"" r.sha256 "\" :tree \"" r.tree "\" :deps ("
       (stringJoin (map (fn [(d ix/Dep)] -> String (str "(\"" d.name "\" \"" d.spec "\")")) r.deps) " ") "))")

fn depOfItem e: rd/SExpr -> ix/Dep
  (match e
    ((rd/sexprList items) (ix/Dep :name (ix/atomText (optionOr (listGet items 0) (rd/sexprAtom ""))) :spec (ix/atomText (optionOr (listGet items 1) (rd/sexprAtom "*")))))
    ((rd/sexprVect _) (ix/Dep :name "" :spec "*"))
    ((rd/sexprAtom a) (ix/Dep :name (ix/unquote a) :spec "*")))

fn depNames r: LockRow -> (List String)
  (map (fn [(d ix/Dep)] -> String d.name) r.deps)

fn parseLockRow line: String -> (Result LockRow String)
  (let [(items (rd/sexprToList (rd/parseSexpr line)))
        (name (ix/strField items ":name"))
        (version (ix/strField items ":version"))]
    (if (not (and (ix/validName? name) (ix/validVersion? version))) (err (str "ERR_PKG_LOCK: bad row " line))
      (ok (LockRow :name name :version version :how (ix/strField items ":how") :sha256 (ix/strField items ":sha256")
                   :tree (ix/strField items ":tree") :deps (map depOfItem (ix/listField items ":deps"))))))

fn parseLock text: String -> (Result (List LockRow) String)
  (ix/mapResult parseLockRow (filter (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:pkg ")) (stringLines text)))

fn ! readLock! ctx: Ctx -> (Result (List LockRow) String)
  (if (not (fileExists? (lockPath ctx))) (ok (list))
    (match (fileReadString (lockPath ctx))
      ((err e) (err (ioErr "read lock" e)))
      ((ok text) (parseLock text))))

fn ! writeAtomic! path: String text: String -> (Result Unit String)
  (let [(tmp (str path ".tmp-" (nowNs)))]
    (match (dirCreate (parentOf path))
      ((err e) (err (ioErr "mkdir" e)))
      ((ok _)
       (match (fileWrite tmp text)
         ((err e) (err (ioErr "write" e)))
         ((ok _)
          (match (pathRename tmp path)
            ((ok _) (ok ()))
            ((err e) (do (removeQuiet! tmp) (err (ioErr "rename" e))))))))))

fn ! writeLock! ctx: Ctx rows: (List LockRow) -> (Result Unit String)
  (let [(sorted (listSortBy (fn [(r LockRow)] -> String r.name) rows))]
    (writeAtomic! (lockPath ctx) (str (stringJoin (map lockRowText sorted) "\n") (if (listEmpty? sorted) "" "\n"))))

fn rowFor rows: (List LockRow) name: String -> (Option LockRow)
  (listFind (fn [(r LockRow)] -> Bool (= r.name name)) rows)

fn replaceRows rows: (List LockRow) fresh: (List LockRow) -> (List LockRow)
  (listAppend (filter (fn [(r LockRow)] -> Bool (not (listAny? (fn [(f LockRow)] -> Bool (= f.name r.name)) fresh))) rows) fresh)

; (:m :ref PKG-CLIENT :do "the lock file holds pid|process-start-time|token of its owner; a taker may displace it only when that process is dead or its start time differs (pid reuse), by renaming the old lock aside, checking the moved content is the content it judged stale, then creating its own exclusively; finish! removes the lock only when the token is its own")
fn ! startIdOf! pid: Int64 -> String
  (let [(o (fr/runGuarded (list "/bin/ps" "-o" "lstart=" "-p" (stringFromInt64 pid)) "/" (fr/childEnv (list)) (fr/limits 10 4)))]
    (if (= o.exitCode 0) (stringTrim o.stdout) ""))

fn ! ownerText! token: String -> String
  (str (procSelf) "|" (startIdOf! (procSelf)) "|" token)

fn ! lockOld? path: String -> Bool
  (match (fileStat path)
    ((err _) false)
    ((ok st) (> (- (/ (nowNs) 1000000000) st.mtime) 600)))

fn ! ownerStale? path: String content: String -> Bool
  (let [(parts (stringSplit (stringTrim content) "|"))
        (pid (optionOr (stringToInt64 (optionOr (listHead parts) "")) 0))]
    (if (< (listLength parts) 3) (lockOld? path)
      (match (procAlive? pid)
        ((err _) true)
        ((ok alive) (if alive (!= (optionOr (listGet parts 1) "") (startIdOf! pid)) true)))))

fn busy lock: String why: String -> String
  (str "ERR_PKG_BUSY: another asl pkg operation holds " lock ": " why)

fn ! acquire! lock: String token: String -> (Result Unit String)
  (let [(content (ownerText! token))]
    (match (fileCreateExclusive lock content)
      ((ok _) (ok ()))
      ((err e)
       (match (fileReadString lock)
         ((err _) (match (fileCreateExclusive lock content) ((ok _) (ok ())) ((err e2) (err (busy lock e2)))))
         ((ok seen)
          (if (not (ownerStale? lock seen)) (err (busy lock (stringTrim seen)))
            (let [(aside (str lock ".stale-" token))]
              (match (pathRename lock aside)
                ((err e3) (err (busy lock e3)))
                ((ok _)
                 (match (fileReadString aside)
                   ((err e4) (err (busy lock e4)))
                   ((ok moved)
                    (if (= moved seen)
                      (do (removeQuiet! aside)
                          (match (fileCreateExclusive lock content) ((ok _) (ok ())) ((err e5) (err (busy lock e5)))))
                      (do (removeQuiet! aside)
                          (match (fileCreateExclusive lock moved) ((ok _) ()) ((err _) ()))
                          (err (busy lock "taken over by another process")))))))))))))))

fn ! recoverTmp! root: String keep: String names: (List String) -> Unit
  (match (listHead names)
    ((none) ())
    ((some n)
     (do (if (and (or (stringStartsWith? n ".tmp-") (stringStartsWith? n ".lock.stale-")) (!= n keep)) (removeQuiet! (str root "/" n)) ())
         (recoverTmp! root keep (optionOr (listTail names) (list))))))

fn ! recoverLinks! ctx: Ctx rows: (List LockRow) -> Unit
  (match (listHead rows)
    ((none) ())
    ((some r)
     (do (if (and (!= (optionOr (previousOf ctx r.name) "") r.version) (fileExists? (str (verDir ctx r.name r.version) "/manifest.asn")))
           (match (setCurrent! ctx r.name r.version) ((ok _) ()) ((err _) ()))
           ())
         (recoverLinks! ctx (optionOr (listTail rows) (list))))))

; (:m :ref PKG-CLIENT :do "recovery runs under the lock at every begin!: temp dirs and aside locks of dead operations are deleted and a current link that disagrees with the lock row (a crash between link flip and lock write) is set back to the locked version")
fn ! recover! ctx: Ctx keep: String -> Unit
  (do (match (dirList (pkgsRoot ctx)) ((ok names) (recoverTmp! (pkgsRoot ctx) keep names)) ((err _) ()))
      (match (readLock! ctx) ((ok rows) (recoverLinks! ctx rows)) ((err _) ())))

fn tokenOfTmp tmp: String -> String
  (optionOr (listLast (stringSplit tmp "/.tmp-")) "")

fn ! begin! ctx: Ctx -> (Result String String)
  (let [(root (pkgsRoot ctx))
        (lock (str root "/.lock"))
        (token (str (procSelf) "-" (nowNs)))
        (tmp (str root "/.tmp-" token))]
    (match (dirCreate root)
      ((err e) (err (ioErr "mkdir" e)))
      ((ok _)
       (match (acquire! lock token)
         ((err e) (err e))
         ((ok _)
          (let [(_ (recover! ctx (str ".tmp-" token)))]
            (match (dirCreate tmp)
              ((err e) (do (finish! ctx tmp) (err (ioErr "mkdir" e))))
              ((ok _) (ok tmp)))))))))

fn ! finish! ctx: Ctx tmp: String -> Unit
  (let [(lock (str (pkgsRoot ctx) "/.lock"))]
    (do (removeQuiet! tmp)
        (match (fileReadString lock)
          ((ok c) (if (stringEndsWith? (stringTrim c) (str "|" (tokenOfTmp tmp))) (removeQuiet! lock) ()))
          ((err _) ()))))

; (:m :ref PKG-CLIENT :do "a file:// copy is capped by fileSize before it is read, and a file:/// artefact is fetched only when the index itself is a file:/// one, so an https index can never make the client read a local file")
fn ! copyFile! ctx: Ctx from: String to: String -> (Result Unit String)
  (match (fileSize from)
    ((err e) (err (str "ERR_PKG_FETCH: " e)))
    ((ok n)
     (if (> n ctx.maxBytes) (err (str "ERR_PKG_SIZE: " from " is " n " bytes, over the " ctx.maxBytes " byte cap"))
       (match (fileReadBytes from)
         ((err e) (err (str "ERR_PKG_FETCH: " e)))
         ((ok bytes) (match (fileWrite to bytes) ((err e) (err (ioErr "write" e))) ((ok _) (ok ()))))))))

fn ! fetch! ctx: Ctx url: String dest: String -> (Result Unit String)
  (cond
    ((and (stringStartsWith? url "file:///") (not (stringStartsWith? ctx.indexUrl "file:///")))
     (err (str "ERR_PKG_URL: a local file artefact is refused because the index is not a file:/// index: " url)))
    ((stringStartsWith? url "file:///") (copyFile! ctx (optionOr (stringSlice url 7 (stringLength url)) "") dest))
    ((stringStartsWith? url "https://")
     (let [(o (fr/runGuarded (list "/usr/bin/curl" "-q" "-fsSL" "-g" "--proto" "=https" "--proto-redir" "=https" "--max-time" (stringFromInt64 ctx.timeoutS) "--max-filesize" (stringFromInt64 ctx.maxBytes) "-o" dest "--" url)
                             (parentOf dest) (fr/childEnv (list)) (fr/limits (+ ctx.timeoutS 5) 16)))]
       (if (= o.exitCode 0) (ok ()) (err (str "ERR_PKG_FETCH: curl exit " o.exitCode " for " url ": " (stringTrim o.stderr))))))
    (else (err (str "ERR_PKG_URL: only file:/// and https:// are fetched, got " url))))

fn ! readIndex! ctx: Ctx tmp: String -> (Result ix/Index String)
  (let [(local (str tmp "/index.asn"))]
    (if (stringEmpty? ctx.indexUrl) (err "ERR_PKG_CONFIG: no :index URL in ~/.asl/pkg.asn")
      (match (fetch! ctx ctx.indexUrl local)
        ((err e) (err e))
        ((ok _) (match (fileReadString local) ((err e) (err (ioErr "read index" e))) ((ok text) (ix/parseIndex text)))))))

; (:m :ref PKG-CLIENT :do "every tar entry is checked before anything is unpacked: names from tar -t must be relative with no .. segment, tar -tv types must be regular files or directories, and the sizes in the -tv lines must sum under the byte cap with the entry count under its cap, so links, devices, escaping paths and decompression bombs never reach the disk")
fn safeEntry? name: String -> Bool
  (and (and (not (stringEmpty? name)) (not (stringStartsWith? name "/")))
       (and (not (stringContains? name "\\")) (not (listContains? (stringSplit name "/") ".."))))

fn tokensOf line: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " "))

; (:m :ref PKG-CLIENT :do "bsdtar -tv prints perm links owner group size and GNU tar prints perm owner/group size, so a slash in the second token says which column holds the size")
fn entrySize line: String -> (Option Int64)
  (let [(ts (tokensOf line))]
    (stringToInt64 (optionOr (listGet ts (if (stringContains? (optionOr (listGet ts 1) "") "/") 2 4)) "")))

fn sizesOf types: (List String) -> (Option Int64)
  (match (listHead types)
    ((none) (some 0))
    ((some l)
     (match (entrySize l)
       ((none) (none))
       ((some n) (optionMap (fn [(rest Int64)] -> Int64 (+ n rest)) (sizesOf (optionOr (listTail types) (list))))))))

fn tarListsOk names: String types: String maxBytes: Int64 maxEntries: Int64 -> (Result Unit String)
  (let [(ns (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines names)))
        (ts (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines types)))
        (badName (listFind (fn [(n String)] -> Bool (not (safeEntry? n))) ns))
        (badType (listFind (fn [(l String)] -> Bool (not (or (stringStartsWith? l "-") (stringStartsWith? l "d")))) ts))
        (total (sizesOf ts))]
    (cond
      ((listEmpty? ns) (err "ERR_PKG_TAR: empty archive"))
      ((some? badName) (err (str "ERR_PKG_TAR: unsafe entry name " (optionOr badName ""))))
      ((some? badType) (err (str "ERR_PKG_TAR: entry is not a plain file or directory: " (optionOr badType ""))))
      ((> (listLength ns) maxEntries) (err (str "ERR_PKG_SIZE: " (listLength ns) " entries, over the " maxEntries " entry cap")))
      ((none? total) (err "ERR_PKG_SIZE: cannot read entry sizes from the archive listing"))
      ((> (optionOr total 0) maxBytes) (err (str "ERR_PKG_SIZE: " (optionOr total 0) " unpacked bytes, over the " maxBytes " byte cap")))
      (else (ok ()))))

fn ! checkTar! ctx: Ctx tgz: String cwd: String -> (Result Unit String)
  (let [(lim (fr/limits ctx.timeoutS 8))
        (names (fr/runGuarded (list "/usr/bin/tar" "-tzf" tgz) cwd (fr/childEnv (list)) lim))
        (types (fr/runGuarded (list "/usr/bin/tar" "-tvzf" tgz) cwd (fr/childEnv (list)) lim))]
    (if (or (!= names.exitCode 0) (!= types.exitCode 0)) (err (str "ERR_PKG_TAR: cannot list archive: " (stringTrim names.stderr) (stringTrim types.stderr)))
      (tarListsOk names.stdout types.stdout ctx.maxBytes ctx.maxEntries)))

; (:m :ref PKG-CLIENT :do "treeDigest! is sha256 over sorted 'relpath digest' lines of an unpacked tree where a file digest is sha256 of its 1 MiB chunk digests (nothing is read whole), and it fails on any symlink or special file, a second line of defence behind checkTar!; verify recomputes it against the lock row")
fn ! fileChunks! path: String size: Int64 off: Int64 acc: (List String) -> (Result String String)
  (if (>= off size) (ok (bytesSha256 (stringToBytes (stringJoin (listReverse acc) ","))))
    (match (fileReadRange path off 1048576)
      ((err e) (err (ioErr "read" e)))
      ((ok b) (fileChunks! path size (+ off 1048576) (cons (bytesSha256 b) acc)))))

fn ! digestEntries! base: String rel: String names: (List String) -> (Result (List String) String)
  (match (listHead names)
    ((none) (ok (list)))
    ((some n)
     (let [(relPath (if (stringEmpty? rel) n (str rel "/" n)))
           (full (str base "/" relPath))]
       (match (fileLstat full)
         ((err e) (err (ioErr "lstat" e)))
         ((ok st)
          (match (cond
                   (st.isSymlink (err (str "ERR_PKG_TAR: symlink in package: " relPath)))
                   (st.isDir (digestDir! base relPath))
                   (st.isFile (match (fileChunks! full st.size 0 (list)) ((err e) (err e)) ((ok d) (ok (list (str relPath " " d))))))
                   (else (err (str "ERR_PKG_TAR: special file in package: " relPath))))
            ((err e) (err e))
            ((ok here)
             (match (digestEntries! base rel (optionOr (listTail names) (list)))
               ((err e) (err e))
               ((ok more) (ok (listAppend here more)))))))))))

fn ! digestDir! base: String rel: String -> (Result (List String) String)
  (match (dirList (if (stringEmpty? rel) base (str base "/" rel)))
    ((err e) (err (ioErr "list" e)))
    ((ok names) (digestEntries! base rel names)))

fn ! treeDigest! dir: String -> (Result String String)
  (match (digestDir! dir "")
    ((err e) (err e))
    ((ok lines) (ok (bytesSha256 (stringToBytes (stringJoin (listSort lines) "\n"))))))

fn ! buildCheck! ctx: Ctx unpack: String -> (Result Unit String)
  (if (stringEmpty? ctx.aslBin) (err "ERR_PKG_NOBUILD: source package needs an asl binary to check it, none configured")
    (match (fileReadString (str unpack "/manifest.asn"))
      ((err e) (err (ioErr "read manifest" e)))
      ((ok text)
       (let [(entry (ix/strField (rd/sexprToList (rd/parseSexpr text)) ":entry"))]
         (if (not (safeEntry? entry)) (err (str "ERR_PKG_BUILD: manifest :entry '" entry "' is missing or unsafe"))
           (let [(o (fr/runGuarded (list ctx.aslBin "check" (str unpack "/" entry)) unpack (fr/childEnv (list)) (fr/limits ctx.timeoutS 32)))]
             (if (= o.exitCode 0) (ok ()) (err (str "ERR_PKG_BUILD: asl check exit " o.exitCode ": " (stringTrim o.stdout) (stringTrim o.stderr))))))))))

; (:m :ref PKG-CLIENT :do "stageArtefact! never touches the installed state: download, sha256 against the index, tar checks, unpack to the temp dir, digest, optional source check, then one rename into ~/.asl/pkgs/NAME/VER; v0 never runs anything shipped inside a package")
fn ! stageArtefact! ctx: Ctx tmp: String name: String ver: ix/Version how: String a: ix/Artefact -> (Result Staged String)
  (let [(work (str tmp "/" name "-" ver.v))
        (tgz (str work "/pkg.tgz"))
        (unpack (str work "/unpack"))
        (dest (verDir ctx name ver.v))]
    (match (dirCreate unpack)
      ((err e) (err (ioErr "mkdir" e)))
      ((ok _)
       (match (fetch! ctx a.url tgz)
         ((err e) (err e))
         ((ok _)
          (match (fileReadBytes tgz)
            ((err e) (err (ioErr "read" e)))
            ((ok bytes)
             (if (!= (bytesSha256 bytes) a.sha256) (err (str "ERR_PKG_SHA256: " name "@" ver.v " " a.url (if (stringStartsWith? a.url "file:///") " does not match the index digest " (str " is " (bytesSha256 bytes) ", index says " a.sha256))))
               (match (checkTar! ctx tgz work)
                 ((err e) (err e))
                 ((ok _)
                  (let [(x (fr/runGuarded (list "/usr/bin/tar" "-xzf" tgz "-C" unpack) work (fr/childEnv (list)) (fr/limits ctx.timeoutS 8)))]
                    (if (!= x.exitCode 0) (err (str "ERR_PKG_TAR: unpack failed: " (stringTrim x.stderr)))
                      (if (not (fileExists? (str unpack "/manifest.asn"))) (err (str "ERR_PKG_TAR: " name "@" ver.v " has no manifest.asn at its root"))
                        (match (treeDigest! unpack)
                          ((err e) (err e))
                          ((ok tree)
                           (match (if (= how "source") (buildCheck! ctx unpack) (ok ()))
                             ((err e) (err e))
                             ((ok _)
                              (let [(_ (removeQuiet! dest))]
                                (match (dirCreate (pkgDir ctx name))
                                  ((err e) (err (ioErr "mkdir" e)))
                                  ((ok _)
                                   (match (pathRename unpack dest)
                                     ((err e) (err (ioErr "rename" e)))
                                     ((ok _) (ok (Staged :row (LockRow :name name :version ver.v :how how :sha256 a.sha256 :tree tree :deps ver.deps) :dir dest))))))))))))))))))))))))

fn ! stageOne! ctx: Ctx tmp: String name: String ver: ix/Version -> (Result Staged String)
  (match (ix/artefactFor ver ctx.triple)
    ((some a) (stageArtefact! ctx tmp name ver "binary" a))
    ((none)
     (match (listHead ver.source)
       ((some s) (stageArtefact! ctx tmp name ver "source" s))
       ((none) (err (str "ERR_PKG_NOARTEFACT: " name "@" ver.v " has no artefact for " ctx.triple " and no source"))))))

fn ! stageAll! ctx: Ctx tmp: String items: (List (Pair String ix/Version)) -> (Result (List Staged) String)
  (match (listHead items)
    ((none) (ok (list)))
    ((some it)
     (match (stageOne! ctx tmp (pairFirst it) (pairSecond it))
       ((err e) (err e))
       ((ok s)
        (match (stageAll! ctx tmp (optionOr (listTail items) (list)))
          ((err e) (do (removeQuiet! s.dir) (err e)))
          ((ok rest) (ok (cons s rest))))))))

fn ! setCurrent! ctx: Ctx name: String v: String -> (Result Unit String)
  (let [(link (str (pkgDir ctx name) "/.current-" (nowNs)))]
    (match (pathSymlink v link)
      ((err e) (err (ioErr "symlink" e)))
      ((ok _)
       (match (pathRename link (currentPath ctx name))
         ((ok _) (ok ()))
         ((err e) (do (removeQuiet! link) (err (ioErr "rename current" e))))))))

fn ! restoreCurrent! ctx: Ctx name: String prev: (Option String) -> Unit
  (match prev
    ((some v) (match (setCurrent! ctx name v) ((ok _) ()) ((err _) ())))
    ((none) (removeQuiet! (currentPath ctx name))))

fn ! previousOf ctx: Ctx name: String -> (Option String)
  (match (fileReadlink (currentPath ctx name)) ((ok t) (some t)) ((err _) (none)))

fn ! unflip! ctx: Ctx flipped: (List (Pair String (Option String))) -> Unit
  (match (listHead flipped)
    ((none) ())
    ((some f) (do (restoreCurrent! ctx (pairFirst f) (pairSecond f)) (unflip! ctx (optionOr (listTail flipped) (list))))))

fn ! flipAll! ctx: Ctx staged: (List Staged) done: (List (Pair String (Option String))) -> (Result (List (Pair String (Option String))) String)
  (match (listHead staged)
    ((none) (ok done))
    ((some s)
     (let [(prev (previousOf ctx s.row.name))]
       (match (setCurrent! ctx s.row.name s.row.version)
         ((err e) (do (unflip! ctx done) (err e)))
         ((ok _) (flipAll! ctx (optionOr (listTail staged) (list)) (cons (pair s.row.name prev) done)))))))

fn ! dropStaged! staged: (List Staged) -> Unit
  (match (listHead staged)
    ((none) ())
    ((some s) (do (removeQuiet! s.dir) (dropStaged! (optionOr (listTail staged) (list))))))

fn ! pruneOld! ctx: Ctx rows: (List LockRow) staged: (List Staged) -> Unit
  (match (listHead staged)
    ((none) ())
    ((some s)
     (do (match (rowFor rows s.row.name)
           ((some old) (if (!= old.version s.row.version) (removeQuiet! (verDir ctx old.name old.version)) ()))
           ((none) ()))
         (pruneOld! ctx rows (optionOr (listTail staged) (list))))))

; (:m :ref PKG-CLIENT :do "commit! is the only place state changes: flip every current link, then write the lock; if either step fails the links are restored and the freshly unpacked dirs are deleted, so the previous state is intact")
fn ! commit! ctx: Ctx rows: (List LockRow) staged: (List Staged) -> (Result Unit String)
  (match (flipAll! ctx staged (list))
    ((err e) (do (dropStaged! staged) (err e)))
    ((ok flipped)
     (match (writeLock! ctx (replaceRows rows (map (fn [(s Staged)] -> LockRow s.row) staged)))
       ((err e) (do (unflip! ctx flipped) (dropStaged! staged) (err e)))
       ((ok _) (do (pruneOld! ctx rows staged) (ok ()))))))

fn chosenFor plan: Plan name: String -> (Option ix/Version)
  (optionMap pairSecond (listFind (fn [(p (Pair String ix/Version))] -> Bool (= (pairFirst p) name)) plan.chosen))

fn pickVersion pkg: ix/Pkg rows: (List LockRow) spec: String prefer: Bool -> (Option ix/Version)
  (match (if prefer (rowFor rows pkg.name) (none))
    ((some r)
     (if (ix/versionSatisfies? spec r.version)
       (some (optionOr (ix/findVersion pkg r.version) (ix/Version :v r.version :artefacts (list) :source (list) :deps (list))))
       (ix/highestMatching pkg spec)))
    ((none) (ix/highestMatching pkg spec)))

fn resolveDeps idx: ix/Index rows: (List LockRow) deps: (List ix/Dep) plan: Plan -> (Result Plan String)
  (match (listHead deps)
    ((none) (ok plan))
    ((some d)
     (match (resolveOne idx rows d.name d.spec true plan)
       ((err e) (err e))
       ((ok p) (resolveDeps idx rows (optionOr (listTail deps) (list)) p)))))

fn resolveOne idx: ix/Index rows: (List LockRow) name: String spec: String prefer: Bool plan: Plan -> (Result Plan String)
  (match (chosenFor plan name)
    ((some v)
     (if (ix/versionSatisfies? spec v.v) (ok plan)
       (err (str "ERR_PKG_CONFLICT: " name " is already resolved to " v.v " which does not satisfy " spec))))
    ((none)
     (match (ix/findPkg idx name)
       ((none) (err (str "ERR_PKG_NOTFOUND: " name " is not in the index")))
       ((some pkg)
        (match (pickVersion pkg rows spec prefer)
          ((none) (err (str "ERR_PKG_NOVERSION: no version of " name " satisfies " spec)))
          ((some v)
           (match (resolveDeps idx rows v.deps (Plan :chosen (cons (pair name v) plan.chosen) :order plan.order))
             ((err e) (err e))
             ((ok p) (ok (Plan :chosen p.chosen :order (listAppend p.order (list name))))))))))))

fn planInstall idx: ix/Index rows: (List LockRow) reqs: (List (Pair String String)) prefer: Bool -> (Result Plan String)
  (match (listHead reqs)
    ((none) (ok (Plan :chosen (list) :order (list))))
    ((some r)
     (match (planInstall idx rows (optionOr (listTail reqs) (list)) prefer)
       ((err e) (err e))
       ((ok rest)
        (resolveOne idx rows (pairFirst r) (pairSecond r) prefer rest)))))

fn changes plan: Plan rows: (List LockRow) -> (List (Pair String ix/Version))
  (filter (fn [(p (Pair String ix/Version))] -> Bool
            (match (rowFor rows (pairFirst p)) ((some r) (!= r.version (pairSecond p).v)) ((none) true)))
          (map (fn [(n String)] -> (Pair String ix/Version) (pair n (optionOr (chosenFor plan n) (ix/Version :v "0" :artefacts (list) :source (list) :deps (list))))) plan.order))

fn receipt op: String staged: (List Staged) -> String
  (str "(:pkg :op " op " :installed (" (stringJoin (map (fn [(s Staged)] -> String (str "(" s.row.name " \"" s.row.version "\" " s.row.how ")")) staged) " ") "))")

; (:m :ref PKG-CLIENT :do "lock rows keep (name spec) deps, so before anything is staged every installed package's constraints are checked against the versions that will be current after the plan (its new version's deps when it is itself replaced); a violation is ERR_PKG_CONFLICT and nothing changes")
fn finalVersion rows: (List LockRow) plan: Plan name: String -> (Option String)
  (match (chosenFor plan name)
    ((some v) (some v.v))
    ((none) (optionMap (fn [(r LockRow)] -> String r.version) (rowFor rows name))))

fn checkDeps rows: (List LockRow) plan: Plan owner: String deps: (List ix/Dep) -> (Result Unit String)
  (match (listHead deps)
    ((none) (ok ()))
    ((some d)
     (match (finalVersion rows plan d.name)
       ((none) (checkDeps rows plan owner (optionOr (listTail deps) (list))))
       ((some fv)
        (if (ix/versionSatisfies? d.spec fv) (checkDeps rows plan owner (optionOr (listTail deps) (list)))
          (err (str "ERR_PKG_CONFLICT: " owner " needs " d.name " " d.spec " but " d.name " would be " fv)))))))

fn validateFinal rows: (List LockRow) plan: Plan -> (Result Unit String)
  (match (listHead rows)
    ((none) (ok ()))
    ((some r)
     (match (checkDeps rows plan r.name (match (chosenFor plan r.name) ((some v) v.deps) ((none) r.deps)))
       ((err e) (err e))
       ((ok _) (validateFinal (optionOr (listTail rows) (list)) plan)))))

fn ! applyPlan! ctx: Ctx tmp: String rows: (List LockRow) plan: Plan op: String -> (Result String String)
  (let [(todo (changes plan rows))]
    (if (listEmpty? todo) (ok (str "(:pkg :op " op " :installed () :note \"up to date\")"))
      (match (validateFinal rows plan)
        ((err e) (err e))
        ((ok _)
         (match (stageAll! ctx tmp todo)
           ((err e) (err e))
           ((ok staged)
            (match (commit! ctx rows staged)
              ((err e) (err e))
              ((ok _) (ok (receipt op staged))))))))))

fn ! withIndex! ctx: Ctx tmp: String reqs: (List (Pair String String)) prefer: Bool op: String -> (Result String String)
  (match (readLock! ctx)
    ((err e) (err e))
    ((ok rows)
     (match (readIndex! ctx tmp)
       ((err e) (err e))
       ((ok idx)
        (match (planInstall idx rows reqs prefer)
          ((err e) (err e))
          ((ok plan) (applyPlan! ctx tmp rows plan op)))))))

fn ! locked! ctx: Ctx op: String reqs: (List (Pair String String)) prefer: Bool -> (Result String String)
  (match (begin! ctx)
    ((err e) (err e))
    ((ok tmp)
     (let [(r (withIndex! ctx tmp reqs prefer op))
           (_ (finish! ctx tmp))]
       r)))

fn ! install! ctx: Ctx reqs: (List (Pair String String)) -> (Result String String)
  (locked! ctx "install" reqs true)

; (:m :ref PKG-CLIENT :do "update re-resolves each requested name to its highest version (dependencies keep an installed version that still satisfies them); with no names every installed package is requested")
fn ! update! ctx: Ctx names: (List String) -> (Result String String)
  (match (if (listEmpty? names) (match (readLock! ctx) ((ok rows) (ok (map (fn [(r LockRow)] -> String r.name) rows))) ((err e) (err e))) (ok names))
    ((err e) (err e))
    ((ok ns) (locked! ctx "update" (map (fn [(n String)] -> (Pair String String) (pair n "*")) ns) false)))

fn addMissing xs: (List String) more: (List String) -> (List String)
  (fold (fn [(acc (List String)) (n String)] -> (List String) (if (listContains? acc n) acc (listAppend acc (list n)))) xs more)

fn reachStep rows: (List LockRow) cur: (List String) -> (List String)
  (addMissing cur (listFlatMap (fn [(r LockRow)] -> (List String) (if (listContains? cur r.name) (depNames r) (list))) rows))

fn reachFrom rows: (List LockRow) cur: (List String) fuel: Int64 -> (List String)
  (if (<= fuel 0) cur (reachFrom rows (reachStep rows cur) (- fuel 1)))

; (:m :ref PKG-CLIENT :do "remove takes the strongly connected group with it: packages that reach NAME and are reached from NAME (a dependency cycle) go together; any other installed package that depends on a removed one blocks the removal")
fn ! removeLocked! ctx: Ctx name: String -> (Result String String)
  (match (readLock! ctx)
    ((err e) (err e))
    ((ok rows)
     (match (rowFor rows name)
       ((none) (err (str "ERR_PKG_NOTINSTALLED: " name)))
       ((some row)
        (let [(fuel (+ (listLength rows) 1))
              (down (reachFrom rows (list name) fuel))
              (group (filter (fn [(r LockRow)] -> Bool (or (= r.name name) (and (listContains? down r.name) (listContains? (reachFrom rows (list r.name) fuel) name)))) rows))
              (gnames (map (fn [(r LockRow)] -> String r.name) group))
              (users (filter (fn [(o LockRow)] -> Bool (and (not (listContains? gnames o.name)) (listAny? (fn [(g String)] -> Bool (listContains? (depNames o) g)) gnames))) rows))]
          (if (not (listEmpty? users)) (err (str "ERR_PKG_REQUIRED: " name " is required by " (stringJoin (map (fn [(o LockRow)] -> String o.name) users) " ")))
            (match (writeLock! ctx (filter (fn [(o LockRow)] -> Bool (not (listContains? gnames o.name))) rows))
              ((err e) (err e))
              ((ok _) (do (dropDirs! ctx gnames) (ok (str "(:pkg :op remove :name " name " :version \"" row.version "\" :removed (" (stringJoin gnames " ") "))")))))))))))

fn ! dropDirs! ctx: Ctx names: (List String) -> Unit
  (match (listHead names)
    ((none) ())
    ((some n) (do (removeQuiet! (pkgDir ctx n)) (dropDirs! ctx (optionOr (listTail names) (list))))))

fn ! remove! ctx: Ctx name: String -> (Result String String)
  (match (begin! ctx)
    ((err e) (err e))
    ((ok tmp)
     (let [(r (removeLocked! ctx name))
           (_ (finish! ctx tmp))]
       r)))

fn ! verifyRow! ctx: Ctx r: LockRow -> (Option String)
  (let [(dir (verDir ctx r.name r.version))]
    (cond
      ((not (fileExists? (str dir "/manifest.asn"))) (some (str r.name "@" r.version " is missing its files")))
      ((!= (optionOr (previousOf ctx r.name) "") r.version) (some (str r.name " current does not point at " r.version)))
      (else (match (treeDigest! dir)
              ((err e) (some (str r.name "@" r.version " " e)))
              ((ok d) (if (= d r.tree) (none) (some (str r.name "@" r.version " files differ from the installed digest"))))))))

fn ! verifyRows! ctx: Ctx rows: (List LockRow) -> (List String)
  (match (listHead rows)
    ((none) (list))
    ((some r)
     (let [(rest (verifyRows! ctx (optionOr (listTail rows) (list))))]
       (match (verifyRow! ctx r) ((some p) (cons p rest)) ((none) rest)))))

fn ! verify! ctx: Ctx -> (Result String String)
  (match (readLock! ctx)
    ((err e) (err e))
    ((ok rows)
     (let [(problems (verifyRows! ctx rows))]
       (if (listEmpty? problems) (ok (str "(:pkg :op verify :ok " (listLength rows) ")"))
         (err (str "ERR_PKG_VERIFY: " (stringJoin problems "; ")))))))

fn ! installed! ctx: Ctx -> (Result String String)
  (match (readLock! ctx)
    ((err e) (err e))
    ((ok rows) (ok (str "(:pkg :op list :installed (" (stringJoin (map (fn [(r LockRow)] -> String (str "(" r.name " \"" r.version "\" " r.how ")")) rows) " ") "))"))))

fn ! withTmpIndex! ctx: Ctx f: (fn [ix/Index (List LockRow)] -> String) -> (Result String String)
  (match (begin! ctx)
    ((err e) (err e))
    ((ok tmp)
     (let [(r (match (readLock! ctx)
                ((err e) (err e))
                ((ok rows) (match (readIndex! ctx tmp) ((err e) (err e)) ((ok idx) (ok (f idx rows)))))))
           (_ (finish! ctx tmp))]
       r)))

fn available! ctx: Ctx -> (Result String String)
  (withTmpIndex! ctx (fn [(idx ix/Index) (rows (List LockRow))] -> String
    (str "(:pkg :op available :packages ("
         (stringJoin (map (fn [(p ix/Pkg)] -> String (str "(" p.name " (" (stringJoin (map (fn [(v ix/Version)] -> String (str "\"" v.v "\"")) p.versions) " ") "))")) idx.pkgs) " ")
         "))")))

fn ! info! ctx: Ctx name: String -> (Result String String)
  (withTmpIndex! ctx (fn [(idx ix/Index) (rows (List LockRow))] -> String
    (match (ix/findPkg idx name)
      ((none) (str "(:pkg :op info :name " name " :found false)"))
      ((some p)
       (str "(:pkg :op info :name " name " :found true :installed "
            (match (rowFor rows name) ((some r) (str "\"" r.version "\"")) ((none) "none"))
            " :versions ("
            (stringJoin (map (fn [(v ix/Version)] -> String (str "(\"" v.v "\" :triples (" (stringJoin (map (fn [(a ix/Artefact)] -> String a.triple) v.artefacts) " ") ") :source " (if (listEmpty? v.source) "false" "true") ")")) p.versions) " ")
            "))")))))
