(module asl-html/tests/rectAtTest :x [runTests] :i [(asl-html/html :a h) (asl-html/svg :a s)])

; (:m :ref COVBATCH3 :do "rectAt writes x y width height with trimmed numbers and then the extra attributes")
fn at haystack: String needle: String -> Int64
  (optionOr (stringIndexOf haystack needle) (- 0 1))

fn runTests -> Bool
  (let [(plain (h/render (s/rectAt 1.0 2.5 3.0 4.0 (list))))
        (extra (h/render (s/rectAt 0.0 -1.5 10.0 20.0 (list (h/attr "fill" "red")))))]
    (do
      (assert (stringStartsWith? plain "<rect ") "an svg rect element")
      (assert (stringContains? plain "x=\"1\"") "a whole number loses its .0")
      (assert (stringContains? plain "y=\"2.5\"") "a fraction is kept")
      (assert (stringContains? plain "width=\"3\"") "width")
      (assert (stringContains? plain "height=\"4\"") "height")
      (assert (< (at plain "x=") (at plain "y=")) "x comes before y")
      (assert (< (at plain "width=") (at plain "height=")) "width comes before height")
      (assert (stringContains? extra "x=\"0\"") "zero")
      (assert (stringContains? extra "y=\"-1.5\"") "a negative fraction")
      (assert (stringContains? extra "fill=\"red\"") "extra attributes are kept")
      (assert (< (at extra "height=") (at extra "fill=")) "extra attributes follow the geometry")
      true))
