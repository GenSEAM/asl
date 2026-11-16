(module asl-stats/regress
  :x [Ols Logit ols olsClassical logit logitCluster logitWith]
  :i [(asl-linalg/qr :a q) (asl-linalg/cholesky :a ch) (asl-linalg/dense :a d) (asl-stats/special :a sp)])

; (:m :ref NUM-REGRESSION-MODELS :do "regression models on a row-major n x k F64Array design X whose intercept column the CALLER supplies (a column of ones; nothing is added); every entry returns (err msg) on shape, finiteness, rank, separation or cluster errors, never traps; covariance is B M B scaled by a small-sample factor with B = (X'X)^-1 (OLS) or the inverse Fisher information (logit) computed on an equilibrated X'X by Cholesky; dependency direction asl-stats -> asl-linalg, never back, because linalg has no use of the t and normal cdfs")
schema Ols
  (:f coef F64Array)
  (:f residuals F64Array)
  (:f rss Float64)
  (:f rSquared Float64)
  (:f n Int64)
  (:f k Int64)
  (:f df Float64)
  (:f cov F64Array)
  (:f se F64Array)
  (:f tStat F64Array)
  (:f pValue F64Array)
  (:f covKind String)
  (:f clusters Int64)
  (:f warning String)

schema Logit
  (:f coef F64Array)
  (:f cov F64Array)
  (:f se F64Array)
  (:f zStat F64Array)
  (:f pValue F64Array)
  (:f logLik Float64)
  (:f iterations Int64)
  (:f converged Bool)
  (:f n Int64)
  (:f k Int64)
  (:f covKind String)
  (:f clusters Int64)
  (:f warning String)

schema LgState
  (:f beta F64Array)
  (:f eta F64Array)
  (:f ll Float64)
  (:f prev Float64)
  (:f move Float64)
  (:f iter Int64)
  (:f converged Bool)

fn cat2 a: String b: String -> String
  (stringConcat a b)

fn sumSq a: F64Array -> Float64
  (f64ArrayFold (fn [(s Float64) (x Float64)] -> Float64 (+ s (* x x))) 0.0 a)

fn ! zeros n: Int64 -> F64Array
  (f64ArrayGenerate n (fn [(i Int64)] -> Float64 0.0))

fn ! gram m: Int64 k: Int64 s: F64Array -> (Result F64Array String)
  (match (d/transpose m k s)
    ((err e) (err e))
    ((ok st) (ok (gemm k k m st s))))

fn ! symmetrize k: Int64 a: F64Array -> F64Array
  (f64ArrayGenerate (* k k) (fn [(p Int64)] -> Float64 (* 0.5 (+ (f64ArrayGet a p) (f64ArrayGet a (+ (* (% p k) k) (/ p k)))))))

fn ! diagPositive! g: F64Array k: Int64 j: Int64 -> Bool
  (if (>= j k) true
    (let [(v (f64ArrayGet g (+ (* j k) j)))]
      (if (and (> v 0.0) (< v 1.0e300)) (diagPositive! g k (+ j 1)) false)))

fn ! writeCol! ib: Bytes k: Int64 j: Int64 col: F64Array sv: F64Array i: Int64 -> Int64
  (if (>= i k) 0
    (do (bytesSetFloat64 ib (+ (* i k) j) (* (* (f64ArrayGet col i) (f64ArrayGet sv i)) (f64ArrayGet sv j)))
        (writeCol! ib k j col sv (+ i 1))))

fn ! invCols! k: Int64 l: F64Array sv: F64Array ib: Bytes j: Int64 -> (Result Bool String)
  (if (>= j k) (ok true)
    (match (ch/choleskySolve k l (f64ArrayGenerate k (fn [(i Int64)] -> Float64 (if (= i j) 1.0 0.0))))
      ((err e) (err e))
      ((ok col) (do (writeCol! ib k j col sv 0) (invCols! k l sv ib (+ j 1))))))

; (:m :ref NUM-REGRESSION-MODELS :do "inverse of a symmetric positive definite k x k matrix: the matrix is first scaled to unit diagonal (D g D, D = diag(1/sqrt(g_jj))), factored by Cholesky, solved against the unit vectors and scaled back, so columns of very different magnitude (an intercept next to a year column) do not trip the pivot test; a non-positive diagonal or a pivot below 1e-13 is the error regressSingular")
fn ! spdInverse k: Int64 g: F64Array -> (Result (Pair F64Array Float64) String)
  (if (not (diagPositive! g k 0))
    (err "regressSingular: information matrix has a non-positive diagonal entry")
    (let [(sv (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (/ 1.0 (sqrt (f64ArrayGet g (+ (* j k) j)))))))
          (gs (f64ArrayGenerate (* k k) (fn [(p Int64)] -> Float64 (* (* (f64ArrayGet g p) (f64ArrayGet sv (/ p k))) (f64ArrayGet sv (% p k))))))]
      (match (ch/choleskyFactor k gs)
        ((err e) (err (cat2 "regressSingular: " e)))
        ((ok l)
          (let [(ib (bytesAlloc (* 8 (* k k))))]
            (match (invCols! k l sv ib 0)
              ((err e) (err (cat2 "regressSingular: " e)))
              ((ok u) (match (ch/choleskyRcond k gs l) ((err e) (err (cat2 "regressSingular: " e))) ((ok rc) (ok (pair (symmetrize k (d/fromBuf ib (* k k))) rc)))))))))))

fn ! indexLoop! cl: I64Array i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m
    (let [(c (i64ArrayGet cl i))]
      (if (>= (mapGetOr m c -1) 0)
        (indexLoop! cl (+ i 1) n m)
        (indexLoop! cl (+ i 1) n (mapSet m c (mapSize m))))))

; (:m :ref NUM-REGRESSION-MODELS :do "cluster ids are any Int64 values, one per row; they are mapped to 0..G-1 and G is returned; fewer than two distinct clusters is the explicit error regressClusters because the cluster-robust variance divides by G-1")
fn ! clusterIndex n: Int64 cl: I64Array -> (Result (Pair I64Array Int64) String)
  (let [(m (indexLoop! cl 0 n (mapEmpty)))
        (g (mapSize m))]
    (if (< g 2)
      (err "regressClusters: need at least two distinct clusters, got one")
      (ok (pair (i64ArrayGenerate n (fn [(i Int64)] -> Int64 (mapGetOr m (i64ArrayGet cl i) 0))) g))))

fn ! zeroFill! b: Bytes i: Int64 len: Int64 -> Int64
  (if (>= i len) 0
    (do (bytesSetFloat64 b i 0.0) (zeroFill! b (+ i 1) len)))

fn ! accRow! sb: Bytes x: F64Array k: Int64 i: Int64 g: Int64 ei: Float64 j: Int64 -> Int64
  (if (>= j k) 0
    (do (bytesSetFloat64 sb (+ (* g k) j) (+ (bytesGetFloat64 sb (+ (* g k) j)) (* ei (f64ArrayGet x (+ (* i k) j)))))
        (accRow! sb x k i g ei (+ j 1))))

fn ! accRows! sb: Bytes x: F64Array e: F64Array idx: I64Array k: Int64 i: Int64 n: Int64 -> Int64
  (if (>= i n) 0
    (do (accRow! sb x k i (i64ArrayGet idx i) (f64ArrayGet e i) 0)
        (accRows! sb x e idx k (+ i 1) n)))

; (:m :ref NUM-REGRESSION-MODELS :do "sandwich covariance c * B M B (for logit too the factor is the OLS one, G/(G-1)*(n-1)/(n-k); Stata logit uses G/(G-1) alone, convert by (n-k)/(n-1) on cov): M = sum over groups of s_g s_g' with s_g the sum of x_i e_i in the group (e = residual for OLS, y - p for logit); hc1 puts every row in its own group with c = n/(n-k); cr1 groups by cluster with c = G/(G-1) * (n-1)/(n-k), the Stata and statsmodels default small-sample factor")
fn ! sandwich! n: Int64 k: Int64 x: F64Array e: F64Array b: F64Array kind: String idx: I64Array g: Int64 -> (Result F64Array String)
  (let [(nf (int64ToFloat64 n))
        (kf (int64ToFloat64 k))
        (gf (int64ToFloat64 g))
        (c (if (= kind "cr1") (* (/ gf (- gf 1.0)) (/ (- nf 1.0) (- nf kf))) (/ nf (- nf kf))))
        (meat (if (= kind "cr1")
                (let [(sb (bytesAlloc (* 8 (* g k))))]
                  (do (zeroFill! sb 0 (* g k))
                      (accRows! sb x e idx k 0 n)
                      (gram g k (d/fromBuf sb (* g k)))))
                (gram n k (f64ArrayGenerate (* n k) (fn [(p Int64)] -> Float64 (* (f64ArrayGet x p) (f64ArrayGet e (/ p k))))))))]
    (match meat
      ((err er) (err er))
      ((ok m)
        (let [(bm (gemm k k k (gemm k k k b m) b))]
          (ok (f64ArrayGenerate (* k k) (fn [(p Int64)] -> Float64 (* c (f64ArrayGet bm p)))))))))

fn ! seOf! k: Int64 cov: F64Array -> F64Array
  (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (sqrt (max 0.0 (f64ArrayGet cov (+ (* j k) j))))))

fn ! statOf coef: Float64 se: Float64 -> Float64
  (cond
    ((> se 0.0) (/ coef se))
    ((= coef 0.0) 0.0)
    ((> coef 0.0) 1.0e300)
    (else -1.0e300))

fn ! pOfT coef: Float64 se: Float64 df: Float64 -> Float64
  (if (> se 0.0)
    (min 1.0 (* 2.0 (sp/studentCdf (- 0.0 (abs (/ coef se))) df)))
    (if (= coef 0.0) 1.0 0.0))

fn ! pOfZ coef: Float64 se: Float64 -> Float64
  (if (> se 0.0)
    (min 1.0 (* 2.0 (sp/normalSurvival (abs (/ coef se)))))
    (if (= coef 0.0) 1.0 0.0))

; (:m :ref NUM-REGRESSION-MODELS :do "a model has a constant when the ones vector lies in the column space of X (least squares residual of ones on X below 1e-9*sqrt(n)), so two dummies summing to one count; R2 is then centred; columns are scaled to unit Euclidean norm before the rank decision, the fit and the inverse, and coefficients, covariance and standard errors are scaled back, so columns of order 1e-8 and 1e8 mix; a zero column keeps scale 1 and is reported as rank deficiency")
fn ! onesInSpan! n: Int64 k: Int64 x: F64Array -> Bool
  (match (q/lstsq n k x (f64ArrayGenerate n (fn [(i Int64)] -> Float64 1.0)))
    ((err e) false)
    ((ok f) (<= f.residualNorm (* 1.0e-9 (sqrt (int64ToFloat64 n))))))

fn ! colSS! x: F64Array n: Int64 k: Int64 j: Int64 i: Int64 acc: Float64 -> Float64
  (if (>= i n) acc
    (colSS! x n k j (+ i 1) (+ acc (* (f64ArrayGet x (+ (* i k) j)) (f64ArrayGet x (+ (* i k) j))))))

fn ! colNorms! n: Int64 k: Int64 x: F64Array -> F64Array
  (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (let [(s (sqrt (colSS! x n k j 0 0.0)))] (if (> s 0.0) s 1.0))))

fn ! scaleCols! n: Int64 k: Int64 x: F64Array c: F64Array -> F64Array
  (f64ArrayGenerate (* n k) (fn [(p Int64)] -> Float64 (/ (f64ArrayGet x p) (f64ArrayGet c (% p k)))))

fn ! olsScaled! n: Int64 k: Int64 x: F64Array y: F64Array kind: String cl: I64Array -> (Result Ols String)
  (let [(c (colNorms! n k x))]
    (match (olsFit! n k (scaleCols! n k x c) y kind cl)
      ((err e) (err e))
      ((ok o)
        (ok (Ols :coef (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (/ (f64ArrayGet o.coef j) (f64ArrayGet c j))))
                 :residuals o.residuals :rss o.rss :rSquared o.rSquared :n o.n :k o.k :df o.df
                 :cov (f64ArrayGenerate (* k k) (fn [(p Int64)] -> Float64 (/ (f64ArrayGet o.cov p) (* (f64ArrayGet c (/ p k)) (f64ArrayGet c (% p k))))))
                 :se (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (/ (f64ArrayGet o.se j) (f64ArrayGet c j))))
                 :tStat o.tStat :pValue o.pValue :covKind o.covKind :clusters o.clusters :warning o.warning)))))

fn joinW a: String b: String -> String
  (cond
    ((= a "") b)
    ((= b "") a)
    (else (cat2 a (cat2 "; " b))))

fn illWarn rc: Float64 -> String
  (if (< rc 1.0e-8)
    (cat2 "illConditioned: reciprocal condition of the unit-diagonal information matrix is " (cat2 (stringFromFloat64 rc) ", standard errors may have fewer than 8 correct digits"))
    "")

fn sepMsg -> String
  "logitSeparation: the log-likelihood has stopped improving while the coefficients keep moving and some fitted probabilities are within 1e-4 of 0 or 1, complete or quasi-complete separation, coefficients would diverge"

fn ! singMsg eta: F64Array e: String -> String
  (if (> (d/maxAbs eta) 10.0) (cat2 "logitSeparation: information matrix became singular with fitted probabilities at 0 or 1, " e) (cat2 "logitSingular: " e))

fn kindOk? kind: String -> Bool
  (or (= kind "classical") (or (= kind "hc1") (= kind "cr1")))

fn warnFor g: Int64 k: Int64 -> String
  (if (<= g k)
    "clusterCountBelowParams: G <= k, the clustered covariance has rank below k and the tests are unreliable"
    "")

; (:m :ref NUM-REGRESSION-MODELS :do "t statistic and two-sided p = 2 P(T <= -|t|) with df n-k (classical, hc1) or G-1 (cr1); a zero standard error gives t = +-1e300 and p = 0 (t = 0 and p = 1 when the coefficient is also 0) instead of a NaN")
fn ! olsFinish! n: Int64 k: Int64 x: F64Array y: F64Array coef: F64Array res: F64Array b: F64Array rc: Float64 kind: String cl: I64Array -> (Result Ols String)
  (let [(rss (sumSq res))
        (nf (int64ToFloat64 n))
        (ymean (/ (f64ArraySum y) nf))
        (yy (sumSq y))
        (tss (if (onesInSpan! n k x) (sumSq (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (- (f64ArrayGet y i) ymean)))) yy))
        (undefined (or (<= tss 0.0) (<= tss (* 1.0e-24 yy))))
        (r2 (if undefined (/ 0.0 0.0) (- 1.0 (/ rss tss))))
        (w0 (joinW (illWarn rc) (if undefined "rSquaredUndefined: y is constant or zero, R2 is NaN and t and p are rounding noise" (if (<= rss (* 1.0e-24 tss)) "exactFit: rss is zero to rounding, standard errors, t and p are unreliable" ""))))]
    (if (= kind "classical")
      (let [(s2 (/ rss (int64ToFloat64 (- n k))))
            (cov (f64ArrayGenerate (* k k) (fn [(p Int64)] -> Float64 (* s2 (f64ArrayGet b p)))))]
        (ok (olsPack! n k coef res rss r2 (int64ToFloat64 (- n k)) cov kind 0 w0)))
      (if (= kind "hc1")
        (match (sandwich! n k x res b kind cl 0)
          ((err e) (err e))
          ((ok cov) (ok (olsPack! n k coef res rss r2 (int64ToFloat64 (- n k)) cov kind 0 w0))))
        (match (clusterIndex n cl)
          ((err e) (err e))
          ((ok pr)
            (match (sandwich! n k x res b kind (pairFirst pr) (pairSecond pr))
              ((err e) (err e))
              ((ok cov) (ok (olsPack! n k coef res rss r2 (int64ToFloat64 (- (pairSecond pr) 1)) cov kind (pairSecond pr) (joinW w0 (warnFor (pairSecond pr) k)))))))))))

fn ! olsPack! n: Int64 k: Int64 coef: F64Array res: F64Array rss: Float64 r2: Float64 df: Float64 cov: F64Array kind: String g: Int64 warn: String -> Ols
  (let [(se (seOf! k cov))]
    (Ols :coef coef :residuals res :rss rss :rSquared r2 :n n :k k :df df :cov cov :se se
         :tStat (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (statOf (f64ArrayGet coef j) (f64ArrayGet se j))))
         :pValue (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (pOfT (f64ArrayGet coef j) (f64ArrayGet se j) df)))
         :covKind kind :clusters g :warning warn))

fn ! olsFit! n: Int64 k: Int64 x: F64Array y: F64Array kind: String cl: I64Array -> (Result Ols String)
  (match (q/lstsq n k x y)
    ((err e) (err e))
    ((ok f)
      (if (< f.rank k)
        (err (cat2 "regressRankDeficient: design has rank " (cat2 (stringFromInt64 f.rank) (cat2 " of " (cat2 (stringFromInt64 k) " columns; drop or combine collinear columns")))))
        (let [(fitted (gemm n 1 k x f.coef))
              (res (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (- (f64ArrayGet y i) (f64ArrayGet fitted i)))))]
          (match (gram n k x)
            ((err e) (err e))
            ((ok g)
              (match (spdInverse k g)
                ((err e) (err e))
                ((ok bp) (olsFinish! n k x y f.coef res (pairFirst bp) (pairSecond bp) kind cl)))))))))

fn ! designError n: Int64 k: Int64 x: F64Array y: F64Array -> String
  (cond
    ((< k 1) "regressShape: k must be at least 1")
    ((<= n k) (cat2 "regressShape: need n > k, got n=" (cat2 (stringFromInt64 n) (cat2 " k=" (stringFromInt64 k)))))
    ((not (= (f64ArrayLen x) (* n k))) "regressShape: X length is not n*k")
    ((not (= (f64ArrayLen y) n)) "regressShape: y length is not n")
    ((not (and (d/allFinite x) (d/allFinite y))) "regressNonFinite: X or y has a NaN or infinite entry")
    (else ""))

; (:m :ref NUM-REGRESSION-MODELS :do "ols: beta by Householder QR with pivoting (lstsq); rank below k is the error regressRankDeficient naming the rank, no basic solution is returned; kind is classical (s2 (X'X)^-1, s2 = RSS/(n-k)), hc1 or cr1; cl holds one Int64 cluster id per row for cr1 and is ignored otherwise; R2 = 1 - RSS/TSS with TSS centred when some column of X is a nonzero constant, uncentred otherwise, and 0 when TSS = 0; cr1 with G <= k sets warning, with one cluster is an error")
fn ! ols n: Int64 k: Int64 x: F64Array y: F64Array kind: String cl: I64Array -> (Result Ols String)
  (let [(bad (designError n k x y))]
    (cond
      ((not (= bad "")) (err bad))
      ((not (kindOk? kind)) (err "regressKind: kind must be classical, hc1 or cr1"))
      ((and (= kind "cr1") (not (= (i64ArrayLen cl) n))) (err "regressShape: cluster id count is not n"))
      (else (olsScaled! n k x y kind cl))))

fn ! olsClassical n: Int64 k: Int64 x: F64Array y: F64Array -> (Result Ols String)
  (ols n k x y "classical" (i64ArrayGenerate 0 (fn [(i Int64)] -> Int64 0)))

; (:m :ref NUM-REGRESSION-MODELS :do "logistic regression by IRLS (Newton on the log-likelihood, canonical link): each step solves I(b) delta = X'(y-p) with I = X'WX by equilibrated Cholesky, then halves the step (at most maxHalve times) while the log-likelihood falls by more than 1e-12*(1+|ll|); converged means max|step| <= 1e-8*(1+max|b|), else maxIter iterations ran and converged is false; separation is decided by behaviour, never by the size of eta (finite MLEs with |eta| of 50 are fits): the error logitSeparation is returned when, after a step, some |eta| > 10 AND the log-likelihood gain is below 1e-9 relative AND the step max-norm is not contracting (above half the previous step) while still above the 1e-8 tolerance, i.e. the likelihood creeps to its supremum while the coefficients keep moving; a singular information matrix with |eta| > 10 is also separation, otherwise logitSingular; a converged fit (step below tolerance, information positive definite) is returned however large eta is, with warning illConditioned when the reciprocal condition of the unit-diagonal information is below 1e-8 and notConverged when maxIter ran out (p-values still returned); y outside {0,1} is the error logitResponse; a response of all 0 or all 1 is separation")
fn ! sigmoid z: Float64 -> Float64
  (/ 1.0 (+ 1.0 (exp (- 0.0 z))))

fn ! softplus z: Float64 -> Float64
  (+ (max z 0.0) (log (+ 1.0 (exp (- 0.0 (abs z))))))

fn ! logLik n: Int64 y: F64Array eta: F64Array -> Float64
  (f64ArraySum (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (- (* (f64ArrayGet y i) (f64ArrayGet eta i)) (softplus (f64ArrayGet eta i))))))

fn ! maxAbsOf! a: F64Array -> Float64
  (d/maxAbs a)

fn ! binary? y: F64Array i: Int64 n: Int64 -> Bool
  (if (>= i n) true
    (let [(v (f64ArrayGet y i))]
      (if (or (= v 0.0) (= v 1.0)) (binary? y (+ i 1) n) false)))

fn ! halve! x: F64Array eta: F64Array xd: F64Array beta: F64Array delta: F64Array y: F64Array n: Int64 k: Int64 ll: Float64 s: Float64 h: Int64 maxHalve: Int64 -> LgState
  (let [(eta2 (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (+ (f64ArrayGet eta i) (* s (f64ArrayGet xd i))))))
        (ll2 (logLik n y eta2))
        (b2 (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (+ (f64ArrayGet beta j) (* s (f64ArrayGet delta j))))))]
    (if (or (not (= ll2 ll2)) (< ll2 (- ll (* 1.0e-12 (+ 1.0 (abs ll))))))
      (if (< h maxHalve)
        (halve! x eta xd beta delta y n k ll (* s 0.5) (+ h 1) maxHalve)
        (LgState :beta beta :eta eta :ll ll :prev ll :move 1.0e300 :iter 0 :converged false))
      (LgState :beta b2 :eta eta2 :ll ll2 :prev ll :move 1.0e300 :iter 0 :converged true)))

fn ! lgLoop! n: Int64 k: Int64 x: F64Array xt: F64Array y: F64Array st: LgState maxIter: Int64 maxHalve: Int64 -> (Result LgState String)
  (cond
    ((>= st.iter maxIter) (ok st))
    (else
      (let [(p (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (sigmoid (f64ArrayGet st.eta i)))))
            (xw (f64ArrayGenerate (* n k) (fn [(q2 Int64)] -> Float64 (let [(pi (f64ArrayGet p (/ q2 k)))] (* (f64ArrayGet x q2) (sqrt (* pi (- 1.0 pi))))))))
            (r (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (- (f64ArrayGet y i) (f64ArrayGet p i)))))
            (grad (gemm k 1 n xt r))]
        (match (gram n k xw)
          ((err e) (err e))
          ((ok fisher)
            (match (spdInverse k fisher)
              ((err e) (err (singMsg st.eta e)))
              ((ok inv)
                (let [(delta (gemm k 1 k (pairFirst inv) grad))
                      (xd (gemm n 1 k x delta))
                      (t (halve! x st.eta xd st.beta delta y n k st.ll 1.0 0 maxHalve))]
                  (if (not t.converged)
                    (ok (LgState :beta st.beta :eta st.eta :ll st.ll :prev st.ll :move st.move :iter (+ st.iter 1) :converged false))
                    (let [(moved (d/maxAbs (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (- (f64ArrayGet t.beta j) (f64ArrayGet st.beta j))))))
                          (small (<= moved (* 1.0e-8 (+ 1.0 (d/maxAbs t.beta)))))
                          (next (LgState :beta t.beta :eta t.eta :ll t.ll :prev t.prev :move moved :iter (+ st.iter 1) :converged small))]
                      (if small
                        (ok next)
                        (if (and (> (d/maxAbs next.eta) 10.0) (< (- next.ll st.ll) (* 1.0e-9 (+ 1.0 (abs next.ll)))) (> moved (* 0.5 st.move)))
                          (err (sepMsg))
                          (lgLoop! n k x xt y next maxIter maxHalve)))))))))))))

fn ! logitFinish! n: Int64 k: Int64 x: F64Array y: F64Array st: LgState kind: String cl: I64Array -> (Result Logit String)
  (let [(p (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (sigmoid (f64ArrayGet st.eta i)))))
        (xw (f64ArrayGenerate (* n k) (fn [(q2 Int64)] -> Float64 (let [(pi (f64ArrayGet p (/ q2 k)))] (* (f64ArrayGet x q2) (sqrt (* pi (- 1.0 pi))))))))
        (r (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (- (f64ArrayGet y i) (f64ArrayGet p i)))))]
    (match (gram n k xw)
      ((err e) (err e))
      ((ok fisher)
        (match (spdInverse k fisher)
          ((err e) (err (singMsg st.eta e)))
          ((ok ip)
            (let [(inv (pairFirst ip))
                  (w0 (joinW (illWarn (pairSecond ip)) (if st.converged "" "notConverged: maxIter reached before the step fell below 1e-8, estimates and p-values are not at the maximum")))]
             (if (= kind "classical")
              (ok (logitPack! n k st inv kind 0 w0))
              (match (clusterIndex n cl)
                ((err e) (err e))
                ((ok pr)
                  (match (sandwich! n k x r inv kind (pairFirst pr) (pairSecond pr))
                    ((err e) (err e))
                    ((ok cov) (ok (logitPack! n k st cov kind (pairSecond pr) (joinW w0 (warnFor (pairSecond pr) k)))))))))))))))

fn ! logitPack! n: Int64 k: Int64 st: LgState cov: F64Array kind: String g: Int64 warn: String -> Logit
  (let [(se (seOf! k cov))]
    (Logit :coef st.beta :cov cov :se se
           :zStat (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (statOf (f64ArrayGet st.beta j) (f64ArrayGet se j))))
           :pValue (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (pOfZ (f64ArrayGet st.beta j) (f64ArrayGet se j))))
           :logLik st.ll :iterations st.iter :converged st.converged :n n :k k :covKind kind :clusters g :warning warn))

; (:m :ref NUM-REGRESSION-MODELS :do "logitWith is the full entry: kind is classical (inverse Fisher information) or cr1 (sandwich with G/(G-1)*(n-1)/(n-k), the OLS factor, scores x_i (y_i - p_i), normal p-values); Stata logit with vce(cluster) uses G/(G-1) only, so multiply cov by (n-k)/(n-1) and se by its square root to reproduce Stata; beta0 is the start (zeros in logit), maxIter and maxHalve cap the iteration and the step halving; columns are scaled to unit norm internally and coefficients and covariance scaled back; logit and logitCluster are the zero-start entries with maxIter 100 and maxHalve 30; warning carries notConverged (p-values are still returned) and illConditioned")
fn ! logitRun! n: Int64 k: Int64 x: F64Array y: F64Array kind: String cl: I64Array beta0: F64Array maxIter: Int64 maxHalve: Int64 -> (Result Logit String)
  (match (d/transpose n k x)
    ((err e) (err e))
    ((ok xt)
      (let [(eta (gemm n 1 k x beta0))]
        (match (lgLoop! n k x xt y (LgState :beta beta0 :eta eta :ll (logLik n y eta) :prev -1.0e300 :move 1.0e300 :iter 0 :converged false) maxIter maxHalve)
          ((err e) (err e))
          ((ok st) (logitFinish! n k x y st kind cl))))))

fn ! unscaleLogit! k: Int64 o: Logit c: F64Array -> Logit
  (Logit :coef (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (/ (f64ArrayGet o.coef j) (f64ArrayGet c j))))
         :cov (f64ArrayGenerate (* k k) (fn [(p Int64)] -> Float64 (/ (f64ArrayGet o.cov p) (* (f64ArrayGet c (/ p k)) (f64ArrayGet c (% p k))))))
         :se (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (/ (f64ArrayGet o.se j) (f64ArrayGet c j))))
         :zStat o.zStat :pValue o.pValue :logLik o.logLik :iterations o.iterations :converged o.converged :n o.n :k o.k :covKind o.covKind :clusters o.clusters :warning o.warning)

fn ! logitWith n: Int64 k: Int64 x: F64Array y: F64Array kind: String cl: I64Array beta0: F64Array maxIter: Int64 maxHalve: Int64 -> (Result Logit String)
  (let [(bad (designError n k x y))]
    (cond
      ((not (= bad "")) (err bad))
      ((not (or (= kind "classical") (= kind "cr1"))) (err "regressKind: logit kind must be classical or cr1"))
      ((and (= kind "cr1") (not (= (i64ArrayLen cl) n))) (err "regressShape: cluster id count is not n"))
      ((not (= (f64ArrayLen beta0) k)) (err "regressShape: start vector length is not k"))
      ((or (< maxIter 1) (< maxHalve 0)) (err "regressRange: maxIter must be at least 1 and maxHalve at least 0"))
      ((not (binary? y 0 n)) (err "logitResponse: y must be 0 or 1 in every row"))
      (else
        (let [(c (colNorms! n k x))]
          (match (logitRun! n k (scaleCols! n k x c) y kind cl (f64ArrayGenerate k (fn [(j Int64)] -> Float64 (* (f64ArrayGet beta0 j) (f64ArrayGet c j)))) maxIter maxHalve)
            ((err e) (err e))
            ((ok o) (ok (unscaleLogit! k o c))))))))

fn ! logit n: Int64 k: Int64 x: F64Array y: F64Array -> (Result Logit String)
  (logitWith n k x y "classical" (i64ArrayGenerate 0 (fn [(i Int64)] -> Int64 0)) (zeros k) 100 30)

fn ! logitCluster n: Int64 k: Int64 x: F64Array y: F64Array cl: I64Array -> (Result Logit String)
  (logitWith n k x y "cr1" cl (zeros k) 100 30)
