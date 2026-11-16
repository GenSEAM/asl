(module asl-know/scanEnumTest
  :x [runTests]
  :i [(asl-know/scan :a sc)])

fn has m: sc/Module name: String -> Bool
  (mapHas? m.decls name)

fn ownerOf m: sc/Module name: String -> String
  (match (mapGet m.decls name) ((some d) d.owner) ((none) "-"))

fn ! runTests -> Bool
  (let [(one (sc/moduleOf "a.asl" "(module a\n  :x [Space xs sm]\n  :i [])\n\nenum Space (xs) (sm)\n"))
        (nest (sc/moduleOf "a.asl" "(module a\n  :x [F broken]\n  :i [])\n\nenum F (broken found: (List P)) (inert id: String)\n"))
        (both (sc/moduleOf "a.asl" "(module a\n  :x [G a b c]\n  :i [])\n\nenum G (a) (b)\n  (c x: Int64)\n  (b)\n"))
        (block (sc/moduleOf "a.asl" "(module a\n  :x [H p q]\n  :i [])\n\nenum H\n  (p)\n  (q)\n"))]
    (do
      (assert (and (has one "xs") (has one "sm")) "enum Space (xs) (sm) on one line yields xs and sm")
      (assert (= (ownerOf one "xs") "Space") "a head-line constructor names its enum as owner")
      (assert (and (has nest "broken") (has nest "inert") (not (has nest "List"))) "a field type in parentheses is not a constructor")
      (assert (and (has both "a") (has both "b") (has both "c")) "head-line and following-line constructors are all yielded")
      (assert (= (mapSize both.decls) 4) "a constructor named on both lines is yielded once: G, a, b, c")
      (assert (and (has block "p") (has block "q") (= (mapSize block.decls) 3)) "an enum with constructors only on following lines is unchanged")
      true))
