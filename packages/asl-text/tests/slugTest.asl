(module asl-text/tests/slugTest :x [runTests] :i [(asl-text/slug :a sl)])

fn testBasic -> Bool
  (do (assert (= (sl/slugify "Hello World" "-" 50) "hello-world") "basic slugify")
      (assert (= (sl/slugify "Hello   World" "-" 50) "hello-world") "collapses spaces")
      (assert (= (sl/slugify "  Hello World  " "-" 50) "hello-world") "trims edges")
      (assert (= (sl/slugify "The Quick Brown Fox" "-" 50) "the-quick-brown-fox") "words joined")
      true)

fn testAccents -> Bool
  (do (assert (= (sl/slugify "café" "-" 50) "cafe") "folds acute")
      (assert (= (sl/slugify "naïve" "-" 50) "naive") "folds diaeresis")
      (assert (= (sl/slugify "résumé" "-" 50) "resume") "folds multiple")
      (assert (= (sl/slugify "piñata" "-" 50) "pinata") "folds tilde")
      (assert (= (sl/slugify "façade" "-" 50) "facade") "folds cedilla")
      (assert (= (sl/slugify "Ångström" "-" 50) "angstrom") "folds ring and umlaut")
      (assert (= (sl/slugify "Æsop" "-" 50) "aesop") "folds ae ligature")
      (assert (= (sl/slugify "ß" "-" 50) "ss") "folds sharp s")
      true)

fn testMaxLen -> Bool
  (do (assert (= (sl/slugify "hello-world" "-" 5) "hello") "cuts at word boundary")
      (assert (= (sl/slugify "hello-world" "-" 11) "hello-world") "fits exactly")
      (assert (= (sl/slugify "hello-world" "-" 10) "hello") "cuts before separator")
      (assert (= (sl/slugify "a-b-c-d-e" "-" 3) "a") "short maxLen")
      (assert (= (sl/slugify "singleword" "-" 5) "singl") "no separator cuts at maxLen")
      true)

fn testSeparators -> Bool
  (do (assert (= (sl/slugify "Hello World" "_" 50) "hello_world") "underscore separator")
      (assert (= (sl/slugify "Hello World" "--" 50) "hello--world") "multi-char separator")
      (assert (= (sl/slugify "Hello World" "--" 6) "hello") "multi-char sep cut drops dangling fragment")
      (assert (= (sl/slugify "Hello World" "--" 7) "hello") "multi-char sep cut drops full trailing sep")
      true)

fn testEdgeCases -> Bool
  (do (assert (= (sl/slugify "" "-" 50) "") "empty string")
      (assert (= (sl/slugify "!!!" "-" 50) "") "only punctuation")
      (assert (= (sl/slugify "123" "-" 50) "123") "numbers only")
      (assert (= (sl/slugify "a" "-" 1) "a") "single char at maxLen")
      (assert (= (sl/slugify "ab" "-" 1) "a") "single char cut")
      true)

fn runTests -> Bool
  (and (testBasic) (testAccents) (testMaxLen) (testSeparators) (testEdgeCases))
