(module asl-text/tests/caseTest
  :x [runTests]
  :i [(asl-text/case :a cs)])

fn testSplit -> Bool
  (do (assert (= (cs/splitWords "breaker_is_quota_error") (list "breaker" "is" "quota" "error")) "snake splits")
      (assert (= (cs/splitWords "XMLHttpRequest") (list "XML" "Http" "Request")) "acronym boundary")
      (assert (= (cs/splitWords "parseHTTPRequest") (list "parse" "HTTP" "Request")) "lower to acronym")
      (assert (= (cs/splitWords "utf8Decode") (list "utf8" "Decode")) "digits stay with preceding word")
      (assert (= (cs/splitWords "foo-bar baz") (list "foo" "bar" "baz")) "dash and space split")
      (assert (= (cs/splitWords "") (list)) "empty string")
      (assert (= (cs/splitWords "hello") (list "hello")) "single word")
      true)

fn testCamel -> Bool
  (do (assert (= (cs/toCamel "breaker_is_quota_error") "breakerIsQuotaError") "camel from snake")
      (assert (= (cs/toCamel "XMLHttpRequest") "xmlHttpRequest") "camel from acronym")
      (assert (= (cs/toCamel "hello") "hello") "camel single word")
      (assert (= (cs/toCamel "") "") "camel empty")
      true)

fn testPascal -> Bool
  (do (assert (= (cs/toPascal "foo_bar_baz") "FooBarBaz") "pascal from snake")
      (assert (= (cs/toPascal "XMLHttpRequest") "XmlHttpRequest") "pascal from acronym")
      true)

fn testKebab -> Bool
  (do (assert (= (cs/toKebab "fooBarBaz") "foo-bar-baz") "kebab from camel")
      (assert (= (cs/toKebab "XMLHttpRequest") "xml-http-request") "kebab from acronym")
      true)

fn testSnake -> Bool
  (do (assert (= (cs/toSnake "fooBarBaz") "foo_bar_baz") "snake from camel")
      (assert (= (cs/toSnake "utf8Decode") "utf8_decode") "snake keeps digits")
      true)

fn runTests -> Bool
  (and (testSplit) (testCamel) (testPascal) (testKebab) (testSnake))
