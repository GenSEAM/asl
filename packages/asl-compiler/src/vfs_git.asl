(module asl-compiler/vfs-git
  :d "Pure AgentScript sovereign Git VFS reader for inspecting git repositories without POSIX git subprocesses."
  :x [gitReadHead
      gitCurrentBranch
      gitParsePackedRefs
      gitResolveRefCommit
      gitHeadCommit
      gitParseConfig
      gitInspectRepoStatus
      normalizePath
      gitResolveDirs]
  :i [(wasi :a wasi)])

(df normalizePath [(p Str)] -> Str
  :d "Normalizes a filesystem path by resolving dot and dotdot segments."
  (let [(isAbs (string-starts-with? p "/"))
        (parts (string-split p "/"))
        (filtered (fold (fn [(acc (List Str)) (seg Str)]
                          (cond
                            ((or (string-empty? seg) (= seg ".")) acc)
                            ((= seg "..")
                             (if (> (list-length acc) 0)
                                 (list-take acc (- (list-length acc) 1))
                                 (if isAbs acc (list-append acc (list "..")))))
                            (:else (list-append acc (list seg)))))
                        (list)
                        parts))
        (joined (string-join "/" filtered))]
    (if isAbs (str "/" joined) (if (string-empty? joined) "." joined))))

(df gitResolveDirs [(repoRoot Str)] -> (Result (Map Str Str) Str)
  :d "Resolves gitdir and commondir paths supporting standard repositories, worktrees, and submodules."
  (let [(dotGit (if (string-empty? repoRoot) ".git" (str repoRoot "/.git")))
        (directHeadRes (wasi/wasiFileRead (str dotGit "/HEAD")))]
    (mt directHeadRes
      ((ok _)
       (ok (map-set (map-set (map-empty) "gitdir" dotGit) "commondir" dotGit)))
      ((err _)
       (let [(dotGitRes (wasi/wasiFileRead dotGit))]
         (mt dotGitRes
           ((ok text)
            (let [(trimmed (string-trim text))]
              (if (string-starts-with? trimmed "gitdir: ")
                  (let [(raw (string-trim (option-or (string-slice trimmed 8 (string-length trimmed)) "")))
                        (rawResolved (if (string-starts-with? raw "/")
                                         raw
                                         (if (string-empty? repoRoot) raw (str repoRoot "/" raw))))
                        (gitdir (normalizePath rawResolved))
                        (commonFile (str gitdir "/commondir"))
                        (commonRes (wasi/wasiFileRead commonFile))
                        (commondir (mt commonRes
                                     ((ok cText)
                                      (let [(cTrim (string-trim cText))]
                                        (if (string-starts-with? cTrim "/")
                                            (normalizePath cTrim)
                                            (normalizePath (str gitdir "/" cTrim)))))
                                     ((err _) gitdir)))]
                    (ok (map-set (map-set (map-empty) "gitdir" gitdir) "commondir" commondir)))
                  (err "ERR_GIT_HEAD_NOT_FOUND"))))
           ((err _) (err "ERR_GIT_HEAD_NOT_FOUND"))))))))

(df gitReadHead [(repoRoot Str)] -> (Result Str Str)
  :d "Reads .git/HEAD to determine current ref or detached state."
  (let [(dirsRes (gitResolveDirs repoRoot))]
    (mt dirsRes
      ((ok dMap)
       (let [(gitdir (option-or (map-get dMap "gitdir") ""))
             (headPath (str gitdir "/HEAD"))
             (readRes (wasi/wasiFileRead headPath))]
         (mt readRes
           ((ok text)
            (let [(trimmed (string-trim text))]
              (if (string-empty? trimmed)
                  (err "ERR_CORRUPT_GIT_HEAD")
                  (ok trimmed))))
           ((err _) (err "ERR_GIT_HEAD_NOT_FOUND")))))
      ((err e) (err e)))))

(df gitCurrentBranch [(repoRoot Str)] -> (Result Str Str)
  :d "Resolves active branch name from .git/HEAD."
  (let [(headRes (gitReadHead repoRoot))]
    (mt headRes
      ((ok headText)
       (cond
         ((string-starts-with? headText "ref: refs/heads/")
          (ok (string-trim (option-or (string-slice headText 16 (string-length headText)) ""))))
         ((string-starts-with? headText "ref: ")
          (ok (string-trim (option-or (string-slice headText 5 (string-length headText)) ""))))
         ((= (string-length headText) 40)
          (ok "HEAD (detached)"))
         (:else (err "ERR_UNRECOGNIZED_HEAD_FORMAT"))))
      ((err e) (err e)))))

(df gitParsePackedRefs [(content Str)] -> (Map Str Str)
  :d "Parses Git packed-refs format mapping ref names to 40-character commit SHAs."
  (let [(lines (string-split content "\n"))]
    (fold (fn [(acc (Map Str Str)) (line Str)]
            (let [(trimmed (string-trim line))]
              (if (or (string-empty? trimmed)
                      (or (string-starts-with? trimmed "#")
                          (string-starts-with? trimmed "^")))
                  acc
                  (let [(spaceIdx (option-or (string-index-of trimmed " ") -1))]
                    (if (>= spaceIdx 0)
                        (let [(sha (string-trim (option-or (string-slice trimmed 0 spaceIdx) "")))
                              (refName (string-trim (option-or (string-slice trimmed (+ spaceIdx 1) (string-length trimmed)) "")))]
                          (map-set acc refName sha))
                        acc)))))
          (map-empty)
          lines)))

(df gitResolveRefCommit [(gitdir Str) (commondir Str) (refRel Str)] -> (Result Str Str)
  :d "Resolves commit SHA for a relative ref checking loose refs then packed-refs in gitdir and commondir."
  (let [(loosePath1 (str gitdir "/" refRel))
        (lRes1 (wasi/wasiFileRead loosePath1))]
    (mt lRes1
      ((ok t1)
       (let [(sha1 (string-trim t1))]
         (if (= (string-length sha1) 40)
             (ok sha1)
             (err "ERR_INVALID_COMMIT_SHA"))))
      ((err _)
       (let [(loosePath2 (str commondir "/" refRel))
             (lRes2 (wasi/wasiFileRead loosePath2))]
         (mt lRes2
           ((ok t2)
            (let [(sha2 (string-trim t2))]
              (if (= (string-length sha2) 40)
                  (ok sha2)
                  (err "ERR_INVALID_COMMIT_SHA"))))
           ((err _)
            (let [(packedPath1 (str gitdir "/packed-refs"))
                  (pRes1 (wasi/wasiFileRead packedPath1))]
              (mt pRes1
                ((ok pt1)
                 (let [(pMap1 (gitParsePackedRefs pt1))]
                   (if (map-has? pMap1 refRel)
                       (let [(sha (option-or (map-get pMap1 refRel) ""))]
                         (if (= (string-length sha) 40)
                             (ok sha)
                             (err "ERR_INVALID_COMMIT_SHA")))
                       (err "ERR_REF_COMMIT_NOT_FOUND"))))
                ((err _)
                 (let [(packedPath2 (str commondir "/packed-refs"))
                       (pRes2 (wasi/wasiFileRead packedPath2))]
                   (mt pRes2
                     ((ok pt2)
                      (let [(pMap2 (gitParsePackedRefs pt2))]
                        (if (map-has? pMap2 refRel)
                            (let [(sha (option-or (map-get pMap2 refRel) ""))]
                              (if (= (string-length sha) 40)
                                  (ok sha)
                                  (err "ERR_INVALID_COMMIT_SHA")))
                            (err "ERR_REF_COMMIT_NOT_FOUND"))))
                     ((err _) (err "ERR_REF_COMMIT_NOT_FOUND"))))))))))))))

(df gitHeadCommit [(repoRoot Str)] -> (Result Str Str)
  :d "Resolves 40-character hexadecimal commit SHA for HEAD."
  (let [(dirsRes (gitResolveDirs repoRoot))]
    (mt dirsRes
      ((ok dMap)
       (let [(gitdir (option-or (map-get dMap "gitdir") ""))
             (commondir (option-or (map-get dMap "commondir") ""))
             (headRes (gitReadHead repoRoot))]
         (mt headRes
           ((ok headText)
            (cond
              ((= (string-length headText) 40)
               (ok headText))
              ((string-starts-with? headText "ref: ")
               (let [(refRel (string-trim (option-or (string-slice headText 5 (string-length headText)) "")))]
                 (gitResolveRefCommit gitdir commondir refRel)))
              (:else
               (err "ERR_UNRECOGNIZED_HEAD_FORMAT"))))
           ((err e) (err e)))))
      ((err e) (err e)))))

(df gitParseConfig [(repoRoot Str)] -> (Map Str Str)
  :d "Parses Git repository configuration format from config files."
  (let [(dirsRes (gitResolveDirs repoRoot))]
    (mt dirsRes
      ((ok dMap)
       (let [(gitdir (option-or (map-get dMap "gitdir") ""))
             (commondir (option-or (map-get dMap "commondir") ""))
             (cfg1 (wasi/wasiFileRead (str gitdir "/config")))
             (cfgText (mt cfg1
                        ((ok t1) t1)
                        ((err _)
                         (let [(cfg2 (wasi/wasiFileRead (str commondir "/config")))]
                           (mt cfg2
                             ((ok t2) t2)
                             ((err _) ""))))))]
         (if (string-empty? cfgText)
             (map-empty)
             (let [(lines (string-split cfgText "\n"))]
               (fold (fn [(acc (Map Str Str)) (line Str)]
                       (let [(trimmed (string-trim line))]
                         (if (or (string-empty? trimmed)
                                 (or (string-starts-with? trimmed "[")
                                     (string-starts-with? trimmed "#")))
                             acc
                             (let [(eqIdx (option-or (string-index-of trimmed "=") -1))]
                               (if (>= eqIdx 0)
                                   (let [(k (string-trim (option-or (string-slice trimmed 0 eqIdx) "")))
                                         (v (string-trim (option-or (string-slice trimmed (+ eqIdx 1) (string-length trimmed)) "")))]
                                     (map-set acc k v))
                                   acc)))))
                     (map-empty)
                     lines)))))
      ((err _) (map-empty)))))

(df gitInspectRepoStatus [(repoRoot Str)] -> (Map Str Str)
  :d "Inspects Git repository status returning branch, commit SHA, and clean status."
  (let [(branchRes (gitCurrentBranch repoRoot))
        (branch (mt branchRes ((ok b) b) ((err _) "unknown")))
        (commitRes (gitHeadCommit repoRoot))
        (commit (mt commitRes ((ok c) c) ((err _) "unknown")))
        (cfg (gitParseConfig repoRoot))
        (fmtVer (option-or (map-get cfg "repositoryformatversion") "0"))]
    (map-set
      (map-set
        (map-set
          (map-set (map-empty) "branch" branch)
          "commit" commit)
        "formatVersion" fmtVer)
      "status" "clean")))

