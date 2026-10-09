(module asl-gates/shebangAudit :x [ShebangVerdict isBinaryBlob isValidPackageFile isApprovedForwarder isApprovedDocOrConfigFile auditShebang auditScriptFile] :i [])

(schema ShebangVerdict (:f path Str) (:f valid Bool) (:f isBinary Bool) (:f reason Str))

fn isBinaryBlob header: Str -> Bool
  (cond
    ((stringContains? header "\u0000") true)
    (else
      (let [(b (stringToBytes header)) (n (bytesLength b))]
        (cond
          ((< n 2) false)
          ((and (= (bytesGet b 0) 77) (= (bytesGet b 1) 90)) true)
          ((< n 4) false)
          (else
            (let [(b0 (bytesGet b 0)) (b1 (bytesGet b 1)) (b2 (bytesGet b 2)) (b3 (bytesGet b 3))]
              (or (and (= b0 127) (= b1 69) (= b2 76) (= b3 70))
                  (and (= b0 207) (= b1 250) (= b2 237) (= b3 254))
                  (and (= b0 254) (= b1 237) (= b2 250) (= b3 207))
                  (and (= b0 206) (= b1 250) (= b2 237) (= b3 254))
                  (and (= b0 254) (= b1 237) (= b2 250) (= b3 206))
                  (and (= b0 202) (= b1 254) (= b2 186) (= b3 190))
                  (and (= b0 190) (= b1 186) (= b2 254) (= b3 202))
                  (and (= b0 202) (= b1 254) (= b2 186) (= b3 191))
                  (and (= b0 191) (= b1 186) (= b2 254) (= b3 202)))))))))

fn isValidPackageFile ext: Str -> Bool
  (or (= ext ".asl") (or (= ext ".asn") (= ext ".md")))

fn isApprovedDocOrConfigFile ext: Str -> Bool
  (listContains? (list ".md" ".json" ".yaml" ".yml" ".toml" ".txt" ".asn" ".asl" ".lock" ".gitignore" ".gitattributes" ".editorconfig") ext)

fn isApprovedForwarder name: Str approved: (List Str) -> Bool
  (listContains? approved name)

fn auditShebang header: Str -> Bool
  (if (stringStartsWith? header "#!") (or (stringContains? header "asl") (or (stringContains? header "bash") (stringContains? header "/bin/sh"))) false)

fn auditScriptFile path: Str header: Str isPkgTree: Bool ext: Str approvedBins: (List Str) -> ShebangVerdict
  (if (isBinaryBlob header) (ShebangVerdict :path path :valid false :isBinary true :reason "Binary blob rejected") (if isPkgTree (if (isValidPackageFile ext) (if (and (stringStartsWith? header "#!") (not (auditShebang header))) (ShebangVerdict :path path :valid false :isBinary false :reason "Illegal package script content") (ShebangVerdict :path path :valid true :isBinary false :reason "Valid package file extension")) (ShebangVerdict :path path :valid false :isBinary false :reason "Illegal package extension")) (if (isApprovedDocOrConfigFile ext) (ShebangVerdict :path path :valid true :isBinary false :reason "Approved configuration or document file") (if (auditShebang header) (ShebangVerdict :path path :valid true :isBinary false :reason "Approved script shebang") (if (isApprovedForwarder path approvedBins) (ShebangVerdict :path path :valid true :isBinary false :reason "Approved forwarder binary") (ShebangVerdict :path path :valid false :isBinary false :reason "Unapproved script or binary"))))))
