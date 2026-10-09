(module asl-lens/tests/lensTest
  :x [testFindLensById testDiscoverLensesForText testComposeLensesWithPack testLevel1Probe runTests]
  :i [(asl-lens :a lens)])

fn testFindLensById -> Bool
  (let [(direct (lens/findLensById "concurrency"))
        (alias (lens/findLensById "attention-density"))
        (missing (lens/findLensById "no-such-lens"))]
    (do
      (assert (mt direct ((some l) (= l.id "concurrency")) ((none) false)) "direct id resolves to its lens")
      (assert (mt alias ((some l) (= l.id "token-economics")) ((none) false)) "alias attention-density resolves to token-economics")
      (refute (mt missing ((some _) true) ((none) false)) "unknown lens id resolves to none")
      true))

fn testDiscoverLensesForText -> Bool
  (let [(conc (lens/discoverLensesForText "mutex deadlock"))
        (fallback (lens/discoverLensesForText "qqq"))]
    (do
      (assert (= conc (list "concurrency")) "concurrency keywords select only the concurrency lens")
      (assert (= fallback (list "falsification" "invariants")) "text with no keyword falls back to falsification and invariants")
      (refute (listContains? fallback "concurrency") "fallback does not include unmatched lenses")
      true))

fn testComposeLensesWithPack -> Bool
  (let [(coding (lens/composeLensesWithPack "coding"))
        (unknown (lens/composeLensesWithPack "unknown-pack"))]
    (do
      (assert (= (listLength coding) 10) "coding pack adds five lenses to five essentials")
      (assert (listContains? coding "security") "coding pack includes security")
      (assert (= unknown (lens/tier1EssentialMetaLensIds)) "unknown pack composes to essentials only")
      true))

fn testLevel1Probe -> Bool
  (let [(known (lens/formatLevel1Probe "falsification" "src/a.asl"))
        (unknown (lens/formatLevel1Probe "no-such-lens" "src/a.asl"))]
    (do
      (assert (stringContains? known ":target \"src/a.asl\"") "probe carries the target")
      (assert (stringContains? unknown "Audit target under no-such-lens criteria.") "unknown lens gets the generic question")
      (refute (stringContains? known "Audit target under falsification criteria.") "known lens uses its own probe question")
      true))

fn ! runTests -> Bool
  (do
    (assert (testFindLensById) "testFindLensById")
    (assert (testDiscoverLensesForText) "testDiscoverLensesForText")
    (assert (testComposeLensesWithPack) "testComposeLensesWithPack")
    (assert (testLevel1Probe) "testLevel1Probe")
    true)
