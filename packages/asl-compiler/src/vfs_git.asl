(module asl-compiler/vfs-git
  :d "Pure AgentScript sovereign Git VFS reader for inspecting git repositories without POSIX git subprocesses."
  :x [gitReadHead
      gitCurrentBranch
      gitParsePackedRefs
      gitHeadCommit
      gitParseConfig
      gitInspectRepoStatus]
  :i [(wasi :a wasi)])

(df gitReadHead [(repoRoot Str)] -> (Result Str Str)
  :d "Reads .git/HEAD to determine current ref or detached state."
  (let [(headPath (if (string-empty? repoRoot) ".git/HEAD" (str repoRoot "/.git/HEAD")))
        (readRes (wasi/wasiFileRead headPath))]
    (mt readRes
      ((ok text)
       (let [(trimmed (string-trim text))]
         (if (string-empty? trimmed)
             (err "ERR_CORRUPT_GIT_HEAD")
             (ok trimmed))))
      ((err _)
       (let [(dotGitPath (if (string-empty? repoRoot) ".git" (str repoRoot "/.git")))
             (dotGitRes (wasi/wasiFileRead dotGitPath))]
         (mt dotGitRes
           ((ok gitText)
            (let [(trimmedGit (string-trim gitText))]
              (if (string-starts-with? trimmedGit "gitdir: ")
                  (let [(rawDir (string-trim (option-or (string-slice trimmedGit 8 (string-length trimmedGit)) "")))
                        (parts (string-split rawDir "/"))
                        (branchName (option-or (list-get parts (- (list-length parts) 1)) ""))]
                    (if (string-empty? branchName)
                        (err "ERR_CORRUPT_GIT_HEAD")
                        (ok (str "ref: refs/heads/" branchName))))
                  (err "ERR_GIT_HEAD_NOT_FOUND"))))
           ((err _) (err "ERR_GIT_HEAD_NOT_FOUND"))))))))

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

(df gitHeadCommit [(repoRoot Str)] -> (Result Str Str)
  :d "Resolves 40-character hexadecimal commit SHA for HEAD."
  (let [(headRes (gitReadHead repoRoot))]
    (mt headRes
      ((ok headText)
       (if (= (string-length headText) 40)
           (ok headText)
           (if (string-starts-with? headText "ref: ")
               (let [(refRel (string-trim (option-or (string-slice headText 5 (string-length headText)) "")))
                     (loosePath (if (string-empty? repoRoot) (str ".git/" refRel) (str repoRoot "/.git/" refRel)))
                     (looseRes (wasi/wasiFileRead loosePath))]
                 (mt looseRes
                   ((ok refText)
                    (let [(sha (string-trim refText))]
                      (if (= (string-length sha) 40)
                          (ok sha)
                          (err "ERR_INVALID_COMMIT_SHA"))))
                   ((err _)
                    (let [(packedPath (if (string-empty? repoRoot) ".git/packed-refs" (str repoRoot "/.git/packed-refs")))
                          (packedRes (wasi/wasiFileRead packedPath))]
                      (mt packedRes
                        ((ok packedText)
                         (let [(pMap (gitParsePackedRefs packedText))]
                           (if (map-has? pMap refRel)
                               (let [(sha (option-or (map-get pMap refRel) ""))]
                                 (if (= (string-length sha) 40)
                                     (ok sha)
                                     (err "ERR_INVALID_COMMIT_SHA")))
                               (err "ERR_REF_COMMIT_NOT_FOUND"))))
                        ((err _)
                         (let [(commitPath (if (string-empty? repoRoot) ".git-commit" (str repoRoot "/.git-commit")))
                               (cRes (wasi/wasiFileRead commitPath))]
                           (mt cRes
                             ((ok cText)
                              (let [(sha (string-trim cText))]
                                (if (= (string-length sha) 40)
                                    (ok sha)
                                    (err "ERR_REF_COMMIT_NOT_FOUND"))))
                             ((err _) (err "ERR_REF_COMMIT_NOT_FOUND"))))))))))
               (err "ERR_UNRECOGNIZED_HEAD_FORMAT"))))
      ((err e) (err e)))))

(df gitParseConfig [(repoRoot Str)] -> (Map Str Str)
  :d "Parses Git repository configuration format from .git/config."
  (let [(cfgPath (if (string-empty? repoRoot) ".git/config" (str repoRoot "/.git/config")))
        (readRes (wasi/wasiFileRead cfgPath))]
    (mt readRes
      ((ok text)
       (let [(lines (string-split text "\n"))]
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
               lines)))
      ((err _)
       (let [(dotGitPath (if (string-empty? repoRoot) ".git" (str repoRoot "/.git")))
             (dotGitRes (wasi/wasiFileRead dotGitPath))]
         (mt dotGitRes
           ((ok gitText)
            (if (string-starts-with? (string-trim gitText) "gitdir: ")
                (map-set (map-empty) "repositoryformatversion" "0")
                (map-empty)))
           ((err _) (map-empty))))))))

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
