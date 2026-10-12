(module asl/packages/asl-plugin/tests/argvTest :x [testArtifactPathIsOneArg! runTests main] :i [(asl-plugin/security :a sec) (asl-proc/coreProcess :a proc)])

fn checkLine name: Str ok: Bool -> Str
  (str "check " name " " (if ok "1" "0"))

fn childPassed out: Str name: Str -> Bool
  (listContains? (stringLines out) (checkLine name true))

fn ! testArtifactPathIsOneArg! -> (List Str)
  (let [(path "tmp/plugin argv ' $(touch PWNED) ; touch PWNED2")
        (expectedArtifact "c7c5c1d70c5dec4416ab6158afd0b223ef40c29b1dc1f97ed9428b94d4cadb1c")
        (expectedManifest "7c1a97613c1cbd350913c1ee00cea3c5250a275e60258d846d12c83f7a835aca")
        (created (fileWrite path "artifact"))
        (verified (sec/verifyArtifactDigest! path expectedArtifact))
        (manifestHash (sec/validateManifestHash! "manifest-data" expectedManifest))
        (signature (sec/computeCallerSignature! "worker" (list "cap-db") "1000" "test-secret"))
        (otherSignature (sec/computeCallerSignature! "worker" (list "cap-db") "1000" "other-secret"))
        (logged (fileRead (optionOr (envGet "ASL_PLUGIN_ARGV_LOG") "")))
        (cleanup (proc/exec! (proc/cmd "rm" (list "-f" path))))]
    (list (checkLine "created" (ok? created))
          (checkLine "verified" (ok? verified))
          (checkLine "manifestHash" (= manifestHash (ok expectedManifest)))
          (checkLine "signatureLength" (= (stringLength signature) 64))
          (checkLine "otherSignatureLength" (= (stringLength otherSignature) 64))
          (checkLine "keyedSignature" (!= signature otherSignature))
          (checkLine "hmacArgv" (mt logged ((ok text) (and (stringContains? text "-hmac") (stringContains? text "test-secret"))) ((err _) false)))
          (checkLine "noPwned" (not (fileExists? "PWNED")))
          (checkLine "noPwned2" (not (fileExists? "PWNED2")))))

fn shellParent? line: Str -> Bool
  (listContains? (list "sh" "bash" "dash" "zsh" "-sh" "-bash") (optionOr (listGet (stringSplit line " ") 1) ""))

fn toolLines text: Str tool: Str -> (List Str)
  (filter (fn [(l Str)] -> Bool (stringStartsWith? l (str tool " "))) (stringSplit text "\n"))

fn ! runTests -> Bool
      (let [(parentTmp (dirCreate "tmp"))
            (stubDir (str "/tmp/plugin-argv-" (stringFromInt64 (monotonicNs))))
            (record (str stubDir "/argv-log"))
            (parents (str stubDir "/parent-log"))
            (made (dirCreate stubDir))
            (tools (list (pair "openssl" "#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"$ASL_PLUGIN_ARGV_LOG\"\nprintf '%s %s\\n' openssl \"$(basename \"$(ps -o comm= -p $PPID)\")\" >> \"$ASL_PLUGIN_PARENT_LOG\"\nPATH=\"$ASL_PLUGIN_REAL_PATH\" exec openssl \"$@\"\n")
                         (pair "shasum" "#!/bin/sh\nprintf '%s %s\\n' shasum \"$(basename \"$(ps -o comm= -p $PPID)\")\" >> \"$ASL_PLUGIN_PARENT_LOG\"\nPATH=\"$ASL_PLUGIN_REAL_PATH\" exec shasum \"$@\"\n")
                         (pair "sha256sum" "#!/bin/sh\nprintf '%s %s\\n' sha256sum \"$(basename \"$(ps -o comm= -p $PPID)\")\" >> \"$ASL_PLUGIN_PARENT_LOG\"\nPATH=\"$ASL_PLUGIN_REAL_PATH\" exec sha256sum \"$@\"\n")))
            (written (map (fn [(t (Pair Str Str))] -> Bool
                            (let [(at (str stubDir "/" (pairFirst t)))]
                              (and (ok? (fileWrite at (pairSecond t))) (ok? (fileChmod at 493)))))
                          tools))
            (realPath (optionOr (envGet "PATH") "/usr/bin:/bin"))
            (childCmd (proc/withEnv (proc/withEnv (proc/withEnv (proc/withEnv (proc/withEnv (proc/withTimeout (proc/cmd "bin/asl" (list "run" "asl/packages/asl-plugin/tests/argvTest.asl")) 30000) "PATH" (str stubDir ":" realPath)) "ASL_PLUGIN_ARGV_LOG" record) "ASL_PLUGIN_ARGV_CHILD" "1") "ASL_PLUGIN_PARENT_LOG" parents) "ASL_PLUGIN_REAL_PATH" realPath))
            (child (proc/exec! childCmd))
            (childOut (mt child ((ok out) out.stdout) ((err _) "")))
            (logged (fileRead record))
            (parentText (resultOr (fileRead parents) ""))
            (digestLines (listAppend (toolLines parentText "shasum") (toolLines parentText "sha256sum")))
            (hmacLines (toolLines parentText "openssl"))
            (shelled (filter shellParent? (listAppend digestLines hmacLines)))
            (cleanup (proc/exec! (proc/cmd "rm" (list "-rf" stubDir))))]
        (do
          (assert (ok? parentTmp) "Could not create tmp directory for plugin argv fixture")
          (assert (ok? made) "Could not create PATH stub directory")
          (assert (listAll? (fn [(w Bool)] -> Bool w) written) "Could not write the openssl, shasum and sha256sum PATH wrappers")
          (assert (mt child ((ok out) (do (println out.stdout) (= out.exitCode 0))) ((err _) false)) "Child plugin argv test failed")
          (assert (childPassed childOut "created") "Adversarial artifact fixture must be written")
          (assert (childPassed childOut "verified") "Real checksum command must accept the artifact digest")
          (assert (childPassed childOut "manifestHash") "Manifest hash must cover the supplied stdin bytes")
          (assert (childPassed childOut "signatureLength") "HMAC command must return a 64-character SHA-256 digest")
          (assert (childPassed childOut "otherSignatureLength") "HMAC with a second key must return a 64-character digest")
          (assert (childPassed childOut "keyedSignature") "Caller signature must depend on the secret key")
          (assert (childPassed childOut "hmacArgv") "OpenSSL must receive the configured HMAC key as an argv value")
          (assert (childPassed childOut "noPwned") "Command substitution payload must not create PWNED")
          (assert (childPassed childOut "noPwned2") "Command separator payload must not create PWNED2")
          (assert (mt logged ((ok text) (stringContains? text "-hmac\ntest-secret")) ((err _) false)) "OpenSSL must receive the secret through direct argv without a shell")
          (assert (and (>= (listLength digestLines) 2) (>= (listLength hmacLines) 2)) (str "the artifact and manifest digests and both HMACs reached the wrapped tools: " parentText))
          (assert (listEmpty? shelled) (str "checksum and HMAC tools are spawned directly, never by a shell: " (stringJoin shelled "; ")))
          true))

fn ! main args: (List Str) -> (Result Int64 Str)
  (do
    (println (stringJoin (testArtifactPathIsOneArg!) "\n"))
    (ok 0))
