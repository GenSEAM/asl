(module asl-utils/tests/civilDateTest
  :x [runTests]
  :i [(asl-utils/civilDate :a cd)])

fn ! testDaysTable -> Bool
  (do (assert (= (cd/daysFromCivil 1970 1 1) 0) "epoch is day 0")
      (assert (= (cd/daysFromCivil 1969 12 31) -1) "the day before the epoch is -1")
      (assert (= (cd/daysFromCivil 2000 2 29) 11016) "2000-02-29 leap day")
      (assert (= (cd/daysFromCivil 2000 3 1) 11017) "2000-03-01 follows the leap day")
      (assert (= (cd/daysFromCivil 1900 2 28) -25509) "1900-02-28")
      (assert (= (cd/daysFromCivil 1900 3 1) -25508) "1900-03-01 follows 02-28 since 1900 is no leap year")
      (assert (= (cd/daysFromCivil 2026 11 22) 20779) "2026-11-22")
      (assert (= (cd/daysFromCivil 9999 12 31) 2932896) "year 9999 end")
      (assert (= (cd/daysFromCivil 0 3 1) -719468) "0000-03-01 is the algorithm origin")
      (assert (= (cd/daysFromCivil -1 3 1) -719834) "Mar 1 of year -1 is 366 days before 0000-03-01 since year 0 is leap")
      (assert (= (cd/daysFromCivil 0 2 29) -719469) "year 0 is a leap year")
      (assert (= (cd/daysFromCivil -400 3 1) (- (cd/daysFromCivil 0 3 1) 146097)) "a 400 year cycle is 146097 days in the negative range")
      true)

fn ! testCivilTable -> Bool
  (do (assert (= (cd/civilFromDays 0) (list 1970 1 1)) "day 0 is the epoch")
      (assert (= (cd/civilFromDays -1) (list 1969 12 31)) "day -1")
      (assert (= (cd/civilFromDays 11016) (list 2000 2 29)) "2000-02-29")
      (assert (= (cd/civilFromDays -25508) (list 1900 3 1)) "1900-03-01")
      (assert (= (cd/civilFromDays 2932896) (list 9999 12 31)) "9999-12-31")
      (assert (= (cd/civilFromDays -719469) (list 0 2 29)) "0000-02-29")
      (assert (= (cd/civilFromDays -719470) (list 0 2 28)) "0000-02-28")
      (assert (= (cd/civilFromDays -719834) (list -1 3 1)) "year -1 March 1")
      (assert (= (cd/civilFromDays -719835) (list -1 2 28)) "year -1 has no leap day")
      true)

fn countMisses d: Int64 hi: Int64 misses: Int64 -> Int64
  (if (> d hi) misses
    (let [(c (cd/civilFromDays d))
          (back (cd/daysFromCivil (optionOr (listGet c 0) 0) (optionOr (listGet c 1) 0) (optionOr (listGet c 2) 0)))
          (okDay (and (= back d) (>= (optionOr (listGet c 1) 0) 1) (<= (optionOr (listGet c 1) 0) 12) (>= (optionOr (listGet c 2) 0) 1)
                      (<= (optionOr (listGet c 2) 0) (cd/monthLength (optionOr (listGet c 0) 0) (optionOr (listGet c 1) 0)))))]
      (countMisses (+ d 1) hi (if okDay misses (+ misses 1)))))

fn ! testRoundTrip -> Bool
  (do (assert (= (countMisses -800000 -700000 0) 0) "round trip across negative years")
      (assert (= (countMisses -40000 80000 0) 0) "round trip across 1860..2189")
      (assert (= (countMisses 2930000 2933000 0) 0) "round trip around year 9999")
      true)

fn ! testLeapAndLengths -> Bool
  (do (assert (cd/leapYear? 2000) "2000 leap")
      (assert (not (cd/leapYear? 1900)) "1900 not leap")
      (assert (cd/leapYear? 2024) "2024 leap")
      (assert (cd/leapYear? -4) "-4 leap")
      (assert (= (cd/monthLength 2000 2) 29) "Feb 2000")
      (assert (= (cd/monthLength 1900 2) 28) "Feb 1900")
      (assert (= (cd/monthLength 2026 4) 30) "Apr")
      (assert (= (cd/monthLength 2026 12) 31) "Dec")
      true)

fn ! testQuarters -> Bool
  (let [(q1 (cd/quarterBoundsDays 2026 1))
        (q4 (cd/quarterBoundsDays 2025 4))]
    (do (assert (= (pairFirst q1) (cd/daysFromCivil 2026 1 1)) "Q1 starts Jan 1")
        (assert (= (pairSecond q1) (cd/daysFromCivil 2026 4 1)) "Q1 ends at Apr 1")
        (assert (= (pairFirst q4) (cd/daysFromCivil 2025 10 1)) "Q4 starts Oct 1")
        (assert (= (pairSecond q4) (cd/daysFromCivil 2026 1 1)) "Q4 ends at next Jan 1")
        (assert (= (- (pairSecond (cd/quarterBoundsDays 2000 1)) (pairFirst (cd/quarterBoundsDays 2000 1))) 91) "Q1 of a leap year has 91 days")
        true))

fn ! runTests -> Bool
  (and (testDaysTable) (testCivilTable) (testRoundTrip) (testLeapAndLengths) (testQuarters))
