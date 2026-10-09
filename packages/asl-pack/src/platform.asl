(module aslPack/platform :x [TargetOs TargetArch PlatformDescriptor makePlatform targetTriple formatBinaryName isWindows? isMacos? isLinux?] :i [])

(enum TargetOs (:c osMacos [] "Apple Darwin / macOS") (:c osLinux [] "Linux (GNU / musl)") (:c osWindows [] "Microsoft Windows"))

(enum TargetArch (:c archArm64 [] "ARM64 / AArch64 (Apple Silicon, AWS Graviton)") (:c archX64 [] "x86_64 / AMD64"))

(schema PlatformDescriptor (:f os TargetOs) (:f arch TargetArch) (:f triple Str) (:f executableExtension Str) (:f sharedLibExtension Str))

fn targetTriple os: TargetOs arch: TargetArch -> Str
  (mt os ((osMacos) (mt arch ((archArm64) "aarch64-apple-darwin") ((archX64) "x86_64-apple-darwin"))) ((osLinux) (mt arch ((archArm64) "aarch64-unknown-linux-gnu") ((archX64) "x86_64-unknown-linux-gnu"))) ((osWindows) (mt arch ((archArm64) "aarch64-pc-windows-msvc") ((archX64) "x86_64-pc-windows-msvc"))))

fn makePlatform os: TargetOs arch: TargetArch -> PlatformDescriptor
  (let [(triple (targetTriple os arch)) (exeExt (mt os ((osWindows) ".exe") ((osMacos) "") ((osLinux) ""))) (libExt (mt os ((osMacos) ".dylib") ((osLinux) ".so") ((osWindows) ".dll")))] (PlatformDescriptor :os os :arch arch :triple triple :executableExtension exeExt :sharedLibExtension libExt))

fn formatBinaryName pkgName: Str plat: PlatformDescriptor -> Str
  (str pkgName "-" plat.triple plat.executableExtension)

fn isWindows? plat: PlatformDescriptor -> Bool
  (mt plat.os ((osWindows) true) ((osMacos) false) ((osLinux) false))

fn isMacos? plat: PlatformDescriptor -> Bool
  (mt plat.os ((osMacos) true) ((osWindows) false) ((osLinux) false))

fn isLinux? plat: PlatformDescriptor -> Bool
  (mt plat.os ((osLinux) true) ((osMacos) false) ((osWindows) false))
