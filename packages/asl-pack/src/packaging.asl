(module aslPack/packaging
  :x [PackageSpec makePackageSpec emitMacosPackageSpec emitDebianControlFile emitRpmSpecFile emitWindowsPackageManifest emitBrowserPackageBundle emitPackageChecksumManifest]
  :i [])

(schema PackageSpec
  (:f packageName Str)
  (:f version Str)
  (:f os Str)
  (:f arch Str)
  (:f sha256 (Option Str)))

fn makePackageSpec pkg: Str ver: Str targetOs: Str targetArch: Str -> PackageSpec
  (PackageSpec
    :packageName pkg
    :version ver
    :os targetOs
    :arch targetArch
    :sha256 none)

fn emitMacosPackageSpec spec: PackageSpec -> Str
  (str "(:macosPackage\n"
       "  :packageName \"" spec.packageName "\"\n"
       "  :version \"" spec.version "\"\n"
       "  :format \"tar.gz\"\n"
       "  :pkgIdentifier \"com.genseam.asl\"\n"
       "  :installPath \"/usr/local/bin/asl\"\n"
       "  :arch \"" spec.arch "\"\n"
       "  :bundleContents [\"bin/asl\" \"share/man/man1/asl.1\"]\n"
       "  :targetTriple \"" (if (= spec.arch "aarch64") "aarch64-apple-darwin" "x86_64-apple-darwin") "\")\n")

fn emitDebianControlFile spec: PackageSpec -> Str
  (let [(debArch (if (= spec.arch "x86_64") "amd64" (if (= spec.arch "aarch64") "arm64" "all")))]
    (str "Package: " spec.packageName "\n"
         "Version: " spec.version "\n"
         "Section: devel\n"
         "Priority: optional\n"
         "Architecture: " debArch "\n"
         "Maintainer: GenSEAM Team <team@genseam.com>\n"
         "Description: AgentScript Pure AI Agent Language and Runtime\n"
         " AgentScript (ASL) is a homoiconic, zero-remote, self-hosted runtime\n"
         " for resilient autonomous multi-agent engineering.\n"))

fn emitRpmSpecFile spec: PackageSpec -> Str
  (str "Name:           " spec.packageName "\n"
       "Version:        " spec.version "\n"
       "Release:        1%{?dist}\n"
       "Summary:        AgentScript Pure AI Agent Language\n"
       "License:        MIT\n"
       "URL:            https://github.com/GenSEAM/asl\n"
       "\n"
       "%description\n"
       "AgentScript (ASL) self-hosted multi-agent language and high-throughput runtime.\n"
       "\n"
       "%install\n"
       "mkdir -p %{buildroot}/usr/bin\n"
       "install -m 0755 bin/asl %{buildroot}/usr/bin/asl\n"
       "\n"
       "%files\n"
       "/usr/bin/asl\n")

fn emitWindowsPackageManifest spec: PackageSpec -> Str
  (str "(:windowsPackage\n"
       "  :packageName \"" spec.packageName "\"\n"
       "  :version \"" spec.version "\"\n"
       "  :format \"zip\"\n"
       "  :executable \"asl.exe\"\n"
       "  :installPath \"$LOCALAPPDATA/asl/bin\"\n"
       "  :arch \"" spec.arch "\"\n"
       "  :shimWrapper \"asl.cmd\")\n")

fn emitBrowserPackageBundle spec: PackageSpec -> Str
  (str "(:browserPackage\n"
       "  :packageName \"" spec.packageName "\"\n"
       "  :version \"" spec.version "\"\n"
       "  :format \"wasm-bundle\"\n"
       "  :target \"wasm32-unknown-unknown\"\n"
       "  :wasmBinary \"dist/web/asl.wasm\"\n"
       "  :entryHtml \"dist/web/index.html\"\n"
       "  :jsHarness \"dist/web/asl-web.js\")\n")

fn emitPackageChecksumManifest pkg: Str ver: Str archives: (List Str) -> Str
  (str "(:checksumManifest\n"
       "  :package \"" pkg "\"\n"
       "  :version \"" ver "\"\n"
       "  :algorithm \"sha256\"\n"
       "  :files [" (stringJoin archives " ") "])\n")
