(module aslPack/packagingTest
  :x [runTests]
  :i [(packaging :a pkg)])

fn testMacosPackaging -> Bool
  (let [(pSpec (pkg/makePackageSpec "asl" "0.2.0" "macos" "aarch64"))
        (manifest (pkg/emitMacosPackageSpec pSpec))]
    (do
      (assert (= pSpec.packageName "asl") "Package name must be asl")
      (assert (= pSpec.version "0.2.0") "Version must be 0.2.0")
      (assert (= pSpec.os "macos") "OS must be macos")
      (assert (stringContains? manifest ":format \"tar.gz\"") "macOS package must use tar.gz format")
      (assert (stringContains? manifest ":pkgIdentifier \"com.genseam.asl\"") "macOS package must declare bundle ID")
      (assert (stringContains? manifest ":installPath \"/usr/local/bin/asl\"") "macOS install path must be standard")
      (refute (stringContains? manifest ":format \"deb\"") "macOS must refute deb format")
      (refute (stringContains? manifest ":format \"rpm\"") "macOS must refute rpm format")
      true))

fn testDebianPackaging -> Bool
  (let [(pSpec (pkg/makePackageSpec "asl" "0.2.0" "linux" "x86_64"))
        (controlFile (pkg/emitDebianControlFile pSpec))]
    (do
      (assert (stringContains? controlFile "Package: asl") "Control file must declare Package: asl")
      (assert (stringContains? controlFile "Version: 0.2.0") "Control file must declare Version: 0.2.0")
      (assert (stringContains? controlFile "Architecture: amd64") "Control file must map x86_64 to amd64")
      (assert (stringContains? controlFile "Maintainer: GenSEAM Team") "Control file must have Maintainer")
      (assert (stringContains? controlFile "Section: devel") "Control file must declare section devel")
      (refute (stringContains? controlFile "Architecture: aarch64") "x86_64 deb must refute aarch64")
      (refute (stringContains? controlFile "Package: npm") "Debian package must refute foreign package names")
      true))

fn testRpmPackaging -> Bool
  (let [(pSpec (pkg/makePackageSpec "asl" "0.2.0" "linux" "x86_64"))
        (rpmSpec (pkg/emitRpmSpecFile pSpec))]
    (do
      (assert (stringContains? rpmSpec "Name:           asl") "RPM spec must declare Name: asl")
      (assert (stringContains? rpmSpec "Version:        0.2.0") "RPM spec must declare Version: 0.2.0")
      (assert (stringContains? rpmSpec "Release:        1%{?dist}") "RPM spec must declare Release")
      (assert (stringContains? rpmSpec "Summary:        AgentScript Pure AI Agent Language") "RPM spec must declare Summary")
      (assert (stringContains? rpmSpec "%install") "RPM spec must have %install section")
      (assert (stringContains? rpmSpec "%files") "RPM spec must have %files section")
      (refute (stringContains? rpmSpec "Name:           python") "RPM spec must refute foreign names")
      (refute (stringContains? rpmSpec "Architecture: win32") "RPM spec must refute Windows arch")
      true))

fn testWindowsPackaging -> Bool
  (let [(pSpec (pkg/makePackageSpec "asl" "0.2.0" "windows" "x86_64"))
        (winManifest (pkg/emitWindowsPackageManifest pSpec))]
    (do
      (assert (= pSpec.os "windows") "OS must be windows")
      (assert (stringContains? winManifest ":format \"zip\"") "Windows package must format zip")
      (assert (stringContains? winManifest ":executable \"asl.exe\"") "Windows package must have asl.exe")
      (assert (stringContains? winManifest ":installPath \"$LOCALAPPDATA/asl/bin\"") "Windows path must match")
      (refute (stringContains? winManifest ":format \"tar.gz\"") "Windows package must refute tar.gz")
      (refute (stringContains? winManifest ":executable \"asl\"") "Windows package must refute extension-less binary")
      true))

fn testBrowserWasmPackaging -> Bool
  (let [(pSpec (pkg/makePackageSpec "asl" "0.2.0" "browser" "wasm32"))
        (webManifest (pkg/emitBrowserPackageBundle pSpec))]
    (do
      (assert (= pSpec.os "browser") "OS must be browser")
      (assert (= pSpec.arch "wasm32") "Arch must be wasm32")
      (assert (stringContains? webManifest ":target \"wasm32-unknown-unknown\"") "Browser target must be wasm32")
      (assert (stringContains? webManifest ":wasmBinary \"dist/web/asl.wasm\"") "WASM binary destination must match")
      (assert (stringContains? webManifest ":entryHtml \"dist/web/index.html\"") "Browser entry HTML must match")
      (refute (stringContains? webManifest ":format \"deb\"") "Browser package must refute deb")
      (refute (stringContains? webManifest "asl.exe") "Browser package must refute exe")
      true))

fn runTests -> Bool
  (do
    (assert (testMacosPackaging) "testMacosPackaging must pass")
    (assert (testDebianPackaging) "testDebianPackaging must pass")
    (assert (testRpmPackaging) "testRpmPackaging must pass")
    (assert (testWindowsPackaging) "testWindowsPackaging must pass")
    (assert (testBrowserWasmPackaging) "testBrowserWasmPackaging must pass")
    true)
