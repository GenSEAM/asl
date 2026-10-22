(module asl-sched/slots
  :x [Slot ClaimResult Schedule intervalSchedule cronSchedule slotClaim slotComplete slotExpire recoverSlots serializeSlot parseSlot]
  :i [(asl-sched/interval :a iv) (asl-sched/cron :a cr)])

enum Slot
  (slot job: String dueSeconds: Int64 claimedBy: String claimExpiresSeconds: Int64 attempt: Int64)
enum ClaimResult
  (claimed slot: Slot)
  (alreadyClaimed)
  (notDue)
  (invalidLease)
enum Schedule
  (intervalSchedule interval: iv/Interval)
  (cronSchedule cron: cr/Cron)

fn slotClaim value: Slot worker: String now: Int64 leaseSeconds: Int64 -> ClaimResult
  (match value
    ((slot job due owner expiry attempt)
      (cond ((< leaseSeconds 1) invalidLease)
            ((< now due) notDue)
            ((and (not (= owner "")) (> expiry now)) alreadyClaimed)
            (else (claimed (slot job due worker (+ now leaseSeconds) (+ attempt 1)))))))

fn slotExpire value: Slot now: Int64 -> Slot
  (match value
    ((slot job due owner expiry attempt)
      (if (and (not (= owner "")) (<= expiry now))
        (slot job due "" 0 attempt)
        value)))

fn recoverSlots values: (List Slot) now: Int64 -> (List Slot)
  (if (= (listLength values) 0) []
    (let [(value (optionOr (listHead values) (slot "" 0 "" 0 0)))
          (tail (optionOr (listTail values) []))
          (released (slotExpire value now))
          (rest (recoverSlots tail now))]
      (if (= released value) rest
        (listAppend [released] rest))))

fn slotComplete value: Slot schedule: Schedule completedSeconds: Int64 -> (Result Slot String)
  (match value
    ((slot job _ _ _ attempt)
      (match schedule
        ((intervalSchedule interval)
          (match (iv/intervalNextFire interval completedSeconds)
            ((ok due) (ok (slot job due "" 0 0))) ((err e) (err e))))
        ((cronSchedule cron)
          (match (cr/nextFire cron completedSeconds)
            ((ok due) (ok (slot job due "" 0 0))) ((err e) (err e)))))))

fn integerTextDigits n: Int64 -> String
  (let [(digits "0123456789")]
    (if (< n 10) (optionOr (stringSlice digits n (+ n 1)) "0")
      (stringConcat (integerTextDigits (/ n 10))
        (optionOr (stringSlice digits (mod n 10) (+ (mod n 10) 1)) "0"))))

fn integerText value: Int64 -> String
  (if (< value 0) (stringConcat "-" (integerTextDigits (- 0 value)))
    (integerTextDigits value))

schema SlotToken (:f text String) (:f quoted Bool)

fn slotEscape c: String -> String
  (cond ((= c "n") "\n") ((= c "t") "\t") ((= c "r") "\r") ((= c "0") "\x00") (else c))

fn slotTokens text: String index: Int64 quoted: Bool escaped: Bool current: String tokenQuoted: Bool acc: (List SlotToken) -> (Result (List SlotToken) String)
  (if (>= index (stringLength text))
    (if (or quoted escaped) (err "invalid quoted slot string")
      (ok (if (or tokenQuoted (not (stringEmpty? current))) (listAppend acc (list (SlotToken :text current :quoted tokenQuoted))) acc)))
    (let [(c (optionOr (stringSlice text index (+ index 1)) ""))]
      (if escaped
        (slotTokens text (+ index 1) quoted false (stringConcat current (slotEscape c)) tokenQuoted acc)
        (if (and quoted (= c "\\"))
          (slotTokens text (+ index 1) quoted true current tokenQuoted acc)
          (if (= c "\"")
            (slotTokens text (+ index 1) (not quoted) false current true acc)
            (if (and (not quoted) (= c " "))
              (slotTokens text (+ index 1) false false "" false
                (if (or tokenQuoted (not (stringEmpty? current))) (listAppend acc (list (SlotToken :text current :quoted tokenQuoted))) acc))
              (slotTokens text (+ index 1) quoted false (stringConcat current c) tokenQuoted acc)))))))

fn slotTokenText tokens: (List SlotToken) index: Int64 -> String
  (match (listGet tokens index) ((some token) token.text) ((none) ""))

fn slotTokenQuoted? tokens: (List SlotToken) index: Int64 -> Bool
  (match (listGet tokens index) ((some token) token.quoted) ((none) false))

fn slotQuote value: String -> String
  (stringConcat "\"" (stringConcat (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace value "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\r" "\\r") "\x00" "\\0") "\""))

fn serializeSlot value: Slot -> String
  (match value
    ((slot job due owner expiry attempt)
      (stringConcat "(:slot "
        (stringConcat (slotQuote job)
          (stringConcat " " (stringConcat (integerText due)
            (stringConcat " " (stringConcat (slotQuote owner)
              (stringConcat " " (stringConcat (integerText expiry)
                (stringConcat " " (stringConcat (integerText attempt) ")"))))))))))))

fn parseSlot text: String -> (Result Slot String)
  (let [(source (stringTrim text))]
    (if (or (not (stringStartsWith? source "(:slot ")) (not (stringEndsWith? source ")")))
      (err "invalid slot ASN")
      (match (stringSlice source 7 (- (stringLength source) 1))
        ((some body)
          (match (slotTokens body 0 false false "" false [])
            ((ok tokens)
              (if (or (not (= (listLength tokens) 5)) (not (slotTokenQuoted? tokens 0)) (slotTokenQuoted? tokens 1) (not (slotTokenQuoted? tokens 2)) (slotTokenQuoted? tokens 3) (slotTokenQuoted? tokens 4))
                (err "invalid slot ASN")
                (let [(due (stringToInt64 (slotTokenText tokens 1)))
                      (expiry (stringToInt64 (slotTokenText tokens 3)))
                      (attempt (stringToInt64 (slotTokenText tokens 4)))]
                  (match due
                    ((some d)
                      (match expiry
                        ((some e)
                          (match attempt
                            ((some a) (ok (slot (slotTokenText tokens 0) d (slotTokenText tokens 2) e a)))
                            ((none) (err "invalid attempt"))))
                        ((none) (err "invalid expiry"))))
                    ((none) (err "invalid due"))))))
            ((err e) (err e))))
        ((none) (err "invalid slot ASN")))))
