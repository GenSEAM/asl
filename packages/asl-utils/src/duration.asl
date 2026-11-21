(module asl-utils/duration :x [parseDuration formatDuration] :i [])

(schema PState (:f total Int64) (:f num String) (:f pending String) (:f bad Bool) (:f units Int64))

fn isDigit c: String -> Bool
  (>= (optionOr (stringToInt64 c) -1) 0)

fn lowerChar c: String -> String
  (if (= c "D") "d"
    (if (= c "H") "h"
      (if (= c "M") "m"
        (if (= c "S") "s"
          (if (= c "W") "w"
            (if (= c "T") "t"
              (if (= c "P") "p" c)))))))

fn charsToStr cs: (List String) -> String
  (fold (fn [(acc String) (c String)] -> String (str acc c)) "" cs)

fn headChar s: String -> String
  (optionOr (listHead (stringChars s)) "")

fn tailStr s: String -> String
  (match (listTail (stringChars s))
    ((some cs) (charsToStr cs))
    ((none) ""))

fn commit st: PState ms: Int64 -> PState
  (if (= st.num "")
    (with st :bad true)
    (match (stringToInt64 st.num)
      ((some n) (PState :total (+ st.total (* n ms)) :num "" :pending "" :bad st.bad :units (+ st.units 1)))
      ((none) (with st :bad true))))

fn stepFresh st: PState c: String -> PState
  (if (isDigit c)
    (with st :num (str st.num c))
    (if (= c "m")
      (with st :pending "m")
      (if (= c "s")
        (commit st 1000)
        (if (= c "h")
          (commit st 3600000)
          (if (= c "d")
            (commit st 86400000)
            (if (= c "w")
              (commit st 604800000)
              (with st :bad true)))))))

fn stepChar st: PState c: String -> PState
  (if st.bad
    st
    (if (= st.pending "m")
      (if (= c "s")
        (commit st 1)
        (let [(st2 (commit st 60000))]
          (if st2.bad st2 (stepFresh st2 c))))
      (stepFresh st c)))

fn finish st: PState -> (Result Int64 String)
  (if st.bad
    (err "duration: invalid")
    (if (= st.pending "m")
      (let [(st2 (commit st 60000))]
        (if st2.bad
          (err "duration: invalid")
          (if (= st2.num "")
            (ok st2.total)
            (err "duration: missing unit"))))
      (if (= st.num "")
        (if (= st.units 0)
          (err "duration: no units")
          (ok st.total))
        (err "duration: missing unit"))))

fn parseSimple s: String -> (Result Int64 String)
  (let [(st (fold (fn [(acc PState) (c String)] -> PState (stepChar acc c))
                  (PState :total 0 :num "" :pending "" :bad false :units 0)
                  (map lowerChar (stringChars s))))]
    (finish st))

fn splitOnT cs: (List String) -> (Pair (List String) (List String))
  (if (listEmpty? cs)
    (pair [] [])
    (if (= (optionOr (listHead cs) "") "t")
      (pair [] (optionOr (listTail cs) []))
      (let [(h (optionOr (listHead cs) ""))
            (rest (optionOr (listTail cs) []))
            (sub (splitOnT rest))]
        (pair (cons h (pairFirst sub)) (pairSecond sub)))))

fn validDateChar c: String -> Bool
  (or (isDigit c) (or (= c "d") (= c "w")))

fn validTimeChar c: String -> Bool
  (or (isDigit c) (or (= c "h") (or (= c "m") (= c "s"))))

fn parseIso s: String -> (Result Int64 String)
  (let [(cs (map lowerChar (stringChars s)))
        (parts (splitOnT cs))
        (datePart (charsToStr (pairFirst parts)))
        (timePart (charsToStr (pairSecond parts)))
        (hasT (listAny? (fn [(c String)] -> Bool (= c "t")) cs))]
    (if (and hasT (= timePart ""))
      (err "duration: missing time after T")
      (if (listAny? (fn [(c String)] -> Bool (not (validDateChar c))) (stringChars datePart))
        (err "duration: invalid date character")
        (if (listAny? (fn [(c String)] -> Bool (not (validTimeChar c))) (stringChars timePart))
          (err "duration: invalid time character")
          (let [(dr (parseSimple datePart))
                (tr (parseSimple timePart))]
            (match dr
              ((err e) (if (= datePart "") tr (err e)))
              ((ok dv)
               (match tr
                 ((err e) (if (= timePart "") (ok dv) (err e)))
                 ((ok tv) (ok (+ dv tv)))))))))))

fn parseDuration s: String -> (Result Int64 String)
  (if (= (headChar s) "")
    (err "duration: empty")
    (if (= (lowerChar (headChar s)) "p")
      (parseIso (tailStr s))
      (parseSimple s)))

fn partStr n: Int64 unit: String -> String
  (if (= n 0) "" (str n unit))

fn formatPos ms: Int64 -> String
  (if (= ms 0)
    "0s"
    (let [(d (/ ms 86400000))
          (r1 (- ms (* d 86400000)))
          (h (/ r1 3600000))
          (r2 (- r1 (* h 3600000)))
          (m (/ r2 60000))
          (r3 (- r2 (* m 60000)))
          (sec (/ r3 1000))
          (mrem (- r3 (* sec 1000)))]
      (str (partStr d "d") (partStr h "h") (partStr m "m") (partStr sec "s") (partStr mrem "ms"))))

fn formatDuration ms: Int64 -> String
  (if (< ms 0)
    (if (= ms -9223372036854775808)
      "-106751991167d7h12m55s808ms"
      (str "-" (formatPos (- 0 ms))))
    (formatPos ms))
