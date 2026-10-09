(module asl-regex/regexTest
  :x [runTests]
  :i [(asl-regex/regex :a rx)])

schema TestCase {
  pat: String
  text: String
}

fn get-test-cases -> (List TestCase)
  (list
    (TestCase :pat "hello" :text "hello")
    (TestCase :pat "hello" :text "world hello there")
    (TestCase :pat "a" :text "banana")
    (TestCase :pat "z" :text "banana")
    (TestCase :pat "." :text "a")
    (TestCase :pat "a.c" :text "abc")
    (TestCase :pat "a.c" :text "a\nc")
    (TestCase :pat "a..c" :text "axxc")
    (TestCase :pat "foo" :text "foobar")
    (TestCase :pat "bar" :text "foobar")
    (TestCase :pat "[abc]" :text "c")
    (TestCase :pat "[abc]" :text "x")
    (TestCase :pat "[a-z]" :text "M")
    (TestCase :pat "[a-z]" :text "m")
    (TestCase :pat "[0-9]" :text "5")
    (TestCase :pat "[a-zA-Z0-9]" :text "Z")
    (TestCase :pat "[-abc]" :text "-")
    (TestCase :pat "[abc-]" :text "-")
    (TestCase :pat "[0-9a-fA-F]" :text "e")
    (TestCase :pat "[1-5]" :text "3")
    (TestCase :pat "[^a-z]" :text "5")
    (TestCase :pat "[^a-z]" :text "a")
    (TestCase :pat "[^/]+" :text "foo/bar")
    (TestCase :pat "[^0-9]+" :text "abc123def")
    (TestCase :pat "[^abc]" :text "d")
    (TestCase :pat "[^abc]" :text "a")
    (TestCase :pat "[^-a]" :text "b")
    (TestCase :pat "[^-a]" :text "-")
    (TestCase :pat "[^0-9]" :text "x")
    (TestCase :pat "[^a-zA-Z]" :text "9")
    (TestCase :pat "\\d" :text "abc 123")
    (TestCase :pat "\\d+" :text "12345")
    (TestCase :pat "\\D+" :text "abc123")
    (TestCase :pat "\\w+" :text "hello_world_123")
    (TestCase :pat "\\W+" :text "hello world")
    (TestCase :pat "\\s+" :text "a \t\n b")
    (TestCase :pat "\\S+" :text "  abc  ")
    (TestCase :pat "[\\d_]+" :text "12_34")
    (TestCase :pat "[\\w-]+" :text "foo-bar_1")
    (TestCase :pat "\\d\\w\\s" :text "1a ")
    (TestCase :pat "^abc" :text "abcdef")
    (TestCase :pat "^abc" :text "zabcdef")
    (TestCase :pat "abc$" :text "xyzabc")
    (TestCase :pat "abc$" :text "xyzabcd")
    (TestCase :pat "^abc$" :text "abc")
    (TestCase :pat "^abc$" :text "abcd")
    (TestCase :pat "\\bcat\\b" :text "a cat.")
    (TestCase :pat "\\bcat\\b" :text "a caterpillar")
    (TestCase :pat "\\bcat\\b" :text "cat")
    (TestCase :pat "\\Bcat\\B" :text "scatter")
    (TestCase :pat "\\Bcat" :text "scatter")
    (TestCase :pat "a|b" :text "b")
    (TestCase :pat "cat|dog" :text "dog")
    (TestCase :pat "a|ab" :text "ab")
    (TestCase :pat "ab|a" :text "ab")
    (TestCase :pat "red|green|blue" :text "blue")
    (TestCase :pat "a|" :text "x")
    (TestCase :pat "(abc)" :text "abc")
    (TestCase :pat "(a)(b)(c)" :text "abc")
    (TestCase :pat "((a)b)" :text "ab")
    (TestCase :pat "a(b)?c" :text "ac")
    (TestCase :pat "a(b)?c" :text "abc")
    (TestCase :pat "(a|b)" :text "b")
    (TestCase :pat "(?:abc)" :text "abc")
    (TestCase :pat "(?:a|b)c" :text "bc")
    (TestCase :pat "a(b(c))" :text "abc")
    (TestCase :pat "(a)?(b)?(c)?" :text "b")
    (TestCase :pat "(?:a+)b" :text "aaab")
    (TestCase :pat "((?:ab)+)" :text "ababab")
    (TestCase :pat "(a|b|c)" :text "c")
    (TestCase :pat "a*" :text "aaaa")
    (TestCase :pat "a*" :text "b")
    (TestCase :pat "a*?" :text "aaaa")
    (TestCase :pat "a*?b" :text "aab")
    (TestCase :pat "a*b" :text "aab")
    (TestCase :pat "a+" :text "aaaa")
    (TestCase :pat "a+" :text "b")
    (TestCase :pat "a+?" :text "aaaa")
    (TestCase :pat "a+?b" :text "aab")
    (TestCase :pat "a?" :text "a")
    (TestCase :pat "a?" :text "b")
    (TestCase :pat "a??" :text "a")
    (TestCase :pat "a??b" :text "ab")
    (TestCase :pat "a{3}" :text "aaaa")
    (TestCase :pat "a{3}" :text "aa")
    (TestCase :pat "a{2,}" :text "aaaa")
    (TestCase :pat "a{2,}" :text "a")
    (TestCase :pat "a{2,}?" :text "aaaa")
    (TestCase :pat "a{2,4}" :text "aaaaaa")
    (TestCase :pat "a{2,4}?" :text "aaaaaa")
    (TestCase :pat "\\.\\*\\+\\?" :text ".*+?")
    (TestCase :pat "\\[abc\\]" :text "[abc]")
    (TestCase :pat "\\{2\\}" :text "{2}")
    (TestCase :pat "\\(abc\\)" :text "(abc)")
    (TestCase :pat "a\\|b" :text "a|b")
    (TestCase :pat "\\\\" :text "\\")
    (TestCase :pat "\\n" :text "a\nb")
    (TestCase :pat "\\t" :text "a\tb")
    (TestCase :pat "^[A-Za-z0-9][A-Za-z0-9._-]*$" :text "session-123_abc.v1")
    (TestCase :pat "^[A-Za-z0-9][A-Za-z0-9._-]*$" :text "-invalid")
    (TestCase :pat ":task\\s+\"((?:[^\"\\\\]|\\\\.)*)\"" :text ":task \"write tests\"")
    (TestCase :pat ":task\\s+\"((?:[^\"\\\\]|\\\\.)*)\"" :text ":task \"foo\\\"bar\"")
    (TestCase :pat "\\(:turn\\s+(\\d+)" :text "(:turn 42 :status :ok)")
    (TestCase :pat "\\b(TODO|FIXME|XXX)\\b" :text "// FIXME: check bounds")
    (TestCase :pat "(^|/)Task[^/]*\\.asl$" :text "foo/TaskBar.asl")
    (TestCase :pat "(^|/)Task[^/]*\\.asl$" :text "Task1.asl")
    (TestCase :pat "(^|/)Task[^/]*\\.asl$" :text "foo/TaskBar.py")
    (TestCase :pat "(ab)+" :text "ababab"))

fn escape-json-field s: String -> String
  (let [(s1 (stringReplace s "\\" "\\\\"))
        (s2 (stringReplace s1 "\"" "\\\""))
        (s3 (stringReplace s2 "\n" "\\n"))
        (s4 (stringReplace s3 "\r" "\\r"))]
    (stringReplace s4 "\t" "\\t"))

fn serialize-case c: TestCase -> String
  (str "{\"pat\":\"" (escape-json-field c.pat) "\",\"text\":\"" (escape-json-field c.text) "\"}")

fn serialize-cases-json cases: (List TestCase) -> String
  (let [(items (map serialize-case cases))]
    (str "[" (stringJoin items ",") "]"))

fn check-groups m: rx/Match parts: (List String) k: Int64 numGroups: Int64 -> Bool
  (if (> k numGroups)
    true
    (let [(idxStart (+ 4 (* 2 (- k 1))))
          (idxEnd (+ 5 (* 2 (- k 1))))
          (gs (optionOr (stringToInt64 (optionOr (listGet parts idxStart) "-1")) -1))
          (ge (optionOr (stringToInt64 (optionOr (listGet parts idxEnd) "-1")) -1))
          (grp (rx/regex-group m k))]
      (if (= gs -1)
        (let [(_ (refute (some? grp) (str "group " (stringFromInt64 k) " should be none")))]
          (check-groups m parts (+ k 1) numGroups))
        (let [(expected (optionOr (stringSlice m.text (- gs m.start) (- ge m.start)) ""))
              (_ (assert (= grp (some expected)) (str "group " (stringFromInt64 k) " mismatch")))]
          (check-groups m parts (+ k 1) numGroups)))))

fn verify-one-case! c: TestCase oracleLine: String idx: Int64 -> Bool
  (let [(parts (stringSplit oracleLine "	"))
        (status (optionOr (listHead parts) ""))
        (r (rx/regex-compile! c.pat))]
    (assert (ok? r) (str "Case " (stringFromInt64 idx) " compile should succeed: " c.pat))
    (mt r
      ((err e) false)
      ((ok re)
        (let [(optM (rx/regex-search! re c.text))]
          (if (= status "NONE")
            (let [(_ (refute (some? optM) (str "Case " (stringFromInt64 idx) " expected NONE for pat: " c.pat)))]
              true)
            (let [(_ (assert (some? optM) (str "Case " (stringFromInt64 idx) " expected MATCH for pat: " c.pat)))
                  (m (optionOr optM (rx/Match :start 0 :end 0 :text "" :groups (list))))
                  (pyStart (optionOr (stringToInt64 (optionOr (listGet parts 1) "0")) 0))
                  (pyEnd (optionOr (stringToInt64 (optionOr (listGet parts 2) "0")) 0))
                  (pyGroups (optionOr (stringToInt64 (optionOr (listGet parts 3) "0")) 0))
                  (expectedText (optionOr (stringSlice c.text pyStart pyEnd) ""))
                  (_ (assert (= m.start pyStart) (str "Case " (stringFromInt64 idx) " start mismatch")))
                  (_ (assert (= m.end pyEnd) (str "Case " (stringFromInt64 idx) " end mismatch")))
                  (_ (assert (= m.text expectedText) (str "Case " (stringFromInt64 idx) " text mismatch")))]
              (check-groups m parts 1 pyGroups)))))))

fn verify-cases-loop! cases: (List TestCase) oracleLines: (List String) idx: Int64 -> Bool
  (if (listEmpty? cases)
    true
    (let [(c (optionOr (listHead cases) (TestCase :pat "" :text "")))
          (restCases (optionOr (listTail cases) (list)))
          (line (optionOr (listHead oracleLines) ""))
          (restLines (optionOr (listTail oracleLines) (list)))
          (okOne (verify-one-case! c line idx))]
      (and okOne (verify-cases-loop! restCases restLines (+ idx 1)))))

fn testCasesAgainstRecordedPythonRe! -> Bool
  (let [(cases (get-test-cases))
        (readRes (fileReadString "asl/packages/asl-regex/tests/fixtures/pythonRe.tsv"))]
    (assert (ok? readRes) "fixtures/pythonRe.tsv holds python3 re.search spans and groups for get-test-cases, one line per case")
    (let [(oracleLines (stringSplit (resultOr readRes "") "\n"))]
      (assert (>= (listLength oracleLines) (listLength cases)) "one recorded python re line per case")
      (verify-cases-loop! cases oracleLines 0)))

fn testPathologicalLinear! -> Bool
  (let [(r (rx/regex-compile! "(a*)*b"))]
    (assert (ok? r) "compile (a*)*b should succeed")
    (mt r
      ((err e) false)
      ((ok re)
        (let [(optM (rx/regex-search! re "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))]
          (refute (some? optM) "(a*)*b on 30 a's should not match")
          true))))

fn testSuiteNameOverGitLsFiles! -> Bool
  (let [(out (processRun "git ls-files"))]
    (assert (= out.exitCode 0) "git ls-files should succeed")
    (let [(lines (stringSplit out.stdout "
"))
          (r (rx/regex-compile! "(Test\\.asl|_test\\.asl|Test\\.sh|_test\\.sh)$|(^|/)Task[^/]*\\.asl$"))]
      (assert (ok? r) "compile SUITE_NAME should succeed")
      (mt r
        ((err e) false)
        ((ok re)
          (let [(matches (filter (fn [(p String)] -> Bool (rx/regex-match? re p)) lines))
                (matchCount (listLength matches))
                (ereOut (processRun "git ls-files | /usr/bin/grep -cE '(Test[.]asl|_test[.]asl|Test[.]sh|_test[.]sh)$|(^|/)Task[^/]*[.]asl$'"))
                (ereCount (optionOr (stringToInt64 (stringTrim ereOut.stdout)) -1))]
            (assert (= matchCount ereCount) "SUITE_NAME match count over git ls-files equals POSIX ERE grep over the same list")
            (assert (>= matchCount 990) "SUITE_NAME match count should be at least 990")
            true)))))

fn testFullMatchAndFindReplace! -> Bool
  (let [(r (rx/regex-compile! "a(b+)a"))]
    (assert (ok? r) "compile should succeed")
    (mt r
      ((err e) false)
      ((ok re)
        (let [(mFull (rx/regex-match-full! re "abba"))
              (mFullFail (rx/regex-match-full! re "xabbay"))
              (matches (rx/regex-find-all! re "xabbayabbaa"))
              (replaced (rx/regex-replace-all! re "xabbayabbaa" "<\\1>"))]
          (assert (some? mFull) "fullmatch abba should match")
          (refute (some? mFullFail) "fullmatch xabbay should not match")
          (assert (= (listLength matches) 2) "find-all should find 2 matches")
          (assert (= replaced "x<bb>y<bb>a") "replace-all should replace backrefs")
          true))))

fn testCompileErrors! -> Bool
  (let [(e1 (rx/regex-compile! "(abc"))
        (e2 (rx/regex-compile! "*abc"))
        (e3 (rx/regex-compile! "a{5,2}"))]
    (refute (ok? e1) "unclosed ( should fail to compile")
    (refute (ok? e2) "leading * should fail to compile")
    (refute (ok? e3) "invalid repeat should fail to compile")
    (mt e1
      ((ok _) false)
      ((err msg)
        (assert (stringContains? msg "position") "error msg should contain position")
        true)))

fn ! runTests -> Bool
  (and (testCasesAgainstRecordedPythonRe!)
       (and (testPathologicalLinear!)
            (and (testSuiteNameOverGitLsFiles!)
                 (and (testFullMatchAndFindReplace!)
                      (testCompileErrors!)))))
