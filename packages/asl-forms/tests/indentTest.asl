(module asl-forms/tests/indentTest :x [runTests] :i [(asl-forms/indent :a ind)])

; (:m :do "house style the guide must leave alone: match arms whose body sits one column right of the pattern opener, an opener ending its line, a closer-only line, aligned list items, and delimiters inside strings and comments")
fn houseText -> String
  "fn h w: (Option String) -> String\n  (match w\n    ((none) \"(\")\n    ((some s)\n      (str s \")\")))\n\n(:rows :items (\n    (:a 1) ; (\n    (:b \"[\")\n  )\n  :n [1\n      2])\n"

fn testMissingCloser -> Bool
  (let [(src "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n")
        (g (ind/guide src))]
    (do
      (assert (= g.text "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0))\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n") "the closer of let goes to the end of its last body line, not where the next fn starts")
      (assert (= (ind/editsAsn g.edits) "((:insert \")\" :line 3 :col 21 :opener (:line 2 :col 3 :head \"let\") :by (:line 5)))") "the edit names the opener and the line whose indentation closed it")
      true))

fn testStrayCloser -> Bool
  (let [(g (ind/guide "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)))\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n"))]
    (do
      (assert (= g.text "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0))\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n") "a closer with nothing open is deleted where it stands")
      (assert (= (ind/editsAsn g.edits) "((:delete \")\" :line 3 :col 22 :stray true))") "a stray closer is reported as stray")
      true))

fn testBalancedMisnest -> Bool
  (let [(src "fn f x: Int64 -> Int64\n  (let ((y (+ x 1))\n    (if (> y 2) y 0)))\n")
        (g (ind/guide src))
        (b (ind/guideBroken src))]
    (do
      (assert (= g.text "fn f x: Int64 -> Int64\n  (let ((y (+ x 1)))\n    (if (> y 2) y 0))\n") "parens that balance but put the body inside the bindings follow the indentation")
      (assert (= (listLength g.edits) 2) "one closer moves: an insert and a delete")
      (assert (= (ind/editsAsn g.edits) "((:insert \")\" :line 2 :col 20 :opener (:line 2 :col 8 :head \"\") :by (:line 3)) (:delete \")\" :line 3 :col 22 :stray true))") "the bindings opener gets its closer on its own line and the closer left over is stray")
      (assert (= b.text src) "guideBroken leaves a balanced segment as it is")
      (assert (= (listLength b.skipped) 2) "and returns its disagreements as skipped")
      true))

fn testExtraCloserMidForm -> Bool
  (let [(g (ind/guide "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (foo y))\n    (bar y))\n"))]
    (do
      (assert (= g.text "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (foo y)\n    (bar y))\n") "a body line right of the form the previous line closed reopens it")
      (assert (= (ind/editsAsn g.edits) "((:delete \")\" :line 3 :col 12 :opener (:line 2 :col 3 :head \"let\") :by (:line 4)))") "the deleted closer is the one that closed let early")
      true))

fn testWrongKind -> Bool
  (let [(g (ind/guide "(:a [1 2)\n  :b 3)\n"))]
    (do
      (assert (= g.text "(:a [1 2]\n  :b 3)\n") "a closer of the wrong kind is replaced by the kind its opener needs")
      (assert (= (ind/editsAsn g.edits) "((:replace \")\" :with \"]\" :line 1 :col 9 :opener (:line 1 :col 5 :head \"1\")))") "replace names what it was and what it became")
      true))

fn testHouseStyleIsFixedPoint -> Bool
  (let [(src (houseText))
        (g (ind/guide src))]
    (do
      (assert (listEmpty? g.edits) (str "house style needs no edit, got " (ind/editsAsn g.edits)))
      (assert (= g.text src) "and the text comes back unchanged")
      true))

fn testBrokenSegmentOnly -> Bool
  (let [(src (str "fn f x: Int64 -> Int64\n  (let ((y (+ x 1))\n    (if (> y 2) y 0)))\n\n" "fn g x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)\n"))
        (b (ind/guideBroken src))]
    (do
      (assert (= b.text (str "fn f x: Int64 -> Int64\n  (let ((y (+ x 1))\n    (if (> y 2) y 0)))\n\n" "fn g x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0))\n")) "only the unbalanced fn g is repaired")
      (assert (= (listLength b.edits) 1) "one applied edit")
      (assert (= (listLength b.skipped) 2) "the balanced misnest in fn f is skipped, not applied")
      true))

; (:m :ref unbalancedFormDiagnostic :do "a missing closer in the second fn names that fn as its item; a stray closer names none; a module header above is not the item")
fn testItemNamed -> Bool
  (let [(src "(module ub2 :x [g h] :i [])\n\nfn g -> Int64\n  1\n\nfn ! h x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (+ y 2)\n\nfn k -> Int64\n  3\n")
        (g (ind/guide src))
        (stray (ind/guide "fn f -> Int64\n  1)\n"))]
    (do
      (assert (= (ind/editsAsnIn src g.edits) "((:insert \")\" :line 8 :col 12 :opener (:line 7 :col 3 :head \"let\") :by (:line 10) :item (:line 6 :kind \"fn\" :name \"h\")))") (str "the edit names fn h as its item, got " (ind/editsAsnIn src g.edits)))
      (assert (= (ind/editsAsnIn "fn f -> Int64\n  1)\n" stray.edits) (ind/editsAsn stray.edits)) "a stray closer gets no item")
      true))

fn runTests -> Bool
  (do
    (assert (testItemNamed) "testItemNamed")
    (assert (testMissingCloser) "testMissingCloser")
    (assert (testStrayCloser) "testStrayCloser")
    (assert (testBalancedMisnest) "testBalancedMisnest")
    (assert (testExtraCloserMidForm) "testExtraCloserMidForm")
    (assert (testWrongKind) "testWrongKind")
    (assert (testHouseStyleIsFixedPoint) "testHouseStyleIsFixedPoint")
    (assert (testBrokenSegmentOnly) "testBrokenSegmentOnly")
    true)
