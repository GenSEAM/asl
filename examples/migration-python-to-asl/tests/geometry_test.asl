(module migration-geometry/geometry-test
  :d "Unit tests for migrated geometric functions asserting parity with Python baseline."
  :x [test-euclidean-distance test-batch-closest-point run-tests]
  :i [(geometry :a geo)])

(df test-euclidean-distance [] -> Bool
  :d "Verifies Euclidean distance between (0,0) and (3,4) equals 5.0."
  (let [(p1 (geo/Point2D :x 0.0 :y 0.0))
        (p2 (geo/Point2D :x 3.0 :y 4.0))
        (dist (geo/euclidean-distance p1 p2))]
    (assert (= dist 5.0) "Distance must equal 5.0")
    true))

(df test-batch-closest-point [] -> Bool
  :d "Verifies batch closest point selector finds nearest neighbor."
  (let [(target (geo/Point2D :x 10.0 :y 10.0))
        (p1 (geo/Point2D :x 100.0 :y 100.0))
        (p2 (geo/Point2D :x 11.0 :y 10.0))
        (p3 (geo/Point2D :x 50.0 :y 50.0))
        (pts (list p1 p2 p3))
        (closest (geo/batch-closest-point target pts))]
    (assert (= (.-x closest) 11.0) "Closest point x must equal 11.0")
    (assert (= (.-y closest) 10.0) "Closest point y must equal 10.0")
    true))

(df run-tests [] -> Bool
  :d "Runs all geometry tests"
  (do
    (assert (test-euclidean-distance) "test-euclidean-distance must pass")
    (assert (test-batch-closest-point) "test-batch-closest-point must pass")
    true))
