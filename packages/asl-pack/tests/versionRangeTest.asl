(module asl-pack/tests/versionRangeTest
  :x [runTests]
  :i [(pkgIndex :a ix)])

fn ! row spec: String v: String expected: Bool -> Bool
  (do
    (assert (= (ix/versionSatisfies? spec v) expected)
            (str "versionSatisfies? spec '" spec "' version '" v "' expected " (if expected "match" "no match")))
    true)

fn ! table -> Bool
  (do
    (row "*" "1.2.3" true)
    (row ">=1.2" "1.2.0" true)
    (row ">=1.2" "1.1.9" false)
    (row "^1.2" "1.9.0" true)
    (row "^1.2" "2.0.0" false)
    (row "^0.2.3" "0.2.9" true)
    (row "^0.2.3" "0.3.0" false)
    (row "1.2.0" "1.2" true)
    (row "1.2.0" "1.2.1" false)
    (row "~1.2.3" "1.2.9" true)
    (row "~1.2.3" "1.3.0" false)
    (row "~1.2.3" "1.2.2" false)
    (row ">1.2.3" "1.2.4" true)
    (row ">1.2.3" "1.2.3" false)
    (row "<2.0" "1.9.9" true)
    (row "<2.0" "2.0.0" false)
    (row "<=2.0" "2.0.0" true)
    (row "<=2.0" "2.0.1" false)
    (row "=1.2.3" "1.2.3" true)
    (row "=1.2.3" "1.2.4" false)
    (row ">=1.0 <2.0" "1.5.0" true)
    (row ">=1.0 <2.0" "2.0.0" false)
    (row ">=1.0 <2.0 || >=3.1" "3.2.0" true)
    (row ">=1.0 <2.0 || >=3.1" "2.5.0" false)
    (row "bad spec" "1.0.0" false)
    (row "~" "1.2.3" false)
    true)

fn ! validity -> Bool
  (do
    (assert (ix/specValid? "*") "star is valid")
    (assert (ix/specValid? ">=1.0 <2.0 || >=3.1") "AND and OR are valid")
    (assert (ix/specValid? "~1.2.3") "tilde is valid")
    (assert (ix/specValid? "=1.2.3") "equals is valid")
    (assert (not (ix/specValid? "bad spec")) "a malformed spec is invalid")
    (assert (not (ix/specValid? ">=")) "an operator without a version is invalid")
    (assert (not (ix/specValid? "1.2.3.4.5")) "too many version parts is invalid")
    (assert (not (ix/specValid? "1.0 ||")) "an empty alternative is invalid")
    true)

fn ! runTests -> Bool
  (do
    (table)
    (validity)
    true)
