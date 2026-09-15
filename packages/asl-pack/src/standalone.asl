(module aslPack/standalone
  :d "Standalone single-binary executable packager: footer layout, payload mapping, and platform signing."
  :x [StandaloneBundleConfig
      BundleManifest
      magicFooter
      footerSizeBytes
      requiresCodesign?
      formatFooterManifest
      formatCodesignCommand
      planStandaloneBundle]
  :i [(platform :a plat)
      (asl-codec/asn :a asn)])

(df magicFooter [] -> Str
  :d "Canonical 8-byte magic footer identifying an ASL packed executable payload."
  "ASLPACK!")

(df footerSizeBytes [] -> I64
  :d "Fixed footer footprint in bytes: 8 bytes payload length + 8 bytes magic."
  16)

(dfs StandaloneBundleConfig
  (:f runnerStubPath Str "Path to precompiled native runtime runner stub")
  (:f wasmPayloadPath Str "Path to compiled WebAssembly bytecode module")
  (:f manifestHeader Str "Embedded ASN metadata manifest")
  (:f outputBinaryPath Str "Destination path for standalone executable")
  (:f platform plat/PlatformDescriptor "Target OS and architecture descriptor"))

(dfs BundleManifest
  (:f entryName Str "Application entry point identifier")
  (:f payloadSize I64 "Size of attached bytecode payload in bytes")
  (:f footerMagic Str "Integrity verification magic string")
  (:f requiresCodesign Bool "Flag indicating whether post-bundle ad-hoc signing is required"))

(df requiresCodesign? [(p plat/PlatformDescriptor)] -> Bool
  :d "Returns true on macOS where mutating Mach-O requires ad-hoc code-signing."
  (plat/isMacos? p))

(df formatFooterManifest [(payloadSize I64) (magic Str)] -> Str
  :d "Formats metadata descriptor for payload footer."
  (let [(_entry (asn/AsnEntry (asn/asnKw ":payloadSize") (asn/asnInt (string-from-int64 payloadSize)) false))]
    (str "pack-foot:{" (string-from-int64 payloadSize) "|" magic "}")))

(df formatCodesignCommand [(targetPath Str)] -> Str
  :d "Emits ad-hoc codesigning invocation satisfying macOS AMFI."
  (str "codesign -s - --force \"" targetPath "\""))

(df planStandaloneBundle [(cfg StandaloneBundleConfig) (payloadLen I64)] -> BundleManifest
  :d "Evaluates bundle configuration and computes packaging requirements."
  (let [(p (.-platform cfg))
        (needsSign (requiresCodesign? p))]
    (BundleManifest
      :entryName (.-outputBinaryPath cfg)
      :payloadSize payloadLen
      :footerMagic (magicFooter)
      :requiresCodesign needsSign)))
