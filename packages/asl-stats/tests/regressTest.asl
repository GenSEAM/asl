(module asl-stats/tests/regressTest
  :x [runTests]
  :i [(asl-stats/regress :a r)])

; (:m :ref NUM-REGRESSION-MODELS :do "oracle: every reference constant below was produced by a throwaway python3 script kept outside the tree (numpy 2.4.1 float64 and scipy 1.17.0): beta = inv(XtX) Xty by np.linalg.inv, classical cov = RSS/(n-k) inv(XtX), HC1 = n/(n-k) B (Xt diag(e^2) X) B, CR1 = G/(G-1) (n-1)/(n-k) B (sum_g s_g s_g^T) B with s_g = Xt_g e_g, p = 2 scipy.stats.t.sf(|t|, df) with df n-k or G-1; logit by 100 full Newton steps from zero to |step| < 1e-15, cov = inv(XtWX), clustered cov with the same CR1 factor on scores Xt_g(y-p), p = 2 scipy.stats.norm.sf(|z|); printed with %.17g and pasted here")
fn arr xs: (List Float64) -> F64Array
  (f64ArrayConcat (map (fn [(x Float64)] -> F64Array (f64ArrayGenerate 1 (fn [(i Int64)] -> Float64 x))) xs))

fn ids xs: (List Int64) -> I64Array
  (i64ArrayConcat (map (fn [(v Int64)] -> I64Array (i64ArrayGenerate 1 (fn [(i Int64)] -> Int64 v))) xs))

fn rel? a: Float64 b: Float64 eps: Float64 -> Bool
  (<= (abs (- a b)) (* eps (max 1.0e-300 (abs b))))

fn relAll? a: F64Array want: (List Float64) eps: Float64 -> Bool
  (let [(w (arr want))]
    (and (= (f64ArrayLen a) (f64ArrayLen w))
         (f64ArrayFold (fn [(ok Bool) (v Float64)] -> Bool ok) true a)
         (relAllLoop! a w 0 eps)))

fn ! relAllLoop! a: F64Array w: F64Array i: Int64 eps: Float64 -> Bool
  (if (>= i (f64ArrayLen a)) true
    (if (rel? (f64ArrayGet a i) (f64ArrayGet w i) eps) (relAllLoop! a w (+ i 1) eps) false))

fn errHas? res: (Result r/Ols String) key: String -> Bool
  (match res
    ((err e) (stringContains? e key))
    ((ok v) false))

fn logitErrHas? res: (Result r/Logit String) key: String -> Bool
  (match res
    ((err e) (stringContains? e key))
    ((ok v) false))

fn zeroOls -> r/Ols
  (r/Ols :coef (arr (list)) :residuals (arr (list)) :rss -1.0 :rSquared -1.0 :n -1 :k -1 :df -1.0 :cov (arr (list)) :se (arr (list)) :tStat (arr (list)) :pValue (arr (list)) :covKind "" :clusters -1 :warning "none")

fn fit res: (Result r/Ols String) -> r/Ols
  (match res
    ((err e) (zeroOls))
    ((ok v) v))

fn zeroLogit -> r/Logit
  (r/Logit :coef (arr (list)) :cov (arr (list)) :se (arr (list)) :zStat (arr (list)) :pValue (arr (list)) :logLik 1.0 :iterations -1 :converged false :n -1 :k -1 :covKind "" :clusters -1 :warning "none")

fn lfit res: (Result r/Logit String) -> r/Logit
  (match res
    ((err e) (zeroLogit))
    ((ok v) v))

; (:m :ref NUM-REGRESSION-MODELS :do "design: n=12 rows, columns 1, x1 = 1..12, x2 given, y given; clusters 7,7,7,7,3,3,3,9,9,5,5,5 (G=4, unbalanced, ids not contiguous)")
fn x1 -> (List Float64)
  (list 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0)

fn x2 -> (List Float64)
  (list 2.1 0.5 3.3 1.7 4.8 2.2 0.9 5.1 3.6 1.1 4.4 2.8)

fn yv -> (List Float64)
  (list 3.2 2.9 6.1 5.8 9.7 8.1 6.6 13.2 11.0 9.4 14.9 12.3)

fn clv -> (List Int64)
  (list 7 7 7 7 3 3 3 9 9 5 5 5)

fn ones12 -> (List Float64)
  (list 1.0 1.0 1.0 1.0 1.0 1.0 1.0 1.0 1.0 1.0 1.0 1.0)

fn rowMajor3 a: (List Float64) b: (List Float64) c: (List Float64) -> F64Array
  (let [(aa (arr a)) (bb (arr b)) (cc (arr c))]
    (f64ArrayGenerate 36 (fn [(p Int64)] -> Float64
      (let [(col (mod p 3)) (row (/ p 3))]
        (if (= col 0) (f64ArrayGet aa row) (if (= col 1) (f64ArrayGet bb row) (f64ArrayGet cc row)))))))

fn design -> F64Array
  (rowMajor3 (ones12) (x1) (x2))

fn okCl -> I64Array
  (ids (clv))

fn noCl -> I64Array
  (ids (list))

; (:m :ref NUM-REGRESSION-MODELS :do "logit data: n=20, columns 1, lx, lz; lcl is five clusters of four")
fn lx -> (List Float64)
  (list 0.5 1.2 -0.3 2.1 0.8 -1.5 1.9 0.1 -0.8 2.6 1.4 -0.2 0.9 -1.1 1.7 0.4 2.2 -0.6 1.0 -1.9)

fn lz -> (List Float64)
  (list 1.0 0.0 1.0 1.0 0.0 0.0 1.0 1.0 0.0 1.0 0.0 0.0 1.0 0.0 1.0 0.0 0.0 1.0 1.0 0.0)

fn ly -> F64Array
  (arr (list 0.0 1.0 0.0 1.0 1.0 0.0 1.0 0.0 0.0 1.0 0.0 1.0 1.0 0.0 1.0 0.0 1.0 1.0 0.0 0.0))

fn lcl -> I64Array
  (ids (list 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5))

fn ldesign -> F64Array
  (let [(a (arr (lx))) (b (arr (lz)))]
    (f64ArrayGenerate 60 (fn [(p Int64)] -> Float64
      (let [(col (mod p 3)) (row (/ p 3))]
        (if (= col 0) 1.0 (if (= col 1) (f64ArrayGet a row) (f64ArrayGet b row)))))))

fn ! olsTests -> Bool
  (let [(cls (fit (r/ols 12 3 (design) (arr (yv)) "classical" (noCl))))
        (hc (fit (r/ols 12 3 (design) (arr (yv)) "hc1" (noCl))))
        (cr (fit (r/ols 12 3 (design) (arr (yv)) "cr1" (okCl))))
        (exact (fit (r/olsClassical 12 3 (design) (f64ArrayGenerate 12 (fn [(i Int64)] -> Float64 (+ 1.1 (+ (* 2.0 (f64ArrayGet (design) (+ (* 3 i) 1))) (* 0.5 (f64ArrayGet (design) (+ (* 3 i) 2))))))))))
        (nc (fit (r/ols 12 2 (rowMajor2) (arr (yv)) "classical" (noCl))))
        (few (fit (r/ols 12 3 (design) (arr (yv)) "cr1" (ids (list 1 1 1 1 2 2 2 2 3 3 3 3)))))
        (two (r/ols 12 3 (design) (arr (yv)) "cr1" (ids (list 1 1 1 1 1 1 2 2 2 2 2 2))))
        (col3 (f64ArrayGenerate 36 (fn [(p Int64)] -> Float64 (if (= (mod p 3) 2) (* 2.0 (f64ArrayGet (design) (- p 1))) (f64ArrayGet (design) p)))))]
    (do
      (assert (relAll? cls.coef (list 0.27512763316517708 0.77624161031736161 1.2108191629927265) 1.0e-9) "classical coefficients vs oracle")
      (assert (and (rel? cls.rss 2.8339635699754901 1.0e-9) (rel? cls.rSquared 0.98252150259050519 1.0e-10)) "rss and centred R2 vs oracle")
      (assert (and (= cls.n 12) (= cls.k 3) (= cls.df 9.0) (= cls.clusters 0) (= cls.covKind "classical") (= cls.warning "")) "classical metadata, df n-k = 9")
      (assert (relAll? cls.se (list 0.40654644288384206 0.049135232717681131 0.11416339835032582) 1.0e-8) "classical se vs oracle")
      (assert (relAll? cls.tStat (list 0.67674342742628846 15.798065204604882 10.606018921030751) 1.0e-8) "classical t vs oracle")
      (assert (relAll? cls.pValue (list 0.51558340168494332 7.1858892020703947e-08 2.1881491575547648e-06) 1.0e-8) "classical p (t, df 9) vs oracle")
      (assert (relAll? hc.se (list 0.39374246681617781 0.050395991181772931 0.094500718256302726) 1.0e-8) "HC1 se vs oracle")
      (assert (relAll? hc.pValue (list 0.50236345887212419 8.9597201918880869e-08 4.3975810457547839e-07) 1.0e-8) "HC1 p (t, df 9) vs oracle")
      (assert (relAll? cr.se (list 0.15066603278187196 0.02476963077651036 0.11584670083709649) 1.0e-8) "CR1 se vs oracle (factor G/(G-1)(n-1)/(n-k))")
      (assert (relAll? cr.tStat (list 1.8260760443828468 31.338440904556812 10.451908895492666) 1.0e-8) "CR1 t vs oracle")
      (assert (relAll? cr.pValue (list 0.1653152856135697 7.1391895873862448e-05 0.0018696232942032951) 1.0e-8) "CR1 p uses t with G-1 = 3 df")
      (assert (and (= cr.clusters 4) (= cr.df 3.0) (= cr.warning "") (= cr.covKind "cr1")) "CR1 reports G = 4 and df 3, no warning")
      (assert (relAll? cr.cov (list 0.022700253434228119 0.003504789651332098 -0.017222999825760959 0.0035047896513320954 0.00061353460880464927 -0.002813605146758792 -0.017222999825760948 -0.0028136051467587933 0.013420458094839731) 1.0e-8) "CR1 covariance matrix vs oracle")
      (assert (and (< (abs (f64ArraySum cls.residuals)) 1.0e-10) (= (f64ArrayLen cls.residuals) 12)) "residuals of a model with intercept sum to 0")
      (assert (and (< exact.rss 1.0e-20) (rel? (f64ArrayGet exact.coef 0) 1.1 1.0e-9) (rel? (f64ArrayGet exact.coef 1) 2.0 1.0e-9) (rel? (f64ArrayGet exact.coef 2) 0.5 1.0e-9) (> exact.rSquared 0.9999999999)) "exact fit y = 1.1 + 2 x1 + 0.5 x2 recovers coefficients with rss ~ 0")
      (assert (and (relAll? nc.coef (list 0.79486513872135089 1.2515802171290704) 1.0e-9) (rel? nc.rSquared 0.99716272406847717 1.0e-10)) "no constant column: uncentred R2 vs oracle")
      (assert (errHas? (r/ols 12 3 (rowMajor3 (ones12) (x1) (x1)) (arr (yv)) "classical" (noCl)) "regressRankDeficient") "collinear column is an explicit error")
      (assert (errHas? (r/ols 12 3 col3 (arr (yv)) "classical" (noCl)) "rank 2 of 3") "the error names the rank")
      (assert (errHas? (r/ols 12 3 (design) (arr (yv)) "cr1" (ids (list 5 5 5 5 5 5 5 5 5 5 5 5))) "regressClusters") "all rows in one cluster is an error")
      (assert (and (> (f64ArrayLen few.coef) 0) (stringContains? few.warning "clusterCountBelowParams") (= few.clusters 3)) "G = k = 3 gives a warning field, not an error")
      (assert (and (match two ((ok v) (and (stringContains? v.warning "clusterCountBelowParams") (= v.df 1.0))) ((err e) false))) "G = 2 < k warns and uses df G-1 = 1")
      (assert (errHas? (r/ols 3 3 (arr (list 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0)) (arr (list 1.0 2.0 3.0)) "classical" (noCl)) "regressShape") "n = k is an error")
      (assert (errHas? (r/ols 2 3 (arr (list 1.0 0.0 0.0 0.0 1.0 0.0)) (arr (list 1.0 2.0)) "classical" (noCl)) "regressShape") "n < k is an error")
      (assert (errHas? (r/ols 12 3 (design) (arr (yv)) "bogus" (noCl)) "regressKind") "unknown covariance kind")
      (assert (errHas? (r/ols 12 3 (design) (arr (yv)) "cr1" (ids (list 1 2 3))) "regressShape") "cluster id count must be n")
      (assert (errHas? (r/ols 12 3 (design) (arr (list 3.2 2.9 6.1 5.8 9.7 8.1 6.6 13.2 11.0 9.4 14.9 (/ 0.0 0.0))) "classical" (noCl)) "regressNonFinite") "NaN in y")
      true))

fn rowMajor2 -> F64Array
  (let [(a (arr (x1))) (b (arr (x2)))]
    (f64ArrayGenerate 24 (fn [(p Int64)] -> Float64 (if (= (mod p 2) 0) (f64ArrayGet a (/ p 2)) (f64ArrayGet b (/ p 2))))))

fn ! logitTests -> Bool
  (let [(c (lfit (r/logit 20 3 (ldesign) (ly))))
        (k (lfit (r/logitCluster 20 3 (ldesign) (ly) (lcl))))
        (far (lfit (r/logitWith 20 3 (ldesign) (ly) "classical" (noCl) (arr (list 6.0 -6.0 5.0)) 100 30)))
        (nohalf (r/logitWith 20 3 (ldesign) (ly) "classical" (noCl) (arr (list 6.0 -6.0 5.0)) 100 0))
        (sepX (arr (list 1.0 1.0 1.0 2.0 1.0 3.0 1.0 4.0 1.0 5.0 1.0 6.0)))
        (quasiX (arr (list 1.0 1.0 1.0 2.0 1.0 3.0 1.0 3.0 1.0 4.0 1.0 5.0)))]
    (do
      (assert (relAll? c.coef (list -0.71967494069200766 1.2971221702618811 -0.0013921942562963321) 1.0e-6) "logit coefficients vs oracle")
      (assert (rel? c.logLik -9.8371221519927836 1.0e-8) "logit log-likelihood vs oracle")
      (assert (and c.converged (>= c.iterations 3) (<= c.iterations 15) (= c.covKind "classical") (= c.clusters 0)) "logit converges by Newton in a handful of steps")
      (assert (relAll? c.se (list 0.85084915829752927 0.59057678942754332 1.1359520343530447) 1.0e-6) "logit se vs oracle")
      (assert (relAll? c.zStat (list -0.84583140698171566 2.1963649663902385 -0.0012255748607283617) 1.0e-6) "logit z vs oracle")
      (assert (relAll? c.pValue (list 0.3976468020817151 0.028065831118027056 0.99902213298531495) 1.0e-6) "logit normal p vs oracle")
      (assert (and k.converged (= k.clusters 5) (= k.covKind "cr1") (= k.warning "")) "clustered logit metadata")
      (assert (relAll? k.coef (list -0.71967494069200766 1.2971221702618811 -0.0013921942562963321) 1.0e-6) "clustered logit has the same coefficients")
      (assert (relAll? k.se (list 0.58024270352917573 0.71591952822057536 1.2707026613052412) 1.0e-6) "clustered logit se vs oracle (CR1 factor)")
      (assert (relAll? k.pValue (list 0.21486450625998743 0.070012966523905054 0.99912583005109357) 1.0e-6) "clustered logit p (normal) vs oracle")
      (assert (and far.converged (relAll? far.coef (list -0.71967494069200766 1.2971221702618811 -0.0013921942562963321) 1.0e-6)) "from a far start (full step lowers ll from -112 to -1496) step halving still reaches the oracle")
      (assert (match nohalf ((ok v) (not v.converged)) ((err e) true)) "without halving the same start does not converge (the halving is load bearing)")
      (assert (logitErrHas? (r/logit 6 2 sepX (arr (list 0.0 0.0 0.0 1.0 1.0 1.0))) "logitSeparation") "complete separation is reported")
      (assert (logitErrHas? (r/logit 6 2 quasiX (arr (list 0.0 0.0 0.0 1.0 1.0 1.0))) "logitSeparation") "quasi-complete separation is reported")
      (assert (logitErrHas? (r/logit 6 2 sepX (arr (list 0.0 0.0 0.0 1.0 1.0 2.0))) "logitResponse") "y = 2 is an error")
      (assert (logitErrHas? (r/logit 6 2 sepX (arr (list 0.0 0.0 0.0 1.0 1.0 0.5))) "logitResponse") "y = 0.5 is an error")
      (assert (logitErrHas? (r/logit 2 3 (arr (list 1.0 0.0 0.0 1.0 1.0 0.0)) (arr (list 0.0 1.0))) "regressShape") "n <= k")
      (assert (logitErrHas? (r/logit 6 2 sepX (arr (list 1.0 1.0 1.0 1.0 1.0 1.0))) "logitSeparation") "all ones is separation")
      (assert (logitErrHas? (r/logitCluster 20 3 (ldesign) (ly) (ids (list 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1))) "regressClusters") "logit one cluster is an error")
      (assert (logitErrHas? (r/logit 8 2 (arr (list 1.0 2.0 1.0 2.0 1.0 2.0 1.0 2.0 1.0 2.0 1.0 2.0 1.0 2.0 1.0 2.0)) (arr (list 0.0 1.0 0.0 0.0 1.0 1.0 0.0 1.0))) "logitSingular") "constant-column duplicate is singular")
      true))

fn ! runTests -> Bool
  (do (assert (olsTests) "ols group")
      (assert (logitTests) "logit group")
      (assert (robustTests) "robustness group")
      true)


; (:m :ref NUM-REGRESSION-MODELS :do "large-eta data without separation, oracle numpy Newton to 1e-14: gen i = 0..n-1, x_i = (i*104729 mod 2003)/2003*range - range/2 (row n-1 replaced by 40 in case B), u_i = ((i*7919+13) mod 10007)/10007, y_i = 1 if u_i < sigmoid(slope*x_i); case A n=2000 slope 12 range 8 (max |eta| 45.0, beta 6.781422560441995e-05 and 11.253975623553742, se 0.21201774793164746 and 1.3160211413137277), case B n=300 slope 1.5 range 4 one outlier x=40 (max |eta| 55.8, beta -0.028169656597728313 and 1.3969127908030301, se 0.14547758324780299 and 0.15660332531702587); R2 of two dummies summing to one: centred 2.0558365198763973e-05")
fn xAt i: Int64 rng: Float64 last: Float64 n: Int64 -> Float64
  (if (and (= i (- n 1)) (> last 0.0)) last
    (- (* (/ (int64ToFloat64 (mod (* i 104729) 2003)) 2003.0) rng) (/ rng 2.0)))

fn ! bigDesign n: Int64 rng: Float64 last: Float64 -> F64Array
  (f64ArrayGenerate (* 2 n) (fn [(p Int64)] -> Float64 (if (= (mod p 2) 0) 1.0 (xAt (/ p 2) rng last n))))

fn ! bigY n: Int64 slope: Float64 rng: Float64 last: Float64 -> F64Array
  (f64ArrayGenerate n (fn [(i Int64)] -> Float64
    (let [(u (/ (int64ToFloat64 (mod (+ (* i 7919) 13) 10007)) 10007.0))
          (pr (/ 1.0 (+ 1.0 (exp (- 0.0 (* slope (xAt i rng last n)))))))]
      (if (< u pr) 1.0 0.0))))

fn ! scaled3 s0: Float64 s1: Float64 s2: Float64 -> F64Array
  (let [(d (design))]
    (f64ArrayGenerate 36 (fn [(p Int64)] -> Float64 (* (f64ArrayGet d p) (if (= (mod p 3) 0) s0 (if (= (mod p 3) 1) s1 s2))))))

fn ! robustTests -> Bool
  (let [(a (lfit (r/logit 2000 2 (bigDesign 2000 8.0 0.0) (bigY 2000 12.0 8.0 0.0))))
        (b (lfit (r/logit 300 2 (bigDesign 300 4.0 40.0) (bigY 300 1.5 4.0 40.0))))
        (aStart (lfit (r/logitWith 2000 2 (bigDesign 2000 8.0 0.0) (bigY 2000 12.0 8.0 0.0) "classical" (noCl) (arr (list 6.781422560441995e-05 11.253975623553742)) 100 30)))
        (sc (fit (r/ols 12 3 (scaled3 1.0e-8 1.0 1.0e8) (arr (yv)) "classical" (noCl))))
        (sc1 (fit (r/ols 12 3 (scaled3 1.0e-8 1.0 1.0e8) (arr (yv)) "cr1" (okCl))))
        (lsc (lfit (r/logit 20 3 (ldesign) (ly))))
        (lsc2 (lfit (r/logitWith 20 3 (f64ArrayGenerate 60 (fn [(p Int64)] -> Float64 (* (f64ArrayGet (ldesign) p) (if (= (mod p 3) 0) 1.0e-7 (if (= (mod p 3) 1) 1.0 1.0e7))))) (ly) "classical" (noCl) (arr (list 0.0 0.0 0.0)) 100 30)))
        (few (lfit (r/logitWith 20 3 (ldesign) (ly) "classical" (noCl) (arr (list 0.0 0.0 0.0)) 2 30)))
        (cy (fit (r/ols 12 3 (design) (arr (list 5.0 5.0 5.0 5.0 5.0 5.0 5.0 5.0 5.0 5.0 5.0 5.0)) "classical" (noCl))))
        (dum (fit (r/ols 12 2 (dummies) (arr (yv)) "classical" (noCl))))
        (nearX (nearDesign))
        (cls0 (fit (r/ols 12 3 (design) (arr (yv)) "classical" (noCl))))
        (near (fit (r/ols 12 3 nearX (arr (yv)) "classical" (noCl))))]
    (do
      (assert (and a.converged (relAll? a.coef (list 6.781422560441995e-05 11.253975623553742) 1.0e-7) (relAll? a.se (list 0.21201774793164746 1.3160211413137277) 1.0e-7)) "slope 12, n=2000, max|eta| 45 without separation: converges to the oracle (was a false logitSeparation)")
      (assert (and b.converged (relAll? b.coef (list -0.028169656597728313 1.3969127908030301) 1.0e-7) (relAll? b.se (list 0.14547758324780299 0.15660332531702587) 1.0e-7)) "one outlier x = 40, max|eta| 56: converges to the oracle")
      (assert (and aStart.converged (<= aStart.iterations 3)) "started at the MLE the large-eta fit stops at once")
      (assert (relAll? sc.coef (list 27512763.316517708 0.77624161031736161 1.2108191629927265e-08) 1.0e-8) "columns of order 1e-8, 1 and 1e8: no false rank error and coefficients scale back")
      (assert (and (relAll? sc.tStat (list 0.67674342742628846 15.798065204604882 10.606018921030751) 1.0e-8) (relAll? sc1.pValue (list 0.1653152856135697 7.1391895873862448e-05 0.0018696232942032951) 1.0e-8)) "t and clustered p are invariant to column scale")
      (assert (relAll? lsc2.coef (list -0.71967494069200766e7 1.2971221702618811 -0.0013921942562963321e-7) 1.0e-6) "logit with columns at 1e-7 and 1e7 scales back")
      (assert (and (not few.converged) (stringContains? few.warning "notConverged") (> (f64ArrayLen few.se) 0)) "maxIter 2 reports notConverged in warning")
      (assert (and lsc.converged (= lsc.warning "")) "a converged logit has no warning")
      (assert (and (not (= cy.rSquared cy.rSquared)) (stringContains? cy.warning "rSquaredUndefined")) "constant y: R2 is NaN and the warning says so")
      (assert (rel? dum.rSquared 2.0558365198763973e-05 1.0e-6) "two dummies summing to one: the constant is in the column space, R2 centred")
      (assert (stringContains? near.warning "illConditioned") "nearly collinear columns (noise 1e-4, rcond about 1e-12) give an illConditioned warning")
      (assert (= cls0.warning "") "well conditioned classical fit has no warning")
      true))

fn nearAt row: Int64 col: Int64 -> Float64
  (let [(t (int64ToFloat64 (+ row 1)))] (if (= col 0) 1.0 (if (= col 1) t (+ t (* 1.0e-4 (sin (* 7.0 t)))))))

fn ! nearDesign -> F64Array
  (f64ArrayGenerate 36 (fn [(p Int64)] -> Float64 (nearAt (/ p 3) (mod p 3))))
fn ! dummies -> F64Array
  (f64ArrayGenerate 24 (fn [(p Int64)] -> Float64 (let [(d1 (if (= (mod (/ p 2) 2) 0) 1.0 0.0))] (if (= (mod p 2) 0) d1 (- 1.0 d1)))))
