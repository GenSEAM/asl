(module aslPack/platformTest :x [runTests] :i [(platform :a p)])

fn testIsLinux -> Bool
  (let [(mac (p/makePlatform (p/osMacos) (p/archArm64))) (lin (p/makePlatform (p/osLinux) (p/archX64))) (win (p/makePlatform (p/osWindows) (p/archArm64)))] (assert (== (p/isLinux? mac) false) "mac is not linux") (assert (== (p/isLinux? win) false) "win is not linux") (assert (== (p/isLinux? lin) true) "lin is linux") (assert (== (p/isMacos? mac) true) "mac is macos") (assert (== (p/isWindows? win) true) "win is windows") true)

fn runTests -> Bool
  (do (assert (testIsLinux) "test-is-linux must pass") true)
