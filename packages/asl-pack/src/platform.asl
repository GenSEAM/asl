(module aslPack/platform
  :d "Cross-platform operating system, architecture, and executable target descriptor registry."
  :x [TargetOs
      TargetArch
      PlatformDescriptor
      makePlatform
      targetTriple
      formatBinaryName
      isWindows?
      isMacos?
      isLinux?]
  :i [])

(dfe TargetOs
  (:c osMacos [] "Apple Darwin / macOS")
  (:c osLinux [] "Linux (GNU / musl)")
  (:c osWindows [] "Microsoft Windows"))

(dfe TargetArch
  (:c archArm64 [] "ARM64 / AArch64 (Apple Silicon, AWS Graviton)")
  (:c archX64 [] "x86_64 / AMD64"))

(dfs PlatformDescriptor
  (:f os TargetOs "Target operating system family")
  (:f arch TargetArch "Target CPU instruction set architecture")
  (:f triple Str "Standard LLVM target triple")
  (:f executableExtension Str "Executable file suffix")
  (:f sharedLibExtension Str "Dynamic shared library suffix"))

(df targetTriple [(os TargetOs) (arch TargetArch)] -> Str
  :d "Computes standard LLVM target triple for OS and architecture pair."
  (mt os
    ((osMacos)
     (mt arch
       ((archArm64) "aarch64-apple-darwin")
       ((archX64) "x86_64-apple-darwin")))
    ((osLinux)
     (mt arch
       ((archArm64) "aarch64-unknown-linux-gnu")
       ((archX64) "x86_64-unknown-linux-gnu")))
    ((osWindows)
     (mt arch
       ((archArm64) "aarch64-pc-windows-msvc")
       ((archX64) "x86_64-pc-windows-msvc")))))

(df makePlatform [(os TargetOs) (arch TargetArch)] -> PlatformDescriptor
  :d "Constructs platform specification record with canonical file extensions."
  (let [(triple (targetTriple os arch))
        (exeExt (mt os
                   ((osWindows) ".exe")
                   ((osMacos) "")
                   ((osLinux) "")))
        (libExt (mt os
                   ((osMacos) ".dylib")
                   ((osLinux) ".so")
                   ((osWindows) ".dll")))]
    (PlatformDescriptor
      :os os
      :arch arch
      :triple triple
      :executableExtension exeExt
      :sharedLibExtension libExt)))

(df formatBinaryName [(pkgName Str) (plat PlatformDescriptor)] -> Str
  :d "Formats artifact executable filename with platform suffix and extension."
  (str pkgName "-" (.-triple plat) (.-executableExtension plat)))

(df isWindows? [(plat PlatformDescriptor)] -> Bool
  :d "Returns true if platform target is Microsoft Windows."
  (mt (.-os plat)
    ((osWindows) true)
    ((osMacos) false)
    ((osLinux) false)))

(df isMacos? [(plat PlatformDescriptor)] -> Bool
  :d "Returns true if platform target is Apple macOS."
  (mt (.-os plat)
    ((osMacos) true)
    ((osWindows) false)
    ((osLinux) false)))

(df isLinux? [(plat PlatformDescriptor)] -> Bool
  :d "Returns true if platform target is Linux."
  (mt (.-os plat)
    ((osLinux) true)
    ((osMacos) false)
    ((osWindows) false)))
