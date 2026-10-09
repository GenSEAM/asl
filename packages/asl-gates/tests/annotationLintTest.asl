(module asl-gates/tests/annotationLintTest :x [testKebabSegments testIsRefAnnotation testExtractAnnotationBody testAuditSingle testAuditDensity runTests] :i [(annotationLint :a al)])

fn testKebabSegments -> Bool
  (do (assert (= (al/countKebabSegments "word") 1) "1-segment") (assert (= (al/countKebabSegments "two-words") 2) "2-segment") (assert (= (al/countKebabSegments "three-word-tag") 3) "3-segment") true)

fn testIsRefAnnotation -> Bool
  (do (assert (al/isRefAnnotation "@ref:foo") "ref") (assert (al/isRefAnnotation "@dep:bar") "dep") (assert (al/isRefAnnotation "@task:baz") "task") (assert (al/isRefAnnotation "@mem:qux") "mem") (assert (not (al/isRefAnnotation "@other:foo")) "other") true)

fn testExtractAnnotationBody -> Bool
  (do (assert (= (al/extractAnnotationBody "@ref:foo-bar") "foo-bar") "ref") (assert (= (al/extractAnnotationBody "@dep:bar-baz") "bar-baz") "dep") (assert (= (al/extractAnnotationBody "@task:hello") "hello") "task") (assert (= (al/extractAnnotationBody "@mem:world") "world") "mem") (assert (= (al/extractAnnotationBody "@other:foo") "@other:foo") "other") true)

fn testAuditSingle -> Bool
  (let [(r1 (al/auditSingleAnnotation "@ref:ok-tag" 2)) (r2 (al/auditSingleAnnotation "@ref:too-long-tag" 2))] (do (assert r1.valid "valid r1") (assert (= r1.tokens 2) "tokens 2") (assert (not r2.valid) "invalid r2") (assert (= r2.tokens 3) "tokens 3") true))

fn testAuditDensity -> Bool
  (let [(validList (list "@ref:foo" "@dep:bar-baz")) (invalidList (list "@ref:foo" "@dep:bar-baz-qux"))] (do (assert (al/auditAnnotationDensity validList 2) "valid list") (assert (not (al/auditAnnotationDensity invalidList 2)) "invalid list") true))

fn runTests -> Bool
  (do (assert (testKebabSegments) "testKebabSegments") (assert (testIsRefAnnotation) "testIsRefAnnotation") (assert (testExtractAnnotationBody) "testExtractAnnotationBody") (assert (testAuditSingle) "testAuditSingle") (assert (testAuditDensity) "testAuditDensity") true)
