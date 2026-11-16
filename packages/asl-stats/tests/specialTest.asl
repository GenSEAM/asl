(module asl-stats/tests/specialTest
  :x [runTests]
  :i [(asl-stats/special :a sp)])

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn rel? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) (* eps (abs b)))

fn rv r: (Result Float64 String) -> Float64
  (match r ((err e) -999.0) ((ok v) v))

fn errHas? r: (Result Float64 String) key: String -> Bool
  (match r ((err e) (stringContains? e key)) ((ok v) false))

fn close? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) (* eps (abs b)))

fn monoFrom? t: Float64 prev: Float64 df: Float64 -> Bool
  (if (> t 40.0) true
    (let [(c (sp/studentCdf t df))]
      (if (< c prev) false (monoFrom? (+ t 0.25) c df))))

fn cdfMonotone? df: Float64 -> Bool
  (monoFrom? -39.75 (sp/studentCdf -40.0 df) df)

fn ! runTests -> Bool
  (do
    (assert (near? (sp/normalCdf 1.959964) 0.975 1.0e-6) "Phi(1.959964) = 0.975")
    (assert (near? (sp/normalCdf 0.0) 0.5 1.0e-15) "Phi(0) = 0.5")
    (assert (near? (sp/normalCdf 1.0) 0.8413447460685429 1.0e-14) "Phi(1)")
    (assert (near? (sp/normalCdf -1.0) 0.15865525393145707 1.0e-14) "Phi(-1)")
    (assert (rel? (sp/normalCdf -5.0) 2.866515718791939e-07 1.0e-12) "Phi(-5) relative")
    (assert (rel? (sp/normalCdf -6.0) 9.865876450376946e-10 1.0e-12) "Phi(-6) relative")
    (assert (rel? (sp/normalCdf -10.0) 7.619853024160527e-24 1.0e-11) "Phi(-10) relative, far tail does not cancel to 0")
    (assert (near? (+ (sp/normalCdf 2.3) (sp/normalCdf -2.3)) 1.0 1.0e-14) "Phi(z) + Phi(-z) = 1")
    (assert (rel? (sp/normalSurvival 5.0) 2.866515718791939e-07 1.0e-12) "survival of 5")
    (assert (near? (sp/normalPdf 0.0) 0.3989422804014327 1.0e-15) "pdf at 0")
    (assert (near? (rv (sp/normalQuantileChecked 0.975)) 1.959963984540054 1.0e-12) "z 0.975 = 1.959963984540054")
    (assert (near? (rv (sp/normalQuantileChecked 0.995)) 2.5758293035489004 1.0e-12) "z 0.995")
    (assert (near? (rv (sp/normalQuantileChecked 0.999)) 3.090232306167813 1.0e-12) "z 0.999")
    (assert (near? (rv (sp/normalQuantileChecked 0.5)) 0.0 1.0e-12) "z 0.5 = 0")
    (assert (near? (rv (sp/normalQuantileChecked 1.0e-10)) -6.361340902404056 1.0e-9) "z 1e-10")
    (assert (near? (sp/normalCdf (rv (sp/normalQuantileChecked 0.3))) 0.3 1.0e-13) "cdf(quantile(p)) = p")
    (assert (errHas? (sp/normalQuantileChecked 0.0) "statsRange") "p = 0 is an error")
    (assert (errHas? (sp/normalQuantileChecked 1.0) "statsRange") "p = 1 is an error")
    (assert (errHas? (sp/normalQuantileChecked (/ 0.0 0.0)) "statsRange") "p NaN is an error")
    (assert (near? (rv (sp/studentQuantileChecked 0.975 10.0)) 2.228138851986274 1.0e-10) "t 0.975 df 10")
    (assert (near? (rv (sp/studentQuantileChecked 0.975 1.0)) 12.706204736432095 1.0e-9) "t 0.975 df 1")
    (assert (near? (rv (sp/studentQuantileChecked 0.975 2.0)) 4.302652729911275 1.0e-9) "t 0.975 df 2")
    (assert (near? (rv (sp/studentQuantileChecked 0.975 30.0)) 2.0422724563012373 1.0e-10) "t 0.975 df 30")
    (assert (near? (rv (sp/studentQuantileChecked 0.995 5.0)) 4.032142983557536 1.0e-10) "t 0.995 df 5")
    (assert (near? (rv (sp/studentQuantileChecked 0.025 10.0)) -2.228138851986274 1.0e-10) "t is symmetric")
    (assert (near? (rv (sp/studentQuantileChecked 0.975 100000.0)) 1.959963984540054 1.0e-4) "t df 1e5 approaches the normal quantile")
    (assert (near? (sp/studentCdf 2.228138851986274 10.0) 0.975 1.0e-12) "t cdf df 10 at 2.228")
    (assert (near? (sp/studentCdf 0.0 7.0) 0.5 1.0e-15) "t cdf at 0")
    (assert (near? (sp/studentCdf 1.0 1.0) 0.75 1.0e-14) "Cauchy cdf at 1 is 3/4")
    (assert (errHas? (sp/studentQuantileChecked 0.975 0.0) "statsRange") "df = 0 is an error")
    (assert (errHas? (sp/studentQuantileChecked 0.975 (/ 0.0 0.0)) "statsRange") "df NaN is an error")
    (assert (errHas? (sp/studentQuantileChecked 1.5 5.0) "statsRange") "p above 1")
    (assert (errHas? (sp/studentQuantileChecked 1.0e-12 0.05) "statsRange") "bracket edge is reported, not returned")
    (assert (near? (sp/gammaIncQ 2.0 3.0) 0.19914827347145578 1.0e-13) "Q(2,3) = 4 e^-3")
    (assert (near? (sp/normalQuantile (- 1.0 1.0e-10)) 6.361340889697422 1.0e-12) "scipy ndtri(1-1e-10); was 1.3e-7 off")
    (assert (near? (sp/normalQuantile (- 1.0 1.0e-12)) 7.0344869100478356 1.0e-12) "scipy ndtri(1-1e-12); was 3.9e-6 off")
    (assert (near? (sp/normalQuantile (- 1.0 1.0e-14)) 7.650730905155642 1.0e-12) "scipy ndtri(1-1e-14); was 1.1e-3 off")
    (assert (near? (sp/normalQuantile 1.0e-300) -37.0470962993612 1.0e-12) "scipy ndtri(1e-300)")
    (assert (near? (sp/normalQuantile (sp/normalSurvival 8.0)) -8.0 1.0e-11) "quantile of the lower tail probability of 8 round-trips (upper cdf(8) = 1-6e-16 cannot: doubles near 1 are 1.1e-16 apart)")
    (assert (near? (sp/studentQuantile 0.5 30.0) 0.0 1.0e-15) "t median df 30 is 0 (was -4.2e-8)")
    (assert (near? (sp/studentQuantile 0.5 1000000.0) 0.0 1.0e-15) "t median df 1e6 is 0 (was -7.6e-6)")
    (assert (rel? (sp/studentCdf -1.0 100000000.0) 0.15865525514131062 1.0e-13) "scipy t.cdf(-1, 1e8) (was 2e-7 off)")
    (assert (rel? (sp/studentCdf -1.0 10000000000.0) 0.15865525394355556 1.0e-13) "scipy t.cdf(-1, 1e10) (was 1.7e-5 off)")
    (assert (near? (sp/studentQuantile 0.025 1.0e12) -1.9599639845424266 1.0e-13) "scipy t.ppf(0.025, 1e12) (was 2.3e-5 off)")
    (assert (rel? (sp/studentCdf -2.0 100000.0) 0.022751481728753246 1.0e-12) "scipy t.cdf(-2, 1e5), series range")
    (assert (rel? (sp/studentCdf -2.0 99999.0) 0.022751481742251233 1.0e-9) "scipy t.cdf(-2, 99999), beta range, 6e-11 relative measured")
    (assert (rel? (sp/studentCdf 0.001 30.0) 0.5003956321167575 1.0e-13) "scipy t.cdf(0.001, 30), not flat near 0")
    (assert (rel? (sp/studentCdf -40.0 5.0) 9.205981085886474e-08 1.0e-11) "scipy t.cdf(-40, 5) far tail")
    (assert (rel? (sp/studentCdf 1.5 1000.0) 0.933034980588957 1.0e-11) "scipy t.cdf(1.5, 1000)")
    (assert (near? (sp/studentQuantile 0.999 1000.0) 3.098402163912923 1.0e-11) "scipy t.ppf(0.999, 1000)")
    (assert (rel? (sp/studentQuantile 1.0e-8 3.0) -479.5250695797382 1.0e-11) "scipy t.ppf(1e-8, 3)")
    (assert (rel? (sp/studentQuantile 0.99999 2.5) 87.64328685682148 1.0e-11) "scipy t.ppf(0.99999, 2.5)")
    (assert (near? (rv (sp/studentQuantileChecked 0.5 1.0e6)) 0.0 1.0e-15) "checked median at df 1e6")
    (assert (rel? (sp/studentCdf -10.0 1000.0) 8.335351479300063e-23 1.0e-12) "scipy t.cdf(-10, 1000), was 0.0")
    (assert (rel? (sp/studentCdf -20.0 1000.0) 2.0311442497624068e-75 1.0e-12) "scipy t.cdf(-20, 1000), was 0.0")
    (assert (rel? (sp/studentCdf -9.0 99999.0) 1.1477046951809592e-19 2.0e-12) "scipy t.cdf(-9, 99999), was 0.0")
    (assert (rel? (sp/studentCdf -8.5 1000.0) 3.409557447332085e-17 1.0e-12) "scipy t.cdf(-8.5, 1000), was 5.6e-17")
    (assert (rel? (sp/studentCdf -5.0 999.0) 3.384180947900553e-07 1.0e-12) "scipy t.cdf(-5, 999), was 6e-11 off")
    (assert (rel? (sp/studentCdf -5.0 99999.0) 2.8713508877053543e-07 2.0e-12) "scipy t.cdf(-5, 99999), was 1.1e-10 off")
    (assert (rel? (sp/studentCdf -1.0 99999.0) 0.15865646379415355 1.0e-11) "scipy t.cdf(-1, 99999)")
    (assert (rel? (sp/studentCdf -3.0 50.0) 0.0021008515935341207 1.0e-12) "scipy t.cdf(-3, 50)")
    (assert (rel? (sp/studentCdf -1.0 5.0) 0.18160873382456136 1.0e-12) "scipy t.cdf(-1, 5), centre form")
    (assert (rel? (sp/studentCdf -0.5 3.0) 0.3257239824240755 1.0e-12) "scipy t.cdf(-0.5, 3), centre form")
    (assert (rel? (sp/studentCdf -5.0 30.0) 1.1648342733503901e-05 1.0e-12) "scipy t.cdf(-5, 30)")
    (assert (rel? (sp/studentQuantile 1.0e-100 1000.0) -23.930617087826437 1.0e-10) "scipy t.ppf(1e-100, 1000), was -8.526")
    (assert (rel? (sp/studentQuantile 1.0e-300 99999.0) -37.17467194488096 1.0e-10) "scipy t.ppf(1e-300, 99999), was -8.376")
    (assert (rel? (sp/studentQuantile 1.0e-15 1000.0) -8.070281832298525 1.0e-10) "scipy t.ppf(1e-15, 1000), was -8.0668")
    (assert (rel? (sp/studentQuantile 1.0e-10 50.0) -7.948243747646223 1.0e-10) "scipy t.ppf(1e-10, 50)")
    (assert (rel? (sp/studentQuantile 1.0e-30 5.0) -1568392.5590979713 1.0e-9) "scipy t.ppf(1e-30, 5)")
    (assert (rel? (sp/studentCdf -1.0 100000.0) 0.15865646378205506 1.0e-11) "scipy t.cdf(-1, 1e5)")
    (assert (rel? (sp/studentCdf -9.0 100000.0) 1.1477045025115732e-19 1.0e-9) "scipy t.cdf(-9, 1e5), series range")
    (assert (close? (sp/studentCdf -1.0 99999.0) (sp/studentCdf -1.0 100000.0) 1.0e-9) "continuity at df 1e5, t -1")
    (assert (close? (sp/studentCdf -5.0 99999.0) (sp/studentCdf -5.0 100000.0) 1.0e-7) "continuity at df 1e5, t -5 (true change 1.7e-8, jump was 2e-10 on top)")
    (assert (close? (sp/studentCdf -9.0 99999.0) (sp/studentCdf -9.0 100000.0) 1.0e-6) "continuity at df 1e5, t -9 (true change 1.7e-7)")
    (assert (cdfMonotone? 1.0) "monotone df 1")
    (assert (cdfMonotone? 2.5) "monotone df 2.5")
    (assert (cdfMonotone? 30.0) "monotone df 30")
    (assert (cdfMonotone? 999.0) "monotone df 999")
    (assert (cdfMonotone? 1000.0) "monotone df 1000")
    (assert (cdfMonotone? 99999.0) "monotone df 99999")
    (assert (cdfMonotone? 100000.0) "monotone df 1e5")
    (assert (cdfMonotone? 1.0e7) "monotone df 1e7")
    true)

