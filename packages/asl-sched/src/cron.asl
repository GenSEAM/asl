(module asl-sched/cron
  :x [Cron parseCron nextFire]
  :i [(asl-utils/civilDate :a cd)])

enum Cron
  (cron minutes: (List Int64) hours: (List Int64) days: (List Int64) months: (List Int64) weekdays: (List Int64) dayWildcard: Bool weekdayWildcard: Bool)

fn nameValue text: String field: Int64 -> (Option Int64)
  (cond ((and (= field 3) (= text "JAN")) (some 1))
        ((and (= field 3) (= text "FEB")) (some 2))
        ((and (= field 3) (= text "MAR")) (some 3))
        ((and (= field 3) (= text "APR")) (some 4))
        ((and (= field 3) (= text "MAY")) (some 5))
        ((and (= field 3) (= text "JUN")) (some 6))
        ((and (= field 3) (= text "JUL")) (some 7))
        ((and (= field 3) (= text "AUG")) (some 8))
        ((and (= field 3) (= text "SEP")) (some 9))
        ((and (= field 3) (= text "OCT")) (some 10))
        ((and (= field 3) (= text "NOV")) (some 11))
        ((and (= field 3) (= text "DEC")) (some 12))
        ((and (= field 4) (= text "SUN")) (some 0))
        ((and (= field 4) (= text "MON")) (some 1))
        ((and (= field 4) (= text "TUE")) (some 2))
        ((and (= field 4) (= text "WED")) (some 3))
        ((and (= field 4) (= text "THU")) (some 4))
        ((and (= field 4) (= text "FRI")) (some 5))
        ((and (= field 4) (= text "SAT")) (some 6))
        (else (stringToInt64 text)))

fn fieldNumber text: String field: Int64 -> (Option Int64)
  (let [(v (nameValue (stringUpper text) field))]
    (match v ((some n)
      (if (and (>= n (if (or (= field 2) (= field 3)) 1 0)) (<= n (if (= field 0) 59 (if (= field 1) 23 (if (= field 2) 31 (if (= field 3) 12 7))))))
        (some (if (and (= field 4) (= n 7)) 0 n))
        none))
      ((none) none)))

fn fieldStart text: String field: Int64 -> (Option Int64)
  (if (= text "*") (some (if (= field 4) 0 (if (= field 2) 1 (if (= field 3) 1 0))))
    (fieldNumber text field))

fn fieldRangeNumber text: String field: Int64 -> (Option Int64)
  (match (stringToInt64 text) ((some n)
    (if (and (>= n (if (= field 2) 1 (if (= field 3) 1 0)))
             (<= n (if (= field 0) 59 (if (= field 1) 23 (if (= field 2) 31 (if (= field 3) 12 7))))))
      (some n) none))
    ((none) (nameValue (stringUpper text) field)))

fn appendRange out: (List Int64) n: Int64 last: Int64 step: Int64 -> (List Int64)
  (if (> n last) out
    (appendRange (if (listContains? out n) out (listAppend out [n])) (+ n step) last step))

fn appendFieldRange out: (List Int64) n: Int64 last: Int64 step: Int64 field: Int64 -> (List Int64)
  (if (> n last) out
    (let [(value (if (and (= field 4) (= n 7)) 0 n))]
      (appendFieldRange (if (listContains? out value) out (listAppend out [value])) (+ n step) last step field)))

fn parsePart part: String field: Int64 position: Int64 -> (Result (List Int64) String)
  (let [(stepParts (stringSplit part "/"))
        (stepText (optionOr (listGet stepParts 1) "1"))
        (step (optionOr (stringToInt64 stepText) 0))
        (base (optionOr (listGet stepParts 0) ""))
        (rangeParts (stringSplit base "-"))
        (start (optionOr (if (= (listLength rangeParts) 1)
          (fieldStart (optionOr (listGet rangeParts 0) "") field)
          (fieldRangeNumber (optionOr (listGet rangeParts 0) "") field)) -1))
        (end (if (= (listLength rangeParts) 1)
          (if (or (= base "*") (> (listLength stepParts) 1))
            (if (= field 0) 59 (if (= field 1) 23 (if (= field 2) 31 (if (= field 3) 12 7)))) start)
          (optionOr (fieldRangeNumber (optionOr (listGet rangeParts 1) "") field) -1)))]
    (if (or (< step 1) (> (listLength stepParts) 2)) (err (stringConcat "position " (stringConcat (stringFromInt64 position) ": invalid step")))
      (if (or (< start 0) (< end 0)) (err (stringConcat "position " (stringConcat (stringFromInt64 position) ": invalid value")))
        (if (or (> start end) (> (listLength rangeParts) 2)) (err (stringConcat "position " (stringConcat (stringFromInt64 position) ": invalid range")))
          (ok (appendFieldRange [] start end step field))))))

fn fieldLabel field: Int64 -> String
  (cond ((= field 0) "minute") ((= field 1) "hour") ((= field 2) "day-of-month") ((= field 3) "month") (else "day-of-week"))

fn parseFieldAt parts: (List String) field: Int64 index: Int64 accumulated: (List Int64) -> (Result (List Int64) String)
  (if (>= index (listLength parts)) (ok accumulated)
    (match (parsePart (optionOr (listGet parts index) "") field (+ index 1))
      ((ok values) (parseFieldAt parts field (+ index 1) (listAppend accumulated values)))
      ((err e) (err (stringConcat "field " (stringConcat (fieldLabel field) (stringConcat " " e)))))))

fn parseFieldParts parts: (List String) field: Int64 -> (Result (List Int64) String)
  (parseFieldAt parts field 0 [])

fn parseField text: String field: Int64 -> (Result (List Int64) String)
  (parseFieldParts (stringSplit text ",") field)

fn parseCron expression: String -> (Result Cron String)
  (let [(expanded (cond ((= expression "@hourly") "0 * * * *")
                        ((= expression "@daily") "0 0 * * *")
                        ((= expression "@weekly") "0 0 * * 0")
                        ((= expression "@monthly") "0 0 1 * *")
                        ((= expression "@yearly") "0 0 1 1 *")
                        (else expression)))
        (fields (stringSplit (stringTrim expanded) " "))]
    (if (not (= (listLength fields) 5)) (err "field 0 position 1: expected five fields")
      (match (parseField (optionOr (listGet fields 0) "") 0)
        ((ok minutes)
          (match (parseField (optionOr (listGet fields 1) "") 1)
            ((ok hours)
              (match (parseField (optionOr (listGet fields 2) "") 2)
                ((ok days)
                  (match (parseField (optionOr (listGet fields 3) "") 3)
                    ((ok months)
                      (match (parseField (optionOr (listGet fields 4) "") 4)
                        ((ok weekdays) (ok (cron minutes hours days months weekdays
                          (= (optionOr (listGet fields 2) "") "*")
                          (= (optionOr (listGet fields 4) "") "*"))))
                        ((err e) (err e))))
                    ((err e) (err e))))
                ((err e) (err e))))
            ((err e) (err e))))
        ((err e) (err e)))))

fn dateMatches value: Cron days: Int64 -> Bool
  (match value ((cron _ _ dom months dow domStar dowStar)
    (let [(parts (cd/civilFromDays days))
          (year (optionOr (listGet parts 0) 1970))
          (month (optionOr (listGet parts 1) 1))
          (day (optionOr (listGet parts 2) 1))
          (weekday (mod (+ days 4) 7))
          (monthOk (listContains? months month))
          (domOk (listContains? dom day))
          (dowOk (listContains? dow weekday))
          (dayOk (if (and (not domStar) (not dowStar)) (or domOk dowOk)
            (and (if domStar true domOk) (if dowStar true dowOk))))]
      (and monthOk dayOk))))

fn minuteOnDay value: Cron day: Int64 afterSeconds: Int64 minuteOfDay: Int64 -> (Option Int64)
  (if (>= minuteOfDay 1440) none
    (match value ((cron minutes hours _ _ _ _ _)
      (let [(hour (/ minuteOfDay 60))
            (minute (mod minuteOfDay 60))
            (candidate (+ (* day 86400) (* minuteOfDay 60)))]
        (if (and (listContains? hours hour) (listContains? minutes minute) (> candidate afterSeconds))
          (some candidate)
          (minuteOnDay value day afterSeconds (+ minuteOfDay 1)))))))

fn searchDay value: Cron afterSeconds: Int64 startDay: Int64 offset: Int64 -> (Result Int64 String)
  (if (> offset 1827) (err "no fire within five years")
    (let [(day (+ startDay offset))]
      (if (not (dateMatches value day)) (searchDay value afterSeconds startDay (+ offset 1))
        (match (minuteOnDay value day afterSeconds 0)
          ((some fire) (ok fire))
          ((none) (searchDay value afterSeconds startDay (+ offset 1)))))))

fn nextFire value: Cron afterSeconds: Int64 -> (Result Int64 String)
  (searchDay value afterSeconds (/ afterSeconds 86400) 0)
