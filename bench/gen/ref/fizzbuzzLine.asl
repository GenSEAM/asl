fn fizzbuzzLine n: Int64 -> String
  (cond
    ((= (mod n 15) 0) "FizzBuzz")
    ((= (mod n 3) 0) "Fizz")
    ((= (mod n 5) 0) "Buzz")
    (else (stringFromInt64 n)))
