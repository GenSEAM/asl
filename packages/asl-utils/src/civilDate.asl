(module asl-utils/civilDate
  :x [leapYear? monthLength daysFromCivil civilFromDays quarterBoundsDays]
  :i [])

; (:m :do "proleptic Gregorian civil date arithmetic on days since 1970-01-01, exact for negative years because / floors in ASL; the one copy every package imports")
fn leapYear? y: Int64 -> Bool
  (and (= (mod y 4) 0) (or (not (= (mod y 100) 0)) (= (mod y 400) 0)))

fn monthLength y: Int64 m: Int64 -> Int64
  (cond ((= m 2) (if (leapYear? y) 29 28))
        ((or (= m 4) (= m 6) (= m 9) (= m 11)) 30)
        (else 31))

fn daysFromCivil y: Int64 m: Int64 d: Int64 -> Int64
  (let [(yy (if (<= m 2) (- y 1) y))
        (era (/ yy 400))
        (yoe (- yy (* era 400)))
        (mp (if (> m 2) (- m 3) (+ m 9)))
        (doy (+ (/ (+ (* 153 mp) 2) 5) (- d 1)))
        (doe (+ (* yoe 365) (/ yoe 4) (- 0 (/ yoe 100)) doy))]
    (+ (* era 146097) doe -719468))

fn civilFromDays days: Int64 -> (List Int64)
  (let [(z (+ days 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (+ doe (/ doe 36524)) (+ (/ doe 1460) (/ doe 146096))) 365))
        (y (+ yoe (* era 400)))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))]
    (list (if (<= m 2) (+ y 1) y) m d))

; (:m :do "days since the epoch of the first day of quarter q (1..4) of year y and of the first day after it, as a pair [start end)")
fn quarterBoundsDays y: Int64 q: Int64 -> (Pair Int64 Int64)
  (let [(startMonth (+ (* 3 (- q 1)) 1))
        (endYear (if (= q 4) (+ y 1) y))
        (endMonth (if (= q 4) 1 (+ startMonth 3)))]
    (pair (daysFromCivil y startMonth 1) (daysFromCivil endYear endMonth 1)))
