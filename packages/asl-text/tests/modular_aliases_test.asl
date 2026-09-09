(module asl-text/tests/modular-aliases-test
  :d "Unit verification suite for 1-to-2 token modular aliases in asl-text and mem/vfs per d46 and d47."
  :x [run-tests
      test-txt-starts
      test-txt-ends
      test-txt-has
      test-txt-split
      test-v-norm
      test-v-resolve
      test-v-read-write]
  :i [(string :a txt)
      (asl-mem/vfs :a v)])

(df test-txt-starts [] -> Bool
  :d "Verifies txt/starts? positive and negative cases."
  (let [(s1 "alpha/bravo")
        (p1 "alpha")
        (p2 "bravo")]
    (assert (txt/starts? s1 p1) "txt/starts? must return true for valid prefix")
    (assert (not (txt/starts? s1 p2)) "txt/starts? must return false for invalid prefix")
    (assert (txt-starts? s1 p1) "txt-starts? compatibility alias must return true")
    (assert (not (txt-starts? s1 p2)) "txt-starts? compatibility alias must return false")
    true))

(df test-txt-ends [] -> Bool
  :d "Verifies txt/ends? positive and negative cases."
  (let [(s1 "alpha/bravo.asl")
        (sfx1 ".asl")
        (sfx2 ".asn")]
    (assert (txt/ends? s1 sfx1) "txt/ends? must return true for valid suffix")
    (assert (not (txt/ends? s1 sfx2)) "txt/ends? must return false for invalid suffix")
    (assert (txt-ends? s1 sfx1) "txt-ends? compatibility alias must return true")
    (assert (not (txt-ends? s1 sfx2)) "txt-ends? compatibility alias must return false")
    true))

(df test-txt-has [] -> Bool
  :d "Verifies txt/has? positive and negative cases."
  (let [(s1 "token-density-rational-compaction")
        (sub1 "rational")
        (sub2 "extraneous")]
    (assert (txt/has? s1 sub1) "txt/has? must return true when substring is present")
    (assert (not (txt/has? s1 sub2)) "txt/has? must return false when substring is absent")
    (assert (txt-has? s1 sub1) "txt-has? compatibility alias must return true")
    (assert (not (txt-has? s1 sub2)) "txt-has? compatibility alias must return false")
    true))

(df test-txt-split [] -> Bool
  :d "Verifies txt/split single and multi delimiter cases."
  (let [(parts (txt/split "a:b:c" ":"))
        (cparts (txt-split "x/y" "/"))]
    (assert (= (list-length parts) 3) "txt/split must split string into 3 segments")
    (assert (= (list-length cparts) 2) "txt-split compatibility alias must split string into 2 segments")
    (assert (= (option-or (list-get parts 0) "") "a") "First segment must match")
    (assert (= (option-or (list-get parts 2) "") "c") "Last segment must match")
    true))

(df test-v-norm [] -> Bool
  :d "Verifies v/norm stripping dot-slash and leading slash."
  (let [(p1 (v/norm "./src/vfs.asl"))
        (p2 (v/norm "/src/vfs.asl"))
        (p3 (v/norm "src/vfs.asl"))]
    (assert (= p1 "src/vfs.asl") "v/norm must strip leading dot-slash")
    (assert (= p2 "src/vfs.asl") "v/norm must strip leading slash")
    (assert (= p3 "src/vfs.asl") "v/norm must preserve clean relative path")
    true))

(df test-v-resolve [] -> Bool
  :d "Verifies v/resolve relative and absolute resolution."
  (let [(r1 (v/resolve "root" "child.asl"))
        (r2 (v/resolve "/base" "./nested/file.asl"))
        (r3 (v/resolve "" "direct.asl"))]
    (assert (= r1 "root/child.asl") "v/resolve must join base and child")
    (assert (= r2 "base/nested/file.asl") "v/resolve must normalize both paths before joining")
    (assert (= r3 "direct.asl") "v/resolve with empty base must return normalized path")
    true))

(df test-v-read-write [] -> Bool
  :d "Verifies v/write and v/read roundtrip staging."
  (let [(reg0 (v/vfs-init))
        (reg1 (v/write reg0 "pkg/test.asl" "(module test :x [])"))
        (opt-buf (v/read reg1 "pkg/test.asl"))
        (missing-buf (v/read reg1 "pkg/missing.asl"))]
    (assert (is-some? opt-buf) "v/read must find staged buffer")
    (assert (is-none? missing-buf) "v/read must return none for unstaged path")
    (let [(buf (option-or opt-buf (v/VFSBuffer :path "" :content "" :base-content "" :cas-hash "" :base-hash "" :revision 0 :dirty false :loaded-at 0)))]
      (assert (= (.-content buf) "(module test :x [])") "Buffer content must match written payload")
      (assert (= (.-path buf) "pkg/test.asl") "Buffer path must match normalized path"))
    true))

(df run-tests [] -> Bool
  :d "Runs all modular alias verification tests."
  (and (test-txt-starts)
       (and (test-txt-ends)
            (and (test-txt-has)
                 (and (test-txt-split)
                      (and (test-v-norm)
                           (and (test-v-resolve)
                                (test-v-read-write))))))))
