(module asl-text/tests/modularAliasesTest :x [runTests testTxtStarts testTxtEnds testTxtHas testTxtSplit testVNorm testVResolve testVReadWrite] :i [(string :a txt) (aslMem/vfs :a v)])

fn testTxtStarts -> Bool
  (let [(s1 "alpha/bravo") (p1 "alpha") (p2 "bravo")] (assert (txt/starts? s1 p1) "txt/starts? must return true for valid prefix") (refute (txt/starts? s1 p2) "txt/starts? must return false for invalid prefix") (assert (txt/txtStarts? s1 p1) "txtStarts? compatibility alias must return true") (refute (txt/txtStarts? s1 p2) "txtStarts? compatibility alias must return false") true)

fn testTxtEnds -> Bool
  (let [(s1 "alpha/bravo.asl") (sfx1 ".asl") (sfx2 ".asn")] (assert (txt/ends? s1 sfx1) "txt/ends? must return true for valid suffix") (refute (txt/ends? s1 sfx2) "txt/ends? must return false for invalid suffix") (assert (txt/txtEnds? s1 sfx1) "txtEnds? compatibility alias must return true") (refute (txt/txtEnds? s1 sfx2) "txtEnds? compatibility alias must return false") true)

fn testTxtHas -> Bool
  (let [(s1 "token-density-rational-compaction") (sub1 "rational") (sub2 "extraneous")] (assert (txt/has? s1 sub1) "txt/has? must return true when substring is present") (refute (txt/has? s1 sub2) "txt/has? must return false when substring is absent") (assert (txt/txtHas? s1 sub1) "txtHas? compatibility alias must return true") (refute (txt/txtHas? s1 sub2) "txtHas? compatibility alias must return false") true)

fn testTxtSplit -> Bool
  (let [(parts (txt/split "a:b:c" ":")) (cparts (txt/txtSplit "x/y" "/"))] (assert (= (listLength parts) 3) "txt/split must split string into 3 segments") (assert (= (listLength cparts) 2) "txtSplit compatibility alias must split string into 2 segments") (assert (= (optionOr (listGet parts 0) "") "a") "First segment must match") (assert (= (optionOr (listGet parts 2) "") "c") "Last segment must match") true)

fn testVNorm -> Bool
  (let [(p1 (v/norm "./src/vfs.asl")) (p2 (v/norm "/src/vfs.asl")) (p3 (v/norm "src/vfs.asl"))] (assert (= p1 "src/vfs.asl") "v/norm must strip leading dot-slash") (assert (= p2 "src/vfs.asl") "v/norm must strip leading slash") (assert (= p3 "src/vfs.asl") "v/norm must preserve clean relative path") true)

fn testVResolve -> Bool
  (let [(r1 (v/resolve "root" "child.asl")) (r2 (v/resolve "/base" "./nested/file.asl")) (r3 (v/resolve "" "direct.asl"))] (assert (= r1 "root/child.asl") "v/resolve must join base and child") (assert (= r2 "base/nested/file.asl") "v/resolve must normalize both paths before joining") (assert (= r3 "direct.asl") "v/resolve with empty base must return normalized path") true)

fn testVReadWrite -> Bool
  (let [(reg0 (v/vfsInit)) (reg1 (v/write reg0 "pkg/test.asl" "(module test :x [])")) (optBuf (v/read reg1 "pkg/test.asl")) (missingBuf (v/read reg1 "pkg/missing.asl"))] (assert (some? optBuf) "v/read must find staged buffer") (assert (none? missingBuf) "v/read must return none for unstaged path") (let [(buf (optionOr optBuf (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))] (assert (= buf.content "(module test :x [])") "Buffer content must match written payload") (assert (= buf.path "pkg/test.asl") "Buffer path must match normalized path")) true)

fn runTests -> Bool
  (and (testTxtStarts) (and (testTxtEnds) (and (testTxtHas) (and (testTxtSplit) (and (testVNorm) (and (testVResolve) (testVReadWrite)))))))
