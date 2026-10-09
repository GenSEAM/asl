(module aslPack/ffiTest :x [runTests] :i [(ffiLinker :a ffi) (platform :a plat)])

fn testDynamicLibResolution -> Bool
  (let [(spec (ffi/NativeLibrarySpec :name "sqlite3" :libType (ffi/libDynamic) :pkgConfigName "sqlite3" :headerInclude "<sqlite3.h>")) (pMac (plat/makePlatform (plat/osMacos) (plat/archArm64))) (pLin (plat/makePlatform (plat/osLinux) (plat/archX64))) (pWin (plat/makePlatform (plat/osWindows) (plat/archX64))) (resMac (ffi/resolveLibraryTarget spec pMac)) (resLin (ffi/resolveLibraryTarget spec pLin)) (resWin (ffi/resolveLibraryTarget spec pWin))] (assert (= resMac.sharedLibName "libsqlite3.dylib") "macOS dynamic lib name must match") (assert (= resLin.sharedLibName "libsqlite3.so") "Linux dynamic lib name must match") (assert (= resWin.sharedLibName "sqlite3.dll") "Windows dynamic lib name must match") (assert (= (optionOr (listHead resWin.libFlags) "") "sqlite3.lib") "Windows lib flags must match") true)

fn testAppleFrameworkResolution -> Bool
  (let [(spec (ffi/NativeLibrarySpec :name "CoreAudio" :libType (ffi/libFramework) :pkgConfigName "" :headerInclude "<CoreAudio/CoreAudio.h>")) (pMac (plat/makePlatform (plat/osMacos) (plat/archArm64))) (resMac (ffi/resolveLibraryTarget spec pMac)) (flags resMac.libFlags)] (assert (= (optionOr (listHead flags) "") "-framework") "First flag must be -framework") (assert (= (optionOr (listHead (optionOr (listTail flags) (list))) "") "CoreAudio") "Second flag must be framework name") true)

fn testFfiFunctions -> Bool
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64))) (kCall (ffi/makeKernelCall "execve" "posix"))] (assert (= kCall.symbol "execve") "Kernel call symbol") (assert (= (ffi/formatSharedLibName "test" pMac) "libtest.dylib") "Shared lib name") true)

fn runTests -> Bool
  (do (assert (testDynamicLibResolution) "test-dynamic-lib-resolution must pass") (assert (testAppleFrameworkResolution) "test-apple-framework-resolution must pass") (assert (testFfiFunctions) "test-ffi-functions must pass") true)
