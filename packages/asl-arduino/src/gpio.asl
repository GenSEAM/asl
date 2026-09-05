(module asl-arduino/gpio
  :d "Hardware GPIO control primitives, pin modes, and digital signals for microcontrollers."
  :x [Pin
      make-pin
      set-mode
      write-pin
      read-pin
      pin-output
      pin-input
      pin-high
      pin-low]
  :i [])

(dfs Pin
  (:f num I64 "Digital/Analog pin number")
  (:f mode I64 "1 for output, 0 for input")
  (:f state I64 "Current binary voltage level (1 or 0)"))

(df pin-output [] -> I64 1)
(df pin-input [] -> I64 0)
(df pin-high [] -> I64 1)
(df pin-low [] -> I64 0)

(df make-pin [(pin-num I64) (mode I64)] -> Pin
  :d "Constructs a Pin configuration record."
  (Pin :num pin-num :mode mode :state 0))

(df set-mode [(p Pin) (mode I64)] -> Pin
  :d "Configures pin mode (OUTPUT or INPUT)."
  (Pin :num (.-num p) :mode mode :state (.-state p)))

(df write-pin [(p Pin) (level I64)] -> Pin
  :d "Updates the pin voltage state (HIGH or LOW)."
  (Pin :num (.-num p) :mode (.-mode p) :state level))

(df read-pin [(p Pin)] -> I64
  :d "Reads the current digital state of the pin."
  (.-state p))
