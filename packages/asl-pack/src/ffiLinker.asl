(module aslPack/ffiLinker
  :d "Native foreign function interface (FFI) and platform library resolution across macOS, Linux, and Windows."
  :x [LibraryType
      NativeLibrarySpec
      ResolvedLinkerFlags
      KernelSyscall
      makeKernelCall
      formatSharedLibName
      resolveLibraryTarget]
  :i [(platform :a plat)])

(dfs KernelSyscall
  (:f symbol Str "Target kernel function symbol e.g. execve or fd_write")
  (:f abiKind Str "Calling convention e.g. posix, wasi, or win32")
  (:f directToken Str "Canonical single-token representation: :k"))

(df makeKernelCall [(symbol Str) (abi Str)] -> KernelSyscall
  :d "Instantiates single-token kernel syscall specification (:k)."
  (KernelSyscall
    :symbol symbol
    :abiKind abi
    :directToken ":k"))


(dfe LibraryType
  (:c libDynamic [] "Dynamically linked shared object (.dylib, .so, .dll)")
  (:c libStatic [] "Statically linked object archive (.a, .lib)")
  (:c libFramework [] "Apple macOS/iOS system framework"))

(dfs NativeLibrarySpec
  (:f name Str "Base canonical library name without prefixes or extensions")
  (:f libType LibraryType "Linkage kind")
  (:f pkgConfigName Str "Package config lookup token")
  (:f headerInclude Str "C header include statement e.g. <sqlite3.h>"))

(dfs ResolvedLinkerFlags
  (:f libFlags (List Str) "Compiler/linker arguments e.g. -lsqlite3")
  (:f includeFlags (List Str) "Header search path flags")
  (:f sharedLibName Str "Physical runtime shared library file name"))

(df formatSharedLibName [(name Str) (plat plat/PlatformDescriptor)] -> Str
  :d "Calculates the exact runtime library file name according to OS naming conventions."
  (if (plat/isWindows? plat)
    (str name ".dll")
    (if (plat/isMacos? plat)
      (str "lib" name ".dylib")
      (str "lib" name ".so"))))

(df resolveLibraryTarget [(spec NativeLibrarySpec) (plat plat/PlatformDescriptor)] -> ResolvedLinkerFlags
  :d "Translates abstract library specification into platform-specific linker flags."
  (let [(shName (formatSharedLibName (.-name spec) plat))
        (flags (mt (.-libType spec)
                 ((libFramework)
                  (if (plat/isMacos? plat)
                    (list "-framework" (.-name spec))
                    (list (str "-l" (.-name spec)))))
                 ((libStatic)
                  (if (plat/isWindows? plat)
                    (list (str (.-name spec) ".lib"))
                    (list (str "lib" (.-name spec) ".a"))))
                 ((libDynamic)
                  (if (plat/isWindows? plat)
                    (list (str (.-name spec) ".lib"))
                    (list (str "-l" (.-name spec)))))))]
    (ResolvedLinkerFlags
      :libFlags flags
      :includeFlags (list (str "-I/usr/include/" (.-name spec)))
      :sharedLibName shName)))
