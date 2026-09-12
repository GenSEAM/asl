(module asl-gates/shebang-audit
  :d "Pure AgentScript shebang inspector and extensionless binary blob validator under Gate 4."
  :x [ShebangVerdict
      is-binary-blob
      is-valid-package-file
      is-approved-forwarder
      audit-shebang
      audit-script-file]
  :i [(gates :a g)])

(dfs ShebangVerdict
  (:f path Str "Inspected file path")
  (:f valid Bool "True if complies with pure ASL execution rules")
  (:f is-binary Bool "True if header contains binary executable magic")
  (:f reason Str "Audit rationale or failure mode"))

(df is-binary-blob [(header Str)] -> Bool
  :d "Detects Mach-O, ELF, or PE executable binary headers."
  (or (string-starts-with? header "\u007fELF")
      (or (string-starts-with? header "MZ")
          (or (string-starts-with? header "\ufeff")
              (or (string-starts-with? header "\u0000")
                  (string-starts-with? header "\ucffa"))))))

(df is-valid-package-file [(ext Str)] -> Bool
  :d "Verifies that file in package tree strictly has .asl, .asn, or .md extension."
  (or (= ext ".asl")
      (or (= ext ".asn")
          (= ext ".md"))))

(df is-approved-forwarder [(name Str) (approved (List Str))] -> Bool
  :d "Verifies whether an extensionless executable is registered in the bin manifest."
  (list-contains? approved name))

(df audit-shebang [(header Str)] -> Bool
  :d "Audits shebang interpreter line, ensuring it targets asl, bash, or sh."
  (if (string-starts-with? header "#!")
      (or (string-contains? header "asl")
          (or (string-contains? header "bash")
              (string-contains? header "/bin/sh")))
      false))

(df audit-script-file [(path Str) (header Str) (is-pkg-tree Bool) (ext Str) (approved-bins (List Str))] -> ShebangVerdict
  :d "Audits a file against Gate 4 zero-foreign and extensionless binary rules."
  (if (is-binary-blob header)
      (ShebangVerdict :path path :valid false :is-binary true :reason "Binary blob rejected")
      (if is-pkg-tree
          (if (is-valid-package-file ext)
              (if (and (string-starts-with? header "#!") (not (audit-shebang header)))
                  (ShebangVerdict :path path :valid false :is-binary false :reason "Illegal package script content")
                  (ShebangVerdict :path path :valid true :is-binary false :reason "Valid package file extension"))
              (ShebangVerdict :path path :valid false :is-binary false :reason "Illegal package extension"))
          (if (audit-shebang header)
              (ShebangVerdict :path path :valid true :is-binary false :reason "Approved script shebang")
              (if (is-approved-forwarder path approved-bins)
                  (ShebangVerdict :path path :valid true :is-binary false :reason "Approved forwarder binary")
                  (ShebangVerdict :path path :valid false :is-binary false :reason "Unapproved script or binary"))))))
