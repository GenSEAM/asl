(module aslPack/ffiTest
  :d "Unit tests for native FFI library resolution across platform descriptors."
  :x [runTests]
  :i [(ffiLinker :a ffi)
      (platform :a plat)])

(df testDynamicLibResolution [] -> Bool
  :d "Verifies dynamic library naming and flags across macOS, Linux, and Windows."
  (let [(spec (ffi/NativeLibrarySpec
                :name "sqlite3"
                :libType (ffi/libDynamic)
                :pkgConfigName "sqlite3"
                :headerInclude "<sqlite3.h>"))
        (pMac (plat/makePlatform (plat/osMacos) (plat/archArm64)))
        (pLin (plat/makePlatform (plat/osLinux) (plat/archX64)))
        (pWin (plat/makePlatform (plat/osWindows) (plat/archX64)))
        (resMac (ffi/resolveLibraryTarget spec pMac))
        (resLin (ffi/resolveLibraryTarget spec pLin))
        (resWin (ffi/resolveLibraryTarget spec pWin))]
    (assert (= (.-sharedLibName resMac) "libsqlite3.dylib") "macOS dynamic lib name must match")
    (assert (= (.-sharedLibName resLin) "libsqlite3.so") "Linux dynamic lib name must match")
    (assert (= (.-sharedLibName resWin) "sqlite3.dll") "Windows dynamic lib name must match")
    (assert (= (option-or (list-head (.-libFlags resWin)) "") "sqlite3.lib") "Windows lib flags must match")
    true))

(df testAppleFrameworkResolution [] -> Bool
  :d "Verifies macOS framework linker flag generation."
  (let [(spec (ffi/NativeLibrarySpec
                :name "CoreAudio"
                :libType (ffi/libFramework)
                :pkgConfigName ""
                :headerInclude "<CoreAudio/CoreAudio.h>"))
        (pMac (plat/makePlatform (plat/osMacos) (plat/archArm64)))
        (resMac (ffi/resolveLibraryTarget spec pMac))
        (flags (.-libFlags resMac))]
    (assert (= (option-or (list-head flags) "") "-framework") "First flag must be -framework")
    (assert (= (option-or (list-head (option-or (list-tail flags) (list))) "") "CoreAudio") "Second flag must be framework name")
    true))

(df testFfiFunctions [] -> Bool
  :d "Verifies make-kernel-call and format-shared-lib-name functions."
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64)))
        (kCall (ffi/makeKernelCall "execve" "posix"))]
    (assert (= (.-symbol kCall) "execve") "Kernel call symbol")
    (assert (= (ffi/formatSharedLibName "test" pMac) "libtest.dylib") "Shared lib name")
    true))

(df runTests [] -> Bool
  :d "Executes native FFI resolution test suites."
  (do
    (assert (testDynamicLibResolution) "test-dynamic-lib-resolution must pass")
    (assert (testAppleFrameworkResolution) "test-apple-framework-resolution must pass")
    (assert (testFfiFunctions) "test-ffi-functions must pass")
    true))
