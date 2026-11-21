(module asl-checker/tests/layoutCalcTest
  :x [runTests]
  :i [(layout :a lay)])

; (:m :ref LL-LAYOUT-VIEW :do "layoutOf gate: packed and C struct sizes and offsets, the :align override, and ERR_LAYOUT_FIELD for an unknown kind or a count below 1")

fn one name: String kind: String -> lay/FieldSpec
  (lay/FieldSpec :name name :kind kind :count 1)

fn rep name: String kind: String count: Int64 -> lay/FieldSpec
  (lay/FieldSpec :name name :kind kind :count count)

fn sizeOf mode: String fields: (List lay/FieldSpec) -> Int64
  (match (lay/layoutOf mode fields (none))
    ((ok l) l.sizeOf)
    ((err _) -1))

fn offsetAt mode: String fields: (List lay/FieldSpec) i: Int64 -> Int64
  (match (lay/layoutOf mode fields (none))
    ((ok l) (optionOr (listGet l.offsetOf i) -1))
    ((err _) -1))

fn ! runTests -> Bool
  (do
    (assert (= (sizeOf "packed" (list (one "a" "U32") (one "b" "U16") (one "c" "U8"))) 7) "packed U32 U16 U8 is 7 bytes")
    (assert (= (offsetAt "packed" (list (one "a" "U32") (one "b" "U16") (one "c" "U8")) 0) 0) "packed first field at 0")
    (assert (= (offsetAt "packed" (list (one "a" "U32") (one "b" "U16") (one "c" "U8")) 1) 4) "packed second field at 4")
    (assert (= (offsetAt "packed" (list (one "a" "U32") (one "b" "U16") (one "c" "U8")) 2) 6) "packed third field at 6")
    (assert (= (sizeOf "c" (list (one "a" "U8") (one "b" "U32"))) 8) "c U8 U32 is 8 bytes")
    (assert (= (offsetAt "c" (list (one "a" "U8") (one "b" "U32")) 1) 4) "c pads the U32 to offset 4")
    (assert (= (sizeOf "c" (list (one "a" "U8") (one "b" "U16") (one "c" "U8"))) 6) "c U8 U16 U8 is 6 bytes")
    (assert (= (sizeOf "c" (list (one "tv_sec" "I64") (one "tv_nsec" "I64"))) 16) "c timespec is 16 bytes")
    (assert (= (sizeOf "c" (list (rep "a" "U8" 3) (one "b" "U32"))) 8) "c U8 x3 then U32 is 8 bytes")
    (assert (= (offsetAt "c" (list (rep "a" "U8" 3) (one "b" "U32")) 1) 4) "c U8 x3 then U32 puts the U32 at 4")
    (assert (= (match (lay/layoutOf "packed" (list (one "a" "U32") (one "b" "U16") (one "c" "U8")) (some 4)) ((ok l) l.sizeOf) ((err _) -1)) 8) "packed with align 4 rounds the size to 8")
    (assert (match (lay/layoutOf "c" (list (one "a" "Widget")) (none)) ((err e) (= e "ERR_LAYOUT_FIELD")) ((ok _) false)) "an unknown kind is ERR_LAYOUT_FIELD")
    (assert (match (lay/layoutOf "c" (list (rep "a" "U8" 0)) (none)) ((err e) (= e "ERR_LAYOUT_FIELD")) ((ok _) false)) "a count below 1 is ERR_LAYOUT_FIELD")
    true)
