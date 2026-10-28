(module asl/tools/coord/tests/qualityTest
  :x [runTests]
  :i [(asl-tools/coord/quality :a q)])

fn cell alias: String place: String passes: Int64 total: Int64 -> q/Cell
  (q/Cell :alias alias :place place :passes passes :total total)

fn lie alias: String place: String -> q/Lie
  (q/Lie :alias alias :place place)

fn cells -> (List q/Cell)
  (list (cell "e" "code" 6 18) (cell "c" "code" 15 18) (cell "a" "code" 18 18) (cell "d" "code" 14 18)
        (cell "b" "code" 17 18) (cell "z" "grade" 18 18))

fn line r: q/Ranked -> String
  (str r.alias ":" r.quality ":" r.class)

fn show rs: (List q/Ranked) -> String
  (fold (fn [(acc String) (r q/Ranked)] -> String (str acc (line r) ";")) "" rs)

fn testQuality -> Bool
  (do (assert (= (q/qualityOf 18 18 0) 1000) "all passes is 1000")
      (assert (= (q/qualityOf 17 18 0) 944) "17 of 18 is 944")
      (assert (= (q/qualityOf 17 18 2) 844) "each lie costs 50")
      (assert (= (q/qualityOf 1 18 5) 0) "quality floors at 0")
      (assert (= (q/qualityOf 0 0 0) 0) "no data is 0")
      (assert (= (q/spreadPermille 2 18) 111) "2 passes of 18 is 111 permille")
      true)

fn testClasses -> Bool
  (do (assert (= (show (q/rankPlace "code" (cells) (list) 2)) "a:1000:1;b:944:1;c:833:2;d:777:2;e:333:3;") "within the spread one class, outside it rank, place filtered")
      (assert (= (show (q/rankPlace "grade" (cells) (list) 2)) "z:1000:1;") "other places are separate")
      (assert (= (show (q/rankPlace "none" (cells) (list) 2)) "") "an unknown place ranks nothing")
      (assert (= (show (q/rankPlace "code" (cells) (list) 0)) "a:1000:1;b:944:2;c:833:3;d:777:4;e:333:5;") "no spread: every lane is its own class")
      (assert (= (show (q/rankPlace "code" (cells) (list) 18)) "a:1000:1;b:944:1;c:833:1;d:777:1;e:333:1;") "a spread of the whole range is one class")
      true)

fn testLies -> Bool
  (let [(ls (list (lie "b" "code") (lie "b" "code") (lie "a" "grade")))]
    (do (assert (= (show (q/rankPlace "code" (cells) ls 2)) "a:1000:1;b:844:2;c:833:2;d:777:2;e:333:3;") "two lies drop b out of the leading class; other places' lies do not count")
        true))

fn ! runTests -> Bool
  (do (assert (testQuality) "quality")
      (assert (testClasses) "classes")
      (assert (testLies) "lies")
      true)
