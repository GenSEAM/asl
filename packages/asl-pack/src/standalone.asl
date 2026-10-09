(module aslPack/standalone :x [StandaloneBundleConfig BundleManifest magicFooter footerSizeBytes requiresCodesign? formatFooterManifest formatCodesignCommand planStandaloneBundle] :i [(platform :a plat) (asl-transpile/asn :a asn)])

fn magicFooter -> Str
  "ASLPACK!"

fn footerSizeBytes -> I64
  16

(schema StandaloneBundleConfig (:f runnerStubPath Str) (:f wasmPayloadPath Str) (:f manifestHeader Str) (:f outputBinaryPath Str) (:f platform plat/PlatformDescriptor))

(schema BundleManifest (:f entryName Str) (:f payloadSize I64) (:f footerMagic Str) (:f requiresCodesign Bool))

fn requiresCodesign? p: plat/PlatformDescriptor -> Bool
  (plat/isMacos? p)

fn formatFooterManifest payloadSize: I64 magic: Str -> Str
  (let [(_entry (asn/AsnEntry :key (asn/asnKw ":payloadSize") :val (asn/asnInt (stringFromInt64 payloadSize)) :paren false))] (str "pack-foot:{" (stringFromInt64 payloadSize) "|" magic "}"))

fn formatCodesignCommand targetPath: Str -> Str
  (str "codesign -s - --force \"" targetPath "\"")

fn planStandaloneBundle cfg: StandaloneBundleConfig payloadLen: I64 -> BundleManifest
  (let [(p cfg.platform) (needsSign (requiresCodesign? p))] (BundleManifest :entryName cfg.outputBinaryPath :payloadSize payloadLen :footerMagic (magicFooter) :requiresCodesign needsSign))
