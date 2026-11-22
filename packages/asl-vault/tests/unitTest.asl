(module asl-vault/tests/unitTest
  :x [runTests]
  :i [(asl-vault/unit :a un) (asl-vault/time :a tm) (asl-vault/codec :a cd)])

fn passage id: String t: String -> un/Passage
  (un/Passage :id id :text t)

fn base -> un/ProvUnit
  (un/ProvUnit :kind "note" :source "https://example.org/a" :title "T" :observedAt 1000 :retrievedAt 2000 :licence "cc-by" :reviewBy 9000
               :confidenceBp 9000 :replaces "" :contentHash "" :ext (list (pair "k" "v") (pair "q" "a\"b\nc")) :passages (list (passage "p1" "one") (passage "p2" "two \\ three")))

fn invalid? u: un/ProvUnit what: String -> Bool
  (match (un/validateUnit u) ((err e) (stringContains? e what)) ((ok _) false))

; (:m :ref VS-VAULT :do "ports the automate unit rules onto epoch ms and basis points: one time form, one canonical byte form, a hash that binds the bytes, and every refusal of validateUnit")
fn testUnit -> Bool
  (let [(u (base))
        (sealed (un/sealUnit u))
        (hex64 (stringRepeat "a" 64))]
    (do
      (assert (= (tm/isoToEpoch "1970-01-01T00:00:00Z") (some 0)) "the epoch is time zero")
      (assert (= (tm/isoToEpoch "2026-11-20T12:00:00Z") (some 1795176000000)) "a known instant converts to epoch ms")
      (assert (= (tm/epochToIso 1795176000000) "2026-11-20T12:00:00Z") "epoch ms converts back to the canonical form")
      (assert (= (tm/isoToEpoch "2024-02-29T23:59:59Z") (some 1709251199000)) "a leap day is a time")
      (assert (none? (tm/isoToEpoch "2025-02-29T00:00:00Z")) "a non-leap 29 February is not a time")
      (assert (none? (tm/isoToEpoch "2026-11-20 12:00:00Z")) "another spelling is rejected so equal instants have one form")
      (assert (none? (tm/isoToEpoch "1969-12-31T23:59:59Z")) "years before 1970 are rejected")
      (assert (none? (tm/isoToEpoch "2026-13-01T00:00:00Z")) "month 13 is rejected")
      (assert (= (tm/epochToIso (optionOr (tm/isoToEpoch "2000-03-01T00:00:00Z") 0)) "2000-03-01T00:00:00Z") "a century leap year round trips")
      (assert (= (un/parseUnit (un/emitUnit u)) (ok u)) "a unit survives emit and parse unchanged with quotes, newlines and backslashes")
      (assert (= (un/emitUnit u) (un/emitUnit u)) "emit is deterministic")
      (assert (un/hexHash? sealed.contentHash) "sealing yields a sha256 hex")
      (assert (= sealed.contentHash (un/bodyHash u)) "the seal is the hash of the unit with contentHash blanked")
      (assert (!= sealed.contentHash (un/bodyHash (with u :title "T2"))) "a changed field changes the hash")
      (assert (= (un/bodyHash sealed) sealed.contentHash) "re-hashing a sealed unit gives its own seal")
      (assert (= (un/sha256Hex "abc") "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") "sha256Hex is the standard digest")
      (assert (ok? (un/validateUnit sealed)) "a well formed unit validates")
      (assert (invalid? (with u :kind "bad kind") "kind") "kind must be an id")
      (assert (invalid? (with u :source "  ") "source") "empty source rejected")
      (assert (invalid? (with u :title "") "title") "empty title rejected")
      (assert (invalid? (with u :observedAt 3000) "observedAt") "observed after retrieved rejected")
      (assert (invalid? (with u :reviewBy 2000) "reviewBy") "review not after retrieved rejected")
      (assert (invalid? (with u :licence "") "licence") "empty licence rejected")
      (assert (invalid? (with u :confidenceBp 10001) "confidenceBp") "confidence over 10000 rejected")
      (assert (invalid? (with u :confidenceBp -1) "confidenceBp") "negative confidence rejected")
      (assert (invalid? (with u :replaces "xyz") "replaces") "a replaces that is not a sha256 is rejected")
      (assert (ok? (un/validateUnit (with u :replaces hex64))) "a sha256 replaces is accepted")
      (assert (invalid? (with u :contentHash (stringRepeat "A" 64)) "contentHash") "upper case hex is not a sha256")
      (assert (invalid? (with u :ext (list (pair "" "x"))) "ext keys must not") "an empty ext key is rejected")
      (assert (invalid? (with u :ext (list (pair "k" "1") (pair "k" "2"))) "unique") "a duplicate ext key is rejected")
      (assert (invalid? (with u :passages (list)) "at least one") "a unit needs a passage")
      (assert (invalid? (with u :passages (list (passage "p1" ""))) "passage id and text") "an empty passage is rejected")
      (assert (invalid? (with u :passages (list (passage "p1" "a") (passage "p1" "b"))) "passage ids") "duplicate passage ids are rejected")
      (assert (err? (un/parseUnit (stringReplace (un/emitUnit u) ":v 1" ":v 2"))) "an unsupported version is an error")
      (assert (err? (un/parseUnit (stringReplace (un/emitUnit u) ":licence \"cc-by\"" ""))) "a missing field is an error")
      (assert (err? (un/parseUnit (str (un/emitUnit u) " x"))) "trailing text is an error")
      true))

; (:m :ref VS-VAULT :do "ports the passage splitter of automate vault: blank lines and # headings cut passages, CRLF is normalised, a long block is cut at 1200 characters, ids run p1, p2, ...")
fn testPassages -> Bool
  (let [(long (stringRepeat "x" 2500))
        (ps (un/splitPassages "# A\nline1\nline2\n\n# B\ntext\r\n\r\nplain"))
        (lp (un/splitPassages long))]
    (do
      (assert (= (map (fn [(p un/Passage)] -> String p.id) ps) (list "p1" "p2" "p3")) "passage ids run p1 p2 p3")
      (assert (= (map (fn [(p un/Passage)] -> String p.text) ps) (list "# A\nline1\nline2" "# B\ntext" "plain")) "headings start passages and CRLF is normalised")
      (assert (= (listLength lp) 3) "2500 characters make three chunks")
      (assert (= (map (fn [(p un/Passage)] -> Int64 (stringLength p.text)) lp) (list 1200 1200 100)) "chunks are 1200, 1200 and the rest")
      (assert (listEmpty? (un/splitPassages "  \n\n ")) "blank text has no passages")
      true))

; (:m :ref VS-VAULT :do "ids are one store key segment: letters, digits, - and _ up to 120 bytes; dedupStrings keeps first-seen order and drops blanks")
fn testCodec -> Bool
  (do
    (assert (cd/validId? "fact-2026_a") "letters, digits, - and _ are an id")
    (assert (not (cd/validId? "a/b")) "a slash is not an id")
    (assert (not (cd/validId? ".hidden")) "a leading dot is not an id")
    (assert (not (cd/validId? "")) "empty is not an id")
    (assert (not (cd/validId? "a b")) "a space is not an id")
    (assert (and (cd/validId? (stringRepeat "a" 120)) (not (cd/validId? (stringRepeat "a" 121)))) "120 bytes is the limit")
    (assert (= (cd/dedupStrings (list "b" "a" "b" " " "c" "a")) (list "b" "a" "c")) "dedup keeps first-seen order and drops blanks")
    (assert (cd/uniqueStrings? (list "a" "b")) "distinct strings are unique")
    (assert (not (cd/uniqueStrings? (list "a" "b" "a"))) "a repeat is not unique")
    true)

fn runTests -> Bool
  (and (testUnit) (and (testPassages) (testCodec)))
