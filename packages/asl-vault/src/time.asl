(module asl-vault/time
  :x [isoToEpoch epochToIso]
  :i [])

fn digitChar? c: String -> Bool
  (and (>= (charCode c) 48) (<= (charCode c) 57))

fn allDigits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? digitChar? (stringChars s)))

fn sliceInt s: String from: Int64 to: Int64 -> Int64
  (let [(part (optionOr (stringSlice s from to) ""))]
    (if (allDigits? part) (optionOr (stringToInt64 part) -1) -1))

fn leap? y: Int64 -> Bool
  (and (= (mod y 4) 0) (or (!= (mod y 100) 0) (= (mod y 400) 0)))

fn daysInMonth y: Int64 m: Int64 -> Int64
  (cond
    ((= m 2) (if (leap? y) 29 28))
    ((or (= m 4) (or (= m 6) (or (= m 9) (= m 11)))) 30)
    (else 31))

fn daysFromCivil y0: Int64 m: Int64 d: Int64 -> Int64
  (let [(y (if (<= m 2) (- y0 1) y0))
        (era (/ y 400))
        (yoe (- y (* era 400)))
        (mp (if (> m 2) (- m 3) (+ m 9)))
        (doy (+ (/ (+ (* 153 mp) 2) 5) (- d 1)))
        (doe (+ (+ (* yoe 365) (/ yoe 4)) (- doy (/ yoe 100))))]
    (- (+ (* era 146097) doe) 719468))

fn shapeOk? s: String -> Bool
  (and (= (stringLength s) 20)
       (and (= (optionOr (stringSlice s 4 5) "") "-")
            (and (= (optionOr (stringSlice s 7 8) "") "-")
                 (and (= (optionOr (stringSlice s 10 11) "") "T")
                      (and (= (optionOr (stringSlice s 13 14) "") ":")
                           (and (= (optionOr (stringSlice s 16 17) "") ":")
                                (= (optionOr (stringSlice s 19 20) "") "Z")))))))

; (:m :ref VS-VAULT :do "only the exact form YYYY-MM-DDTHH:MM:SSZ in years 1970 to 9999 is a time, answered in epoch milliseconds; every other spelling is rejected so equal instants have one byte form")
fn isoToEpoch s: String -> (Option Int64)
  (if (not (shapeOk? s))
    (none)
    (let [(y (sliceInt s 0 4)) (mo (sliceInt s 5 7)) (d (sliceInt s 8 10))
          (h (sliceInt s 11 13)) (mi (sliceInt s 14 16)) (se (sliceInt s 17 19))]
      (if (and (>= y 1970)
               (and (and (>= mo 1) (<= mo 12))
                    (and (and (>= d 1) (<= d (daysInMonth y mo)))
                         (and (and (>= h 0) (< h 24))
                              (and (and (>= mi 0) (< mi 60)) (and (>= se 0) (< se 60)))))))
        (some (* 1000 (+ (* (daysFromCivil y mo d) 86400) (+ (* h 3600) (+ (* mi 60) se)))))
        (none))))

fn pad n: Int64 width: Int64 -> String
  (let [(t (stringFromInt64 n))]
    (str (stringRepeat "0" (max 0 (- width (stringLength t)))) t))

; (:m :ref VS-VAULT :do "epoch milliseconds to the one canonical form, dropping the sub-second part")
fn epochToIso ms: Int64 -> String
  (let [(secs (/ ms 1000))
        (z (+ (/ secs 86400) 719468))
        (rem (- secs (* (/ secs 86400) 86400)))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- (+ (- doe (/ doe 1460)) (/ doe 36524)) (/ doe 146096)) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str (pad y 4) "-" (pad m 2) "-" (pad d 2) "T" (pad (/ rem 3600) 2) ":" (pad (/ (mod rem 3600) 60) 2) ":" (pad (mod rem 60) 2) "Z"))
