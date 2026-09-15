(module asl-gates/shebangAudit
  :d "Pure AgentScript shebang inspector and extensionless binary blob validator under Gate 4."
  :x [ShebangVerdict
      isBinaryBlob
      isValidPackageFile
      isApprovedForwarder
      isApprovedDocOrConfigFile
      auditShebang
      auditScriptFile]
  :i [])

(dfs ShebangVerdict
  (:f path Str "Inspected file path")
  (:f valid Bool "True if complies with pure ASL execution rules")
  (:f isBinary Bool "True if header contains binary executable magic")
  (:f reason Str "Audit rationale or failure mode"))

(df isBinaryBlob [(header Str)] -> Bool
  :d "Detects Mach-O, ELF, or PE executable binary headers."
  (or (string-starts-with? header "\u007fELF")
      (or (string-starts-with? header "MZ")
          (or (string-starts-with? header "\ufeff")
              (or (string-starts-with? header "\u0000")
                  (or (string-starts-with? header "\ucffa")
                      (string-starts-with? header "\ucafe")))))))

(df isValidPackageFile [(ext Str)] -> Bool
  :d "Verifies that file in package tree strictly has .asl, .asn, or .md extension."
  (or (= ext ".asl")
      (or (= ext ".asn")
          (= ext ".md"))))

(df isApprovedDocOrConfigFile [(ext Str)] -> Bool
  :d "Verifies whether a file extension represents an approved non-executable configuration or documentation format."
  (list-contains? (list ".md"
                        ".json"
                        ".yaml"
                        ".yml"
                        ".toml"
                        ".txt"
                        ".asn"
                        ".asl"
                        ".lock"
                        ".gitignore"
                        ".gitattributes"
                        ".editorconfig")
                  ext))

(df isApprovedForwarder [(name Str) (approved (List Str))] -> Bool
  :d "Verifies whether an extensionless executable is registered in the bin manifest."
  (list-contains? approved name))

(df auditShebang [(header Str)] -> Bool
  :d "Audits shebang interpreter line, ensuring it targets asl, bash, or sh."
  (if (string-starts-with? header "#!")
      (or (string-contains? header "asl")
          (or (string-contains? header "bash")
              (string-contains? header "/bin/sh")))
      false))

(df auditScriptFile [(path Str) (header Str) (isPkgTree Bool) (ext Str) (approvedBins (List Str))] -> ShebangVerdict
  :d "Audits a file against Gate 4 zero-foreign and extensionless binary rules."
  (if (isBinaryBlob header)
      (ShebangVerdict :path path :valid false :isBinary true :reason "Binary blob rejected")
      (if isPkgTree
          (if (isValidPackageFile ext)
              (if (and (string-starts-with? header "#!") (not (auditShebang header)))
                  (ShebangVerdict :path path :valid false :isBinary false :reason "Illegal package script content")
                  (ShebangVerdict :path path :valid true :isBinary false :reason "Valid package file extension"))
              (ShebangVerdict :path path :valid false :isBinary false :reason "Illegal package extension"))
          (if (isApprovedDocOrConfigFile ext)
              (ShebangVerdict :path path :valid true :isBinary false :reason "Approved configuration or document file")
              (if (auditShebang header)
                  (ShebangVerdict :path path :valid true :isBinary false :reason "Approved script shebang")
                  (if (isApprovedForwarder path approvedBins)
                      (ShebangVerdict :path path :valid true :isBinary false :reason "Approved forwarder binary")
                      (ShebangVerdict :path path :valid false :isBinary false :reason "Unapproved script or binary")))))))
