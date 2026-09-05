(module asl-arduino/examples/blink
  :d "Canonical Arduino Blink LED example in pure AgentScript."
  :x [setup-blink
      step-blink]
  :i [(gpio :a g)])

(df setup-blink [] -> g/Pin
  :d "Configures onboard LED pin 13 as OUTPUT."
  (g/make-pin 13 (g/pin-output)))

(df step-blink [(led g/Pin) (high Bool)] -> g/Pin
  :d "Toggles LED pin level."
  (if high
      (g/write-pin led (g/pin-high))
      (g/write-pin led (g/pin-low))))
