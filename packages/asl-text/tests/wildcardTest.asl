(module asl-text/tests/wildcardTest :x [runTests] :i [(asl-text/wildcard :a wc)])

fn testGlob -> Bool
  (do (assert (wc/globMatch "*" "hello") "* matches anything")
      (assert (wc/globMatch "h*o" "hello") "h*o matches hello")
      (assert (wc/globMatch "?" "a") "? matches single char")
      (assert (not (wc/globMatch "?" "ab")) "? does not match two chars")
      (assert (wc/globMatch "[abc]" "b") "class matches member")
      (assert (not (wc/globMatch "[abc]" "d")) "class rejects non-member")
      (assert (wc/globMatch "[a-z]" "m") "range matches in range")
      (assert (not (wc/globMatch "[a-z]" "M")) "range rejects out of range")
      (assert (wc/globMatch "*.txt" "file.txt") "suffix glob")
      (assert (not (wc/globMatch "*.txt" "file.rs")) "suffix glob reject")
      true)

fn testPath -> Bool
  (do (assert (wc/pathMatch "*" "hello") "path * matches no slash")
      (assert (not (wc/pathMatch "*" "a/b")) "path * stops at slash")
      (assert (wc/pathMatch "**" "a/b/c") "path ** crosses slashes")
      (assert (wc/pathMatch "src/*.asl" "src/main.asl") "path single star in segment")
      (assert (not (wc/pathMatch "src/*.asl" "src/sub/main.asl")) "path star does not cross into subdir")
      (assert (wc/pathMatch "src/**/*.asl" "src/a/b/c.asl") "path globstar matches deep")
      (assert (wc/pathMatch "?" "a") "path ? matches single")
      (assert (not (wc/pathMatch "?" "/")) "path ? does not match slash")
      true)

fn runTests -> Bool
  (and (testGlob) (testPath))
