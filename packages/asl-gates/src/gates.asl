(module asl-gates/gates
  :d "Pure AgentScript verification gate runners and continuous audit engine."
  :x [verifySourceSyntax
      verifyFileSemantic
      verifyForeignExt
      verifyBalance
      verifyManifestString
      verifyManifests
      collectDirectoryFiles
      findForeignFilesInPaths
      auditPackageTreeZeroForeign
      runSuite
      main]
  :i [(ast :a a)
      (compiler :a comp)
      (types :a ty)
      (check :a chk)
      (manifestGate :a mg)
      (shebangAudit :a sa)])

(df verifySourceSyntax [(src Str)] -> Bool
  :d "Verifies that source parses cleanly into well-formed AST under pure ASL parser."
  (mt (a/parse src)
    ((ok _) true)
    ((err _) false)))

(df verifyBalance [(src Str)] -> Bool
  :d "Audits S-expression delimiter balance and sigil prohibition."
  (let [(chars (string-chars src))
        (finalState (fold (fn [(st (List I64)) (ch Str)] -> (List I64)
                            (let [(depth (option-or (list-get st 0) 0))
                                  (inStr (option-or (list-get st 1) 0))
                                  (sigil (option-or (list-get st 2) 0))
                                  (escaped (option-or (list-get st 3) 0))]
                              (if (= inStr 1)
                                  (if (= escaped 1)
                                      (list depth 1 sigil 0)
                                      (if (= ch "\\")
                                          (list depth 1 sigil 1)
                                          (if (= ch "\"")
                                              (list depth 0 sigil 0)
                                              (list depth 1 sigil 0))))
                                  (if (= ch "\"")
                                      (list depth 1 sigil 0)
                                      (if (= ch "@")
                                          (list depth 0 1 0)
                                          (if (or (= ch "(") (or (= ch "[") (= ch "{")))
                                              (list (+ depth 1) 0 sigil 0)
                                              (if (or (= ch ")") (or (= ch "]") (= ch "}")))
                                                  (list (- depth 1) 0 sigil 0)
                                                  (list depth 0 sigil 0))))))))
                          (list 0 0 0 0)
                          chars))
        (finalDepth (option-or (list-get finalState 0) 1))
        (finalInStr (option-or (list-get finalState 1) 1))
        (finalSigil (option-or (list-get finalState 2) 1))]
    (and (= finalDepth 0)
         (and (= finalInStr 0)
              (= finalSigil 0)))))

(df verifyManifestString [(content Str)] -> Bool
  :d "Verifies that manifest content string has a valid package id without sigils."
  (let [(pkg (mg/parsePackageId content))]
    (and (> (string-length pkg) 2)
         (mg/isValidPkgName? pkg))))

(df ! verifyManifests [(manifestPaths (List Str))] -> Bool
  :d "Verifies package manifest structure across packages."
  (fold (fn ! [(acc Bool) (path Str)] -> Bool
          (and acc
               (mt (file-read path)
                 ((err _) false)
                 ((ok content)
                  (verifyManifestString content)))))
        true
        manifestPaths))

(df ! verifyFileSemantic [(path Str)] -> (Result Unit Str)
  :d "Verifies that an AgentScript file passes pure ASL semantic and type checks."
  (mt (file-read path)
    ((err _) (err (str "Failed to read file: " path)))
    ((ok src)
     (mt (a/parse src)
       ((err pe)
        (err (str path ":" (string-from-int64 (.-line pe)) ":" (string-from-int64 (.-col pe)) ": " (.-msg pe))))
       ((ok forms)
        (let [(diags (chk/checkModule forms (map-empty) path))]
          (if (list-empty? diags)
              (ok ())
              (err (str path ": " (string-from-int64 (list-length diags)) " semantic error(s)")))))))))

(df verifyForeignExt [(ext Str)] -> Bool
  :d "Returns true if file extension complies with pure ASL zero-foreign policy."
  (or (= ext ".asl")
      (= ext ".asn")))

(df ! collectDirectoryFiles [(dir Str)] -> (List Str)
  :d "Walks a directory tree recursively and returns all relative file paths, excluding .git, node_modules, and dist."
  (let [(cmd (str "find " dir " -type f ! -path '*/.*' ! -path '*/node_modules/*' ! -path '*/dist/*'"))
        (res (sys-exec cmd))]
    (if (= (.-exitCode res) 0)
        (let [(out (.-stdout res))
              (rawLines (string-split out "\n"))]
          (filter (fn [(p Str)] -> Bool (not (string-empty? p))) rawLines))
        (list))))

(df findForeignFilesInPaths [(paths (List Str))] -> (List Str)
  :d "Filters a collection of file paths against forbidden foreign extensions, returning all offending paths."
  (filter (fn [(p Str)] -> Bool
            (or (string-ends-with? p ".py")
                (or (string-ends-with? p ".js")
                    (or (string-ends-with? p ".ts")
                        (or (string-ends-with? p ".rs")
                            (or (string-ends-with? p ".c")
                                (or (string-ends-with? p ".cpp")
                                    (string-ends-with? p ".sh"))))))))
          paths))

(df ! auditPackageTreeZeroForeign [(roots (List Str))] -> (Result I64 (List Str))
  :d "Audits all files in package roots ensuring zero foreign extensions and zero binary blobs."
  (let [(effectiveRoots (if (list-empty? roots) (list "asl/packages") roots))
        (allFiles (fold (fn ! [(acc (List Str)) (r Str)] -> (List Str)
                          (list-concat acc (collectDirectoryFiles r)))
                        (list)
                        effectiveRoots))
        (violations (filter (fn ! [(p Str)] -> Bool
                              (if (not (or (string-ends-with? p ".asl")
                                           (or (string-ends-with? p ".asn")
                                               (string-ends-with? p ".md"))))
                                  true
                                  (mt (file-read p)
                                    ((ok c) (sa/isBinaryBlob c))
                                    ((err _) false))))
                            allFiles))]
    (if (list-empty? violations)
        (ok (list-length allFiles))
        (err violations))))

(df ! runSuite [(paths (List Str))] -> (Result I64 Str)
  :d "Executes semantic verification gate across a collection of ASL source paths."
  (fold (fn ! [(acc (Result I64 Str)) (p Str)] -> (Result I64 Str)
          (mt acc
            ((err e) (err e))
            ((ok count)
             (mt (verifyFileSemantic p)
               ((ok _) (ok (+ count 1)))
               ((err msg) (err msg))))))
        (ok 0)
        paths))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Entrypoint for pure AgentScript gate verification binary."
  (if (list-empty? args)
      (let [(u1 (println "AgentScript Gate Runner: 0 files specified. Verification clean."))]
        (ok ()))
      (mt (runSuite args)
        ((ok count)
         (let [(u2 (println (str "=== [Pure ASL Gate] ALL " (string-from-int64 count) " FILE(S) VERIFIED CLEANLY ===")))]
           (ok ())))
        ((err msg)
         (let [(u3 (eprintln (str "=== [Pure ASL Gate] FAILED: " msg " ===")))]
           (err (other)))))))
