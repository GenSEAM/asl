(module asl-arduino/tests/gpio-test
  :d "Unit tests for GPIO pin modes and signal toggling."
  :x [test-make-pin test-write-pin test-read-pin test-blink-example run-tests]
  :i [(gpio :a g)
      (examples/blink :a b)])

(df test-make-pin [] -> Bool
  :d "Verifies pin allocation defaults."
  (let [(p (g/make-pin 13 (g/pin-output)))]
    (and (= (.-num p) 13)
         (and (= (.-mode p) 1)
              (= (.-state p) 0)))))

(df test-write-pin [] -> Bool
  :d "Verifies digital signal write updates state."
  (let [(p0 (g/make-pin 13 (g/pin-output)))
        (p1 (g/write-pin p0 (g/pin-high)))]
    (= (.-state p1) 1)))

(df test-read-pin [] -> Bool
  :d "Verifies reading pin voltage level."
  (let [(p0 (g/make-pin 2 (g/pin-input)))
        (p1 (g/write-pin p0 (g/pin-high)))]
    (= (g/read-pin p1) 1)))

(df test-blink-example [] -> Bool
  :d "Verifies standard Blink sketch state transitions."
  (let [(led0 (b/setup-blink))
        (led1 (b/step-blink led0 true))
        (led2 (b/step-blink led1 false))]
    (and (= (.-state led1) 1)
         (= (.-state led2) 0))))

(df run-tests [] -> Bool
  :d "Runs all GPIO unit tests."
  (and (test-make-pin)
       (and (test-write-pin)
            (and (test-read-pin)
                 (test-blink-example)))))
