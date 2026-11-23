(module aslGateway/tests/staleHeaderCtrlTest
  :x [runTests]
  :i [(server :a srv)])

; (:m :ref GW-CONFIG-STALE-LOUD :do "a stale reason holding a tab and byte 1 folds to one clean header line: every byte below 32 and byte 127 becomes a space, so the value holds no control byte and the line stays a single line")
fn ! testCtrl -> Bool
  (let [(reason (str "profile p1: bad" "\t" "\u0001" "tail"))
        (line (srv/staleHeaderLine reason))
        (value (optionOr (stringSlice line (+ (stringLength (srv/staleHeaderName)) 2) (- (stringLength line) 2)) ""))
        (codes (map (fn [(c String)] -> Int64 (charCode c)) (stringChars value)))]
    (do (assert (= value "profile p1: bad  tail") (str "CTRL: tab and byte 1 fold to spaces: " value))
        (assert (listAll? (fn [(n Int64)] -> Bool (and (>= n 32) (!= n 127))) codes) "CTRL: the value holds no control byte")
        (assert (= (stringLength line) (+ (stringLength (srv/staleHeaderName)) 2 (stringLength value) 2)) "CTRL: the header line is one line, ending in CRLF")
        (assert (not (stringContains? line "\t")) "CTRL: no tab survives")
        (assert (= (srv/staleHeaderLine "a\r\nb") (str (srv/staleHeaderName) ": a  b\r\n")) "CTRL: CR and LF still fold")
        true))

fn ! runTests -> Bool
  (do (assert (testCtrl) "GW-CONFIG-STALE-LOUD: control bytes fold")
      true)
