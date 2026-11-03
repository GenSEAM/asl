(module asl-text/tests/padTest
  :x [runTests]
  :i [(asl-text/pad :a p)])

fn runTests -> Bool
  (do
    (assert (= (p/padStart "abc" 5 " ") "  abc") "padStart ascii")
    (assert (= (p/padStart "абв" 5 " ") "  абв") "padStart cyrillic")
    (assert (= (p/padEnd "abc" 5 " ") "abc  ") "padEnd ascii")
    (assert (= (p/center "abc" 6 " ") " abc  ") "center ascii")
    (assert (= (p/truncate "abcdef" 4 "...") "a...") "truncate")
    (assert (= (p/truncate "abcdef" 4 "") "abcd") "truncate empty marker")
    (assert (= (p/truncate "abc" 5 "...") "abc") "truncate width > len")
    (assert (= (p/truncate "abcdef" 2 "...") "..") "truncate marker > width")
    true)