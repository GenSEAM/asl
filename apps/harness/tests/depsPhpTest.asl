(module aslHarness/tests/depsPhpTest :x [runTests] :i [(depsPhp :a php)])

fn testExtractComposerVersion -> Bool
  (let [(sample "{\n  \"packages\": [\n    {\n      \"name\": \"monolog/monolog\",\n      \"version\": \"3.4.0\"\n    }\n  ]\n}") (ver (php/extractComposerVersion sample "monolog/monolog"))] (assert (match ver ((none) false) ((some v) (= v "3.4.0"))) "version extracted is 3.4.0") (assert (match (php/extractComposerVersion sample "nonexistent/pkg") ((none) true) ((some _) false)) "nonexistent pkg returns none") true)

fn testExtractPhpAttributes -> Bool
  (let [(code "<?php\n#[Route('/api/v1', methods: ['GET'])]\nclass ApiController {}\n#[ORM\\Id]\nprivate int $id;") (attrs (php/extractPhpAttributes code))] (assert (>= (listLength attrs) 2) "at least 2 attributes found") (assert (= (optionOr (listGet attrs 0) (php/PhpAttribute :targetSymbol "" :attributeName "" :arguments "" :line 0)).attributeName "Route") "first attribute is Route") true)

fn testAuditPhpCompatibility -> Bool
  (let [(cleanCode "<?php\n$fn = fn($x) => $x * 2;\necho $fn(5);") (dirtyCode "<?php\n$f = create_function('$a', 'return $a * 2;');") (cleanRep (php/auditPhpCompatibility cleanCode "8.2")) (dirtyRep (php/auditPhpCompatibility dirtyCode "8.2"))] (assert cleanRep.compatible "clean code is compatible") (assert (not dirtyRep.compatible) "dirty code is incompatible") (assert (> (listLength dirtyRep.violations) 0) "violations found in dirty code") true)

fn testFormatPhpCompatibility -> Bool
  (let [(cleanRep (php/PhpCompatibilityReport :targetVersion "8.2" :violations (list) :compatible true)) (dirtyRep (php/PhpCompatibilityReport :targetVersion "8.2" :violations (list "Deprecated create_function") :compatible false)) (fmtC (php/formatPhpCompatibility cleanRep)) (fmtD (php/formatPhpCompatibility dirtyRep))] (assert (stringContains? fmtC "Fully Compatible") "clean format contains Fully Compatible") (assert (stringContains? fmtD "Violations Found") "dirty format contains Violations Found") true)

fn runTests -> Bool
  (do (testExtractComposerVersion) (testExtractPhpAttributes) (testAuditPhpCompatibility) (testFormatPhpCompatibility) true)
