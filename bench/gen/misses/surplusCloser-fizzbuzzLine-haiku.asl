fn divisibleBy n: Int64 d: Int64 -> Bool
  (< (- n (* (/ n d) d)) 1)

fn digitChar d: Int64 -> String
  (cond
    ((< d 1) "0")
    ((< d 2) "1")
    ((< d 3) "2")
    ((< d 4) "3")
    ((< d 5) "4")
    ((< d 6) "5")
    ((< d 7) "6")
    ((< d 8) "7")
    ((< d 9) "8")
    (else "9"))

fn decimalText n: Int64 -> String
  (cond
    ((< n 10) (digitChar n))
    (else (stringConcat (decimalText (/ n 10)) (digitChar (- n (* (/ n 10) 10))))))

fn fizzbuzzLine n: Int64 -> String
  (cond
    ((and (divisibleBy n 3) (divisibleBy n 5)) "FizzBuzz")
    ((divisibleBy n 3) "Fizz")
    ((divisibleBy n 5) "Buzz")
    (else (decimalText n)))
