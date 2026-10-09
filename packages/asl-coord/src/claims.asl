(module asl-coord/claims
  :x [ClaimsStore Lease claimsStore! claimsAt leaseContent parseLease parseOwns
      pathsOverlap? claims! claim! release! pathAllowed!]
  :i [])

(schema ClaimsStore (:f workspace String) (:f root String) (:f retired String) (:f lock String))
(schema Lease (:f unit String) (:f owns (List String)) (:f branch String) (:f worktree String)
  (:f agent String) (:f host String) (:f pid Int64) (:f at Int64) (:f ttl Int64))

fn q s: String -> String
  (let [(a (stringReplace s "\\" "\\\\"))
        (b (stringReplace a "\"" "\\\""))]
    (str "\"" (stringReplace b "\n" "\\n") "\""))

fn shellQ s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! commandOutput! cmd: String -> String
  (let [(o (processRun cmd))]
    (if (= o.exitCode 0) (stringTrim o.stdout) ""))

fn gitCommand root: String args: String -> String
  (str "git -C " (shellQ root) " " args)

fn ! claimsLocate! workspace: String -> (Result ClaimsStore String)
  (let [(common (commandOutput! (gitCommand workspace "rev-parse --path-format=absolute --git-common-dir")))]
    (if (stringEmpty? common)
      (err (str "cannot resolve git common directory for " workspace))
      (let [(root (str common "/asl/claims"))]
        (ok (ClaimsStore :workspace workspace :root root :retired (str root "/retired") :lock (str root "/.lock"))))))

fn claimsStore! workspace: String -> (Result ClaimsStore String)
  (mt (claimsLocate! workspace)
    ((err e) (err e))
    ((ok store) (mt (dirCreate store.retired) ((err e) (err e)) ((ok _) (ok store)))))

fn ! storeExists? store: ClaimsStore -> Bool
  (mt (fileStat store.root) ((ok st) st.isDir) ((err _) false))

fn claimsAt store: ClaimsStore unit: String -> String
  (str store.root "/" unit ".asn")

fn skipSpaces text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (isSpaceChar (charAt text i)))
    (skipSpaces text (+ i 1))
    i)

fn charAt text: String i: Int64 -> String
  (optionOr (stringSlice text i (+ i 1)) "")

fn isSpaceChar c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn quoteTail text: String i: Int64 -> (Pair String Int64)
  (let [(n (stringLength text))]
    (if (>= i n)
      (pair "" n)
      (let [(c (charAt text i))]
        (cond
          ((= c "\\")
            (if (>= (+ i 1) n) (pair "" n)
              (let [(next (charAt text (+ i 1)))
                    (value (cond ((= next "n") "\n") ((= next "r") "\r") ((= next "t") "\t") (else next)))
                    (tail (quoteTail text (+ i 2)))]
                (pair (str value (pairFirst tail)) (pairSecond tail)))))
          ((= c "\"") (pair "" (+ i 1)))
          (else (let [(tail (quoteTail text (+ i 1)))]
                  (pair (str c (pairFirst tail)) (pairSecond tail))))))))

fn fieldStart text: String key: String -> Int64
  (let [(found (stringIndexOf text (str ":" key)))]
    (mt found ((some i) (skipSpaces text (+ i (stringLength key) 1))) ((none) (stringLength text))))

fn quotedField text: String key: String -> String
  (let [(i (fieldStart text key))]
    (if (and (< i (stringLength text)) (= (charAt text i) "\""))
      (pairFirst (quoteTail text (+ i 1)))
      ""))

fn atomEnd text: String i: Int64 -> Int64
  (if (or (>= i (stringLength text)) (isSpaceChar (charAt text i)) (= (charAt text i) ")"))
    i
    (atomEnd text (+ i 1)))

fn atomField text: String key: String -> String
  (let [(i (fieldStart text key))
        (start (if (and (< i (stringLength text)) (= (charAt text i) "\"")) (pairSecond (quoteTail text (+ i 1))) i))
        (end (atomEnd text start))]
    (optionOr (stringSlice text start end) ""))

fn quotedItems text: String i: Int64 acc: (List String) -> (List String)
  (let [(j (skipSpaces text i))]
    (cond
      ((>= j (stringLength text)) (listReverse acc))
      ((= (charAt text j) ")") (listReverse acc))
      ((= (charAt text j) "\"")
        (let [(item (quoteTail text (+ j 1)))]
          (quotedItems text (pairSecond item) (cons (pairFirst item) acc))))
      (else (quotedItems text (+ j 1) acc))))

fn parseOwns raw: String -> (List String)
  (let [(i (fieldStart raw "owns"))]
    (cond
      ((and (< i (stringLength raw)) (= (charAt raw i) "(")) (quotedItems raw (+ i 1) (list)))
      ((stringStartsWith? raw "(") (quotedItems raw 1 (list)))
      (else (list))))

fn parseNumber text: String key: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (atomField text key)) fallback)

fn leaseContent lease: Lease -> String
  (str "(:lease :unit " (q lease.unit)
       " :owns (" (stringJoin (map q lease.owns) " ") ")"
       " :branch " (q lease.branch) " :worktree " (q lease.worktree)
       " :agent " (q lease.agent) " :host " (q lease.host)
       " :pid " (stringFromInt64 lease.pid) " :at " (stringFromInt64 lease.at)
       " :ttl " (stringFromInt64 lease.ttl) ")\n")

fn parseLease raw: String -> Lease
  (Lease :unit (quotedField raw "unit") :owns (parseOwns raw)
         :branch (quotedField raw "branch") :worktree (quotedField raw "worktree")
         :agent (quotedField raw "agent") :host (quotedField raw "host")
         :pid (parseNumber raw "pid" 0) :at (parseNumber raw "at" 0) :ttl (parseNumber raw "ttl" 7200))

fn trimPath path: String -> String
  (cond
    ((stringStartsWith? path "./") (trimPath (optionOr (stringSlice path 2 (stringLength path)) "")))
    ((and (> (stringLength path) 1) (stringEndsWith? path "/"))
      (trimPath (optionOr (stringSlice path 0 (- (stringLength path) 1)) "")))
    (else path))

fn pathsOverlap? left: String right: String -> Bool
  (let [(a (trimPath left)) (b (trimPath right))]
    (or (= a b) (stringStartsWith? a (str b "/")) (stringStartsWith? b (str a "/"))))

fn pathWithin? path: String root: String -> Bool
  (let [(p (trimPath path)) (r (trimPath root))]
    (or (= p r) (stringStartsWith? p (str r "/"))))

fn pathUnderOwns? path: String owns: (List String) -> Bool
  (listAny? (fn [(root String)] -> Bool (pathWithin? path root)) owns)

fn exemptPath? path: String -> Bool
  (let [(p (trimPath path))]
    (or (= p "scripts/audit/foreignBaseline.asn") (= p "scripts/audit/foreignAllowlist.asn")))

fn listOverlapPath items: (List String) path: String -> String
  (mt (listHead items)
    ((none) "")
    ((some item)
      (if (and (not (exemptPath? path)) (and (not (exemptPath? item)) (pathsOverlap? path item)))
        item
        (listOverlapPath (optionOr (listTail items) (list)) path))))

fn readLease! path: String -> (Result Lease String)
  (mt (fileReadString path)
    ((err e) (err e))
    ((ok raw)
      (let [(lease (parseLease raw))]
        (if (or (stringEmpty? lease.unit) (stringEmpty? lease.branch))
          (err (str "invalid lease file: " path))
          (ok lease)))))

fn readNames! store: ClaimsStore names: (List String) acc: (List Lease) -> (Result (List Lease) String)
  (mt (listHead names)
    ((none) (ok (listReverse acc)))
    ((some name)
      (let [(rest (optionOr (listTail names) (list)))]
        (if (and (stringEndsWith? name ".asn") (!= name "log.asn") (not (stringStartsWith? name "retired")))
          (mt (readLease! (str store.root "/" name))
            ((err e) (err e))
            ((ok lease) (readNames! store rest (cons lease acc))))
          (readNames! store rest acc)))))

fn readLeases! store: ClaimsStore -> (Result (List Lease) String)
  (mt (dirList store.root)
    ((err e) (err e))
    ((ok names) (readNames! store names (list))))

fn ! isMerged? store: ClaimsStore lease: Lease -> Bool
  (let [(o (processRun (gitCommand store.workspace (str "merge-base --is-ancestor " (shellQ lease.branch) " main"))))]
    (= o.exitCode 0))

fn ! worktreeListed? store: ClaimsStore path: String -> Bool
  (let [(o (processRun (gitCommand store.workspace "worktree list --porcelain")))
        (needle (str "worktree " path))]
    (listAny? (fn [(line String)] -> Bool (= line needle)) (stringSplit o.stdout "\n")))

fn ! leaseStale? store: ClaimsStore lease: Lease -> Bool
  (let [(stat (fileStat (claimsAt store lease.unit)))
        (mtime (mt stat ((ok st) st.mtime) ((err _) 0)))
        (age (- (/ (nowNs) 1000000000) mtime))
        (pidAlive (and (> lease.pid 0) (mt (procAlive? lease.pid) ((ok b) b) ((err _) false))))
        (host (optionOr (envGet "HOSTNAME") (commandOutput! "hostname")))]
    (or (isMerged? store lease) (not (worktreeListed? store lease.worktree))
        (and (> age lease.ttl) (or (!= host lease.host) (not pidAlive)))))

fn retireLease! store: ClaimsStore unit: String -> (Result Unit String)
  (let [(source (claimsAt store unit))
        (target (str store.retired "/" unit "." (stringFromInt64 (nowNs)) ".asn"))]
    (mt (pathRename source target)
      ((ok _) (ok ()))
      ((err e) (if (stringContains? e "notFound") (ok ()) (err e)))))

fn retireStale! store: ClaimsStore leases: (List Lease) -> (Result Unit String)
  (mt (listHead leases)
    ((none) (ok ()))
    ((some lease)
      (let [(rest (optionOr (listTail leases) (list)))]
        (if (leaseStale? store lease)
          (mt (retireLease! store lease.unit)
            ((err e) (err e)) ((ok _) (retireStale! store rest)))
          (retireStale! store rest)))))

fn sweepLeases! store: ClaimsStore -> (Result (List Lease) String)
  (mt (readLeases! store)
    ((err e) (err e))
    ((ok leases)
      (mt (retireStale! store leases)
        ((err e) (err e))
        ((ok _) (readLeases! store)))))

fn lockAcquire! store: ClaimsStore -> (Result Int64 String)
  (fileLockWait store.lock true)

fn ! lockRelease! fd: Int64 -> (Result Unit String)
  (fdClose fd)

fn receipt unit: String by: String path: String -> String
  (str "(:refused :unit " (q unit) " :by " (q by) " :path " (q path) ")")

fn heartbeat! store: ClaimsStore unit: String -> (Result Unit String)
  (let [(p (claimsAt store unit))]
    (if (fileExists? p) (fileUtime p (nowNs)) (ok ())))

fn claims! workspace: String -> (Result String String)
  (mt (claimsLocate! workspace)
    ((err e) (err e))
    ((ok store)
      (if (not (storeExists? store)) (ok "(:claims)")
      (mt (lockAcquire! store)
        ((err e) (err e))
        ((ok fd)
          (let [(read (sweepLeases! store))
                (released (lockRelease! fd))]
            (mt released
              ((err e) (err e))
              ((ok _) (mt read
                ((err e) (err e))
                ((ok leases)
                  (ok (str "(:claims" (if (listEmpty? leases) "" (str " " (stringJoin (map leaseContent leases) " "))) ")"))))))))))))

fn pathAllowedLeases! store: ClaimsStore unit: String path: String leases: (List Lease) -> (Result String String)
  (mt (listHead leases)
    ((none) (mt (heartbeat! store unit) ((err e) (err e)) ((ok _) (ok ""))))
    ((some lease)
      (let [(rest (optionOr (listTail leases) (list)))
            (found (listOverlapPath lease.owns path))]
        (cond
          ((= unit lease.unit)
            (if (and (not (listEmpty? lease.owns)) (not (pathUnderOwns? path lease.owns)))
              (err (receipt unit unit path))
              (pathAllowedLeases! store unit path rest)))
          ((leaseStale? store lease) (pathAllowedLeases! store unit path rest))
          ((not (stringEmpty? found)) (err (receipt unit lease.unit path)))
          (else (pathAllowedLeases! store unit path rest))))))

fn pathAllowed! workspace: String unit: String rel: String -> (Result String String)
  (let [(caller (callerUnit! workspace unit))]
    (mt (claimsLocate! workspace)
      ((err e) (if (stringContains? e "cannot resolve git common directory") (ok "") (err e)))
      ((ok store)
        (if (not (storeExists? store)) (ok "")
        (mt (lockAcquire! store)
          ((err e) (err e))
          ((ok fd)
            (let [(result (mt (sweepLeases! store)
                           ((err e) (err e))
                           ((ok rows) (pathAllowedLeases! store caller (trimPath rel) rows))))
                  (released (lockRelease! fd))]
              (mt released
                ((err e) (err e))
                ((ok _) result)))))))))

fn ! envOr! name: String fallback: String -> String
  (optionOr (envGet name) fallback)

fn ! callerUnit! workspace: String given: String -> String
  (if (not (stringEmpty? given))
    given
    (let [(envUnit (envOr! "ASL_UNIT" ""))]
      (if (not (stringEmpty? envUnit))
        envUnit
        (let [(branch (commandOutput! (gitCommand workspace "branch --show-current")))]
          (if (stringStartsWith? branch "sh/")
            (optionOr (stringSlice branch 3 (stringLength branch)) "")
            "")))))

fn validUnit? unit: String -> Bool
  (and (not (stringEmpty? unit))
       (!= unit ".")
       (!= unit "..")
       (not (stringContains? unit "/"))
       (not (stringContains? unit "\\"))
       (not (stringContains? unit "..")))

fn validOwnsPath? path: String -> Bool
  (and (not (stringEmpty? path))
       (not (stringStartsWith? path "/"))
       (!= path "..")
       (not (stringStartsWith? path "../"))
       (not (stringContains? path "/../"))
       (not (stringEndsWith? path "/..")))

fn validOwns? paths: (List String) -> Bool
  (listAll? validOwnsPath? paths)

fn ! currentLease! workspace: String unit: String owns: (List String) -> Lease
  (Lease :unit unit :owns owns
    :branch (commandOutput! (gitCommand workspace "branch --show-current"))
    :worktree (resultOr (realPath workspace) workspace)
    :agent (envOr! "ASL_AGENT" (envOr! "ASL_SESSION" "unknown"))
    :host (envOr! "HOSTNAME" (commandOutput! "hostname"))
    :pid (optionOr (stringToInt64 (envOr! "ASL_LEASE_PID" "0")) 0)
    :at (nowNs) :ttl 7200)

fn claimConflicts unit: String owns: (List String) leases: (List Lease) -> String
  (mt (listHead leases)
    ((none) "")
    ((some lease)
      (let [(rest (optionOr (listTail leases) (list)))
            (first (overlapBetween owns lease.owns))]
        (if (= unit lease.unit)
          (claimConflicts unit owns rest)
          (if (stringEmpty? first)
            (claimConflicts unit owns rest)
            (receipt unit lease.unit first))))))

fn overlapBetween left: (List String) right: (List String) -> String
  (mt (listHead left)
    ((none) "")
    ((some path)
      (let [(hit (listOverlapPath right path))]
        (if (stringEmpty? hit) (overlapBetween (optionOr (listTail left) (list)) right) path))))

fn sameLeaseOwner? a: Lease b: Lease -> Bool
  (and (= a.host b.host)
       (= a.branch b.branch)
       (= a.agent b.agent))

fn leaseForUnit leases: (List Lease) unit: String -> (Option Lease)
  (mt (listHead leases)
    ((none) (none))
    ((some lease)
      (if (= unit lease.unit)
        (some lease)
        (leaseForUnit (optionOr (listTail leases) (list)) unit))))

fn logClaim! store: ClaimsStore lease: Lease -> (Result String String)
  (mt (fileAppend (str store.root "/log.asn") (str "(:claimed :unit " (q lease.unit) " :at " (stringFromInt64 (nowNs)) ")\n"))
    ((ok _) (ok (str "(:claimed :unit " (q lease.unit) ")")))
    ((err e)
      (mt (pathRemove (claimsAt store lease.unit))
        ((err cleanup) (err (str e "; claim rollback failed: " cleanup)))
        ((ok _) (err e)))))

fn writeClaim! store: ClaimsStore lease: Lease -> (Result String String)
  (mt (fileCreateExclusive (claimsAt store lease.unit) (leaseContent lease))
    ((ok _) (logClaim! store lease))
    ((err e) (if (stringContains? e "exists") (err (receipt lease.unit lease.unit (optionOr (listHead lease.owns) ""))) (err e))))

fn claimUnderLock! store: ClaimsStore unit: String owns: (List String) -> (Result String String)
  (mt (readLeases! store)
    ((err e) (err e))
    ((ok leases)
      (mt (retireStale! store leases)
        ((err e) (err e))
        ((ok _)
          (mt (readLeases! store)
            ((err e) (err e))
            ((ok live)
              (let [(self (currentLease! store.workspace unit owns))
                    (previous (leaseForUnit live unit))
                    (others (filter (fn [(lease Lease)] -> Bool (!= unit lease.unit)) live))
                    (refusal (claimConflicts unit owns others))]
                (if (not (stringEmpty? refusal))
                  (err refusal)
                  (mt previous
                    ((some prior)
                      (if (not (sameLeaseOwner? prior self))
                        (err (receipt unit unit (optionOr (listHead owns) "")))
                        (mt (retireLease! store unit)
                          ((err e) (err e))
                          ((ok _) (writeClaim! store self)))))
                    ((none) (writeClaim! store self)))))))))))

fn claim! workspace: String unit: String owns: (List String) -> (Result String String)
  (if (or (not (validUnit? unit)) (not (validOwns? owns)))
    (err (receipt unit "" ""))
    (mt (claimsStore! workspace)
      ((err e) (err e))
      ((ok store)
        (mt (lockAcquire! store)
          ((err e) (err e))
          ((ok fd)
            (let [(result (claimUnderLock! store unit owns))
                  (released (lockRelease! fd))]
              (mt released ((err e) (err e)) ((ok _) result))))))))

fn logRelease! store: ClaimsStore unit: String receipt: String -> (Result String String)
  (mt (fileAppend (str store.root "/log.asn") (str "(:released :unit " (q unit) " :at " (stringFromInt64 (nowNs)) ")\n"))
    ((err e) (err e))
    ((ok _) (ok receipt)))

fn releaseUnderLock! store: ClaimsStore unit: String -> (Result String String)
  (mt (sweepLeases! store)
    ((err e) (err e))
    ((ok live)
      (mt (leaseForUnit live unit)
        ((none) (ok (str "(:released :unit " (q unit) " :absent true)")))
        ((some held)
          (let [(caller (callerUnit! store.workspace ""))
                (self (currentLease! store.workspace unit (list)))]
            (if (or (!= caller unit) (not (sameLeaseOwner? held self)))
              (err (receipt caller unit (optionOr (listHead held.owns) "")))
              (mt (pathRemove (claimsAt store unit))
                ((err e) (err e))
                ((ok _) (logRelease! store unit (str "(:released :unit " (q unit) ")"))))))))))

fn release! workspace: String unit: String -> (Result String String)
  (if (not (validUnit? unit))
    (err (receipt unit "" ""))
    (mt (claimsLocate! workspace)
      ((err e) (err e))
      ((ok store)
        (if (not (storeExists? store))
          (ok (str "(:released :unit " (q unit) " :absent true)"))
          (mt (lockAcquire! store)
            ((err e) (err e))
            ((ok fd)
              (let [(result (releaseUnderLock! store unit))
                    (released (lockRelease! fd))]
                (mt released ((err e) (err e)) ((ok _) result)))))))))
