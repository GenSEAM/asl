(module asl-gates/tests/annotationLintTest
  :d "Unit tests for annotation_lint functionality."
  :x [testKebabSegments testIsRefAnnotation testExtractAnnotationBody testAuditSingle testAuditDensity runTests]
  :i [(annotationLint :a al)])

(df testKebabSegments [] -> Bool
  :d "Verifies countKebabSegments functionality"
  (do
    (assert (= (al/countKebabSegments "word") 1) "1-segment")
    (assert (= (al/countKebabSegments "two-words") 2) "2-segment")
    (assert (= (al/countKebabSegments "three-word-tag") 3) "3-segment")
    true))

(df testIsRefAnnotation [] -> Bool
  :d "Verifies isRefAnnotation for different tags"
  (do
    (assert (al/isRefAnnotation "@ref:foo") "ref")
    (assert (al/isRefAnnotation "@dep:bar") "dep")
    (assert (al/isRefAnnotation "@task:baz") "task")
    (assert (al/isRefAnnotation "@mem:qux") "mem")
    (assert (not (al/isRefAnnotation "@other:foo")) "other")
    true))

(df testExtractAnnotationBody [] -> Bool
  :d "Verifies extractAnnotationBody extraction"
  (do
    (assert (= (al/extractAnnotationBody "@ref:foo-bar") "foo-bar") "ref")
    (assert (= (al/extractAnnotationBody "@dep:bar-baz") "bar-baz") "dep")
    (assert (= (al/extractAnnotationBody "@task:hello") "hello") "task")
    (assert (= (al/extractAnnotationBody "@mem:world") "world") "mem")
    (assert (= (al/extractAnnotationBody "@other:foo") "@other:foo") "other")
    true))

(df testAuditSingle [] -> Bool
  :d "Verifies auditSingleAnnotation logic"
  (let [(r1 (al/auditSingleAnnotation "@ref:ok-tag" 2))
        (r2 (al/auditSingleAnnotation "@ref:too-long-tag" 2))]
    (do
      (assert (.-valid r1) "valid r1")
      (assert (= (.-tokens r1) 2) "tokens 2")
      (assert (not (.-valid r2)) "invalid r2")
      (assert (= (.-tokens r2) 3) "tokens 3")
      true)))

(df testAuditDensity [] -> Bool
  :d "Verifies auditAnnotationDensity logic"
  (let [(validList (list "@ref:foo" "@dep:bar-baz"))
        (invalidList (list "@ref:foo" "@dep:bar-baz-qux"))]
    (do
      (assert (al/auditAnnotationDensity validList 2) "valid list")
      (assert (not (al/auditAnnotationDensity invalidList 2)) "invalid list")
      true)))

(df runTests [] -> Bool
  :d "Master test runner for annotation lint."
  (do
    (assert (testKebabSegments) "testKebabSegments")
    (assert (testIsRefAnnotation) "testIsRefAnnotation")
    (assert (testExtractAnnotationBody) "testExtractAnnotationBody")
    (assert (testAuditSingle) "testAuditSingle")
    (assert (testAuditDensity) "testAuditDensity")
    true))
