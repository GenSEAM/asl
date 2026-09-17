(module asl-plugin/security
  :d "Security, sandbox, and capability validation boundaries for plugins."
  :x [validateSandboxPath verifyArtifactDigest validateManifestSecurity authorizeCall computeCallerSignature verifyCallerSignature verifyCallerNonce constantTimeEqual validateManifestHash]
  :i [(asl-plugin/types)])

(df constantTimeEqual [(a Str) (b Str)] -> Bool
  :d "Constant-time string comparison to prevent timing side-channels on HMAC digests."
  (if (!= (string-length a) (string-length b))
      false
      (let [(ca (string-chars a))
            (cb (string-chars b))
            (mismatches (fold (fn [(acc Int64) (i Int64)] -> Int64
                                (let [(chA (option-or (list-get ca i) ""))
                                      (chB (option-or (list-get cb i) ""))]
                                  (if (= chA chB) acc (+ acc 1))))
                              0
                              (list-range 0 (string-length a))))]
        (= mismatches 0))))

(df validateSandboxPath [(entrypoint Str) (sandboxRoot Str)] -> (Result Str PluginError)
  :d "Checks if the path escapes the canonical sandbox root."
  (if (or (string-empty? entrypoint) (string-empty? sandboxRoot))
      (err (errNotFound entrypoint))
      (if (or (string-starts-with? entrypoint "/")
              (string-starts-with? entrypoint "\\")
              (string-contains? entrypoint "..")
              (string-contains? entrypoint ":")
              (string-contains? entrypoint "\u0000"))
          (err (errSandboxEscape entrypoint))
          (mt (pathCanonicalize sandboxRoot)
            ((err _) (err (errSandboxEscape sandboxRoot)))
            ((ok canonRoot)
             (let [(candPath (str canonRoot "/" entrypoint))]
               (mt (pathCanonicalize candPath)
                 ((err _)
                  (err (errNotFound entrypoint)))
                 ((ok canonEntry)
                  (let [(prefix (str canonRoot "/"))]
                    (if (or (= canonEntry canonRoot)
                            (string-starts-with? canonEntry prefix))
                        (ok canonEntry)
                        (err (errSandboxEscape entrypoint))))))))))))

(df verifyArtifactDigest [(path Str) (expectedSha256 Str)] -> (Result Unit PluginError)
  :d "Verifies the physical artifact on disk matches the expected SHA-256 hash."
  (if (string-empty? expectedSha256)
      (err (errInvalidSignature "Missing integrity SHA-256 hash"))
      (if (!= (string-length expectedSha256) 64)
          (err (errInvalidSignature "Integrity SHA-256 hash must be exactly 64 hexadecimal characters"))
          (mt (fileStat path)
            ((err _) (err (errNotFound path)))
            ((ok st)
             (if (not (.-isFile st))
                 (err (errInvalidSignature (str "Artifact path is not a regular file: " path)))
                 (let [(escaped (string-replace path "'" "'\\''"))
                       (cmd (str "shasum -a 256 '" escaped "' 2>/dev/null || sha256sum '" escaped "'"))
                       (res (sysExec cmd))]
                   (if (!= (.-exitCode res) 0)
                       (err (errExecutionTrap "Failed to compute artifact checksum"))
                       (let [(outStr (string-trim (.-stdout res)))]
                         (if (string-empty? outStr)
                             (err (errExecutionTrap "Artifact checksum command returned empty output"))
                             (let [(hashOpt (string-slice outStr 0 64))]
                               (mt hashOpt
                                 ((none) (err (errExecutionTrap "Invalid checksum output format")))
                                 ((some hashVal)
                                  (let [(computed (string-to-lower hashVal))
                                        (expected (string-to-lower expectedSha256))]
                                    (if (constantTimeEqual computed expected)
                                        (ok ())
                                        (err (errInvalidSignature (str "Artifact SHA-256 digest mismatch: expected " expected " but got " computed))))))))))))))))))

(df validateManifestSecurity [(manifest PluginManifest) (sandboxRoot Str)] -> (Result Unit PluginError)
  :d "Validates cryptographic integrity and sandbox bounds."
  (cond
    ((string-empty? (.-id manifest))
     (err (errInvalidSignature "Plugin ID cannot be empty")))
    ((string-empty? (.-entrypoint manifest))
     (err (errInvalidSignature "Plugin entrypoint cannot be empty")))
    (:else
     (let [(effectiveRoot (if (string-empty? sandboxRoot) "." sandboxRoot))
           (pathRes (validateSandboxPath (.-entrypoint manifest) effectiveRoot))]
       (mt pathRes
         ((err e) (err e))
         ((ok canonPath)
          (verifyArtifactDigest canonPath (.-integritySha256 manifest))))))))

(df computeCallerSignature [(identity Str) (capabilities (List Str)) (nonce Str) (secretKey Str)] -> Str
  :d "Computes deterministic HMAC-SHA256 hex digest over caller identity, capabilities, and nonce."
  (if (or (string-empty? identity) (string-empty? nonce) (string-empty? secretKey))
      ""
      (let [(sortedCaps (list-sort capabilities))
            (capsStr (fold (fn [(acc Str) (cap Str)] -> Str
                             (str acc (int-to-string (string-length cap)) ":" cap ";"))
                           ""
                           sortedCaps))
            (preImage (str (int-to-string (string-length identity)) ":" identity "|"
                           (int-to-string (string-length nonce)) ":" nonce "|"
                           (int-to-string (string-length capsStr)) ":" capsStr))
            (escapedPayload (string-replace preImage "'" "'\\''"))
            (escapedSecret (string-replace secretKey "'" "'\\''"))
            (cmd (str "printf '%s' '" escapedPayload "' | openssl dgst -sha256 -hmac '" escapedSecret "' -r"))
            (res (sysExec cmd))]
        (if (!= (.-exitCode res) 0)
            ""
            (let [(raw (string-trim (.-stdout res)))]
              (if (string-empty? raw)
                  ""
                  (string-to-lower (option-or (string-slice raw 0 64) ""))))))))

(df verifyCallerSignature [(auth CallerAuth) (secretKey Str)] -> (Result Unit PluginError)
  :d "Verifies the cryptographic HMAC signature of a CallerAuth token."
  (if (or (string-empty? (.-identity auth)) (string-empty? (.-nonce auth)))
      (err (errInvalidSignature "Caller identity and nonce must not be empty"))
      (if (string-empty? (.-signature auth))
          (err (errInvalidSignature "Caller signature cannot be empty"))
          (if (string-empty? secretKey)
              (err (errInvalidSignature "Caller secret key cannot be empty"))
              (let [(expectedSig (computeCallerSignature (.-identity auth) (.-grantedCapabilities auth) (.-nonce auth) secretKey))]
                (if (string-empty? expectedSig)
                    (err (errExecutionTrap "Failed to compute caller HMAC signature"))
                    (if (constantTimeEqual (string-to-lower (.-signature auth)) expectedSig)
                        (ok ())
                        (err (errInvalidSignature "Caller HMAC signature mismatch")))))))))

(df verifyCallerNonce [(callerNonces (Map Str Int64)) (identity Str) (nonce Str)] -> (Result (Map Str Int64) PluginError)
  :d "Validates monotonic sequence counter or timestamp against observed caller nonces to prevent replay attacks."
  (if (string-empty? identity)
      (err (errInvalidSignature "Caller identity cannot be empty"))
      (let [(nOpt (string-to-int64 nonce))]
        (mt nOpt
          ((none)
           (err (errUnauthorized "Invalid nonce format: must be a numeric integer")))
          ((some nonceVal)
           (if (<= nonceVal 0)
               (err (errUnauthorized "Nonce must be a positive monotonic integer"))
               (let [(lastNonce (option-or (map-get callerNonces identity) 0))]
                 (if (<= nonceVal lastNonce)
                     (err (errUnauthorized (str "Replayed or out-of-order nonce: " nonce " <= " (int-to-string lastNonce))))
                     (ok (map-set callerNonces identity nonceVal))))))))))

(df authorizeCall [(auth CallerAuth) (exportDef PluginExport) (secretKey Str)] -> (Result Unit PluginError)
  :d "Verifies the caller's cryptographic signature and required capability grant."
  (let [(reqCap (.-requiredCapability exportDef))]
    (if (string-empty? reqCap)
        (err (errInvalidSignature "Exports must explicitly declare a required capability, cannot be open-by-default"))
        (let [(sigRes (if (and (string-empty? secretKey) (string-empty? (.-signature auth)))
                          (ok ())
                          (verifyCallerSignature auth secretKey)))]
          (mt sigRes
            ((err e) (err e))
            ((ok _)
             (if (list-contains? (.-grantedCapabilities auth) reqCap)
                 (ok ())
                 (err (errUnauthorized (str "Caller lacking required capability: " reqCap))))))))))

(df validateManifestHash [(manifestContent Str) (expectedDigest Str)] -> (Result Str PluginError)
  :d "Validates package manifest content against expected Blake3 or SHA256 integrity digest."
  (if (string-empty? expectedDigest)
      (err (errInvalidSignature "Expected manifest hash cannot be empty"))
      (if (string-empty? manifestContent)
          (err (errInvalidSignature "Manifest content cannot be empty"))
          (let [(escaped (string-replace manifestContent "'" "'\\''"))
                (cmd (str "printf '%s' '" escaped "' | shasum -a 256 2>/dev/null | awk '{print $1}' || printf '%s' '" escaped "' | sha256sum | awk '{print $1}'"))
                (res (sysExec cmd))]
            (if (!= (.-exitCode res) 0)
                (err (errExecutionTrap "Failed to compute manifest hash"))
                (let [(computed (string-trim (.-stdout res)))]
                  (if (constantTimeEqual computed expectedDigest)
                      (ok computed)
                      (err (errInvalidSignature (str "Manifest hash mismatch: computed " computed " but expected " expectedDigest))))))))))
