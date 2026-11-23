(module asl-tools/remote/sync
  :x [gitSafe git! gitOut! receiptErr readStdin! readStdinFrom! bundleFile! dropBundle! pushBranch! pullBranch! vpsReceive! vpsSend! remoteRef bundleRange]
  :i [(asl-tools/remote/form :a fm) (asl-tools/remote/transport :a tr)])

; (:m :ref REMOTE-BUNDLE :do "commits move between the Mac and a VPS-only clone as git bundles carried base64 over the ssh stdin and stdout; the asex root gains no remote (workspaceIsolation): the pull side fetches from the bundle file path straight into refs/remote-vps/UNIT")
fn remoteRef unit: String -> String
  (str "refs/remote-vps/" unit)

fn bundleRange base: String branch: String -> String
  (if (stringEmpty? base) branch (str base ".." branch))

fn receiptErr code: String msg: String -> String
  (str "(:err :code " code " :msg " (fm/quoteText msg) ")")

; (:m :ref REMOTE-GITSAFE :do "git on a tree the other side controls runs without hooks or fsmonitor (protocol.file.allow=never was tried and blocks the bundle fetch, whose path counts as the file transport)")
fn gitSafe -> (List String)
  (list "git" "-c" "core.hooksPath=/dev/null" "-c" "core.fsmonitor=")

fn ! git! dir: String args: (List String) -> (Result String String)
  (let [(d (tr/run! (listAppend (listAppend (gitSafe) (list "-C" dir)) args) 120))]
    (if (= d.exitCode 0) (ok d.stdout) (err (stringTrim (str d.stdout d.stderr)))))

fn ! gitOut! dir: String args: (List String) -> (Result String String)
  (resultMap (git! dir args) stringTrim)

fn ! readStdinFrom! fd: Int64 acc: (List String) used: Int64 cap: Int64 -> (Option String)
  (match (fdRead fd 65536)
    ((err _) (some (stringJoin (listReverse acc) "")))
    ((ok chunk)
      (cond
        ((stringEmpty? chunk) (some (stringJoin (listReverse acc) "")))
        ((> (+ used (stringLength chunk)) cap) (none))
        (else (readStdinFrom! fd (cons chunk acc) (+ used (stringLength chunk)) cap)))))

; (:m :ref REMOTE-STDINCAP :do "stdin is read up to a cap and a longer payload is refused, so a peer cannot fill the VPS memory through a forced command")
fn ! readStdin! cap: Int64 -> (Option String)
  (readStdinFrom! 0 (list) 0 cap)

fn goodRef? s: String -> Bool
  (and (fm/safeToken? s) (and (not (stringStartsWith? s "-")) (and (not (stringContains? s ":")) (not (stringContains? s "..")))))

fn ! bundleFile! tag: String -> String
  (str (resultOr (tr/privateDir! tag) (tr/scratchDir!)) "/data.bundle")

fn ! dropBundle! path: String -> Bool
  (ok? (pathRemove (optionOr (stringSlice path 0 (- (stringLength path) 12)) path)))

fn ! writeB64! path: String b64: String -> (Result Unit String)
  (match (bytesFromBase64 (stringTrim b64))
    ((err e) (err (str "bad base64: " e)))
    ((ok bytes) (fileWrite path bytes)))

fn ! readB64! path: String -> (Result String String)
  (resultMap (fileReadBytes path) bytesToBase64)

fn ! pushBranch! cfg: tr/Config root: String unit: String branch: String base: String -> String
  (cond
    ((not (fm/safeUnit? unit)) (receiptErr "badUnit" "unit must match [A-Za-z0-9-]+"))
    ((not (goodRef? branch)) (receiptErr "badBranch" "branch holds a character outside the allowlist"))
    ((and (not (stringEmpty? base)) (not (goodRef? base))) (receiptErr "badBase" "base holds a character outside the allowlist"))
    (else
      (let [(path (bundleFile! "push"))
            (made (git! root (list "bundle" "create" "-q" path (bundleRange base branch))))
            (sent (match made
                    ((err e) (err (str "bundle create: " e)))
                    ((ok _) (match (readB64! path)
                              ((err e) (err e))
                              ((ok b64) (tr/ssh! cfg (list "sync-recv" unit branch) b64))))))
            (_ (dropBundle! path))]
        (match sent
          ((err e) (receiptErr "pushFailed" e))
          ((ok out) (stringTrim out))))))

fn tipOf receipt: String -> String
  (match (fm/parseForm receipt)
    ((err _) "")
    ((ok node) (match (fm/formGet node ":tip") ((some n) (optionOr (fm/formText n) "")) ((none) ""))))

fn ! pullBranch! cfg: tr/Config root: String unit: String branch: String base: String -> String
  (cond
    ((not (fm/safeUnit? unit)) (receiptErr "badUnit" "unit must match [A-Za-z0-9-]+"))
    ((not (goodRef? branch)) (receiptErr "badBranch" "branch holds a character outside the allowlist"))
    ((and (not (stringEmpty? base)) (not (goodRef? base))) (receiptErr "badBase" "base holds a character outside the allowlist"))
    (else
      (match (tr/ssh! cfg (if (stringEmpty? base) (list "sync-send" unit branch) (list "sync-send" unit branch base)) "")
        ((err e) (receiptErr "pullFailed" e))
        ((ok out)
          (let [(lines (stringLines (stringTrim out)))
                (head (optionOr (listHead lines) ""))
                (b64 (stringJoin (optionOr (listTail lines) (list)) ""))
                (path (bundleFile! "pull"))
                (landed (match (writeB64! path b64)
                          ((err e) (err e))
                          ((ok _) (git! root (list "fetch" "-q" path (str "+refs/heads/" branch ":" (remoteRef unit)))))))
                (_ (dropBundle! path))]
            (match landed
              ((err e) (receiptErr "fetchFailed" e))
              ((ok _) (str "(:fetched :unit " unit " :ref " (remoteRef unit) " :tip " (resultOr (gitOut! root (list "rev-parse" (remoteRef unit))) "") " :remote " (tipOf head) ")"))))))))

fn ! ensureClone! dir: String -> (Result Unit String)
  (if (fileExists? (str dir "/.git"))
    (ok ())
    (match (dirCreate dir)
      ((err e) (err e))
      ((ok _) (resultMap (git! dir (list "init" "-q")) (fn [(_ String)] -> Unit ())))))

fn ! checkedOut? dir: String branch: String -> Bool
  (if (ok? (git! dir (list "rev-parse" "-q" "--verify" "HEAD")))
    false
    (ok? (git! dir (list "checkout" "-q" "-B" branch (str "refs/vps/in/" branch)))))

fn ! vpsReceive! root: String unit: String branch: String b64: String -> String
  (let [(dir (str root "/work/" unit))
        (meta (str root "/work/.remote"))
        (_ (dirCreate (str root "/work")))
        (_ (dirCreate meta))
        (path (str meta "/" unit ".bundle"))]
    (cond
      ((not (goodRef? branch)) (receiptErr "badBranch" "branch holds a character outside the allowlist"))
      (else
        (match (ensureClone! dir)
          ((err e) (receiptErr "noClone" e))
          ((ok _)
            (match (writeB64! path b64)
              ((err e) (receiptErr "badBundle" e))
              ((ok _)
                (let [(fetched (git! dir (list "fetch" "-q" path (str "+refs/heads/" branch ":refs/vps/in/" branch))))
                      (_ (pathRemove path))]
                  (match fetched
                    ((err e) (receiptErr "fetchFailed" e))
                    ((ok _) (let [(tip (resultOr (gitOut! dir (list "rev-parse" (str "refs/vps/in/" branch))) ""))
                                  (out (checkedOut? dir branch))]
                              (str "(:recv :unit " unit " :branch " branch " :tip " tip " :checkedOut " (if out "true" "false") ")"))))))))))))

fn ! vpsSend! root: String unit: String branch: String base: String -> String
  (let [(dir (str root "/work/" unit))
        (meta (str root "/work/.remote"))
        (_ (dirCreate meta))
        (path (str meta "/" unit ".out.bundle"))]
    (cond
      ((not (goodRef? branch)) (receiptErr "badBranch" "branch holds a character outside the allowlist"))
      ((and (not (stringEmpty? base)) (not (goodRef? base))) (receiptErr "badBase" "base holds a character outside the allowlist"))
      ((not (fileExists? (str dir "/.git"))) (receiptErr "noClone" "no clone for this unit"))
      (else
        (match (git! dir (list "bundle" "create" "-q" path (bundleRange base (str "refs/heads/" branch))))
          ((err e) (receiptErr "bundleFailed" e))
          ((ok _)
            (let [(tip (resultOr (gitOut! dir (list "rev-parse" (str "refs/heads/" branch))) ""))
                  (b64 (resultOr (readB64! path) ""))
                  (_ (pathRemove path))]
              (str "(:send :unit " unit " :branch " branch " :tip " tip ")\n" b64)))))))
