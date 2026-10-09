(module aslPack/ffiLinker :x [LibraryType NativeLibrarySpec ResolvedLinkerFlags KernelSyscall makeKernelCall formatSharedLibName resolveLibraryTarget] :i [(platform :a plat)])

(schema KernelSyscall (:f symbol Str) (:f abiKind Str) (:f directToken Str))

fn makeKernelCall symbol: Str abi: Str -> KernelSyscall
  (KernelSyscall :symbol symbol :abiKind abi :directToken ":k")

(enum LibraryType (:c libDynamic [] "Dynamically linked shared object (.dylib, .so, .dll)") (:c libStatic [] "Statically linked object archive (.a, .lib)") (:c libFramework [] "Apple macOS/iOS system framework"))

(schema NativeLibrarySpec (:f name Str) (:f libType LibraryType) (:f pkgConfigName Str) (:f headerInclude Str))

(schema ResolvedLinkerFlags (:f libFlags (List Str)) (:f includeFlags (List Str)) (:f sharedLibName Str))

fn formatSharedLibName name: Str plat: plat/PlatformDescriptor -> Str
  (if (plat/isWindows? plat) (str name ".dll") (if (plat/isMacos? plat) (str "lib" name ".dylib") (str "lib" name ".so")))

fn resolveLibraryTarget spec: NativeLibrarySpec plat: plat/PlatformDescriptor -> ResolvedLinkerFlags
  (let [(shName (formatSharedLibName spec.name plat)) (flags (mt spec.libType ((libFramework) (if (plat/isMacos? plat) (list "-framework" spec.name) (list (str "-l" spec.name)))) ((libStatic) (if (plat/isWindows? plat) (list (str spec.name ".lib")) (list (str "lib" spec.name ".a")))) ((libDynamic) (if (plat/isWindows? plat) (list (str spec.name ".lib")) (list (str "-l" spec.name))))))] (ResolvedLinkerFlags :libFlags flags :includeFlags (list (str "-I/usr/include/" spec.name)) :sharedLibName shName))
