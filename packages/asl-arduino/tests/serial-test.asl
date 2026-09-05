(module asl-arduino/tests/serial-test
  :d "Unit tests for embedded UART serial interface."
  :x [test-init-serial test-serial-println run-tests]
  :i [(serial :a s)])

(df test-init-serial [] -> Bool
  :d "Verifies serial port initialization."
  (let [(port (s/init-serial 115200))]
    (and (= (.-baud port) 115200)
         (.-open port))))

(df test-serial-println [] -> Bool
  :d "Verifies string payload formatted with trailing newline."
  (let [(port (s/init-serial 9600))
        (out (s/serial-println port "PING"))]
    (= out "PING\n")))

(df run-tests [] -> Bool
  :d "Runs all Serial unit tests."
  (and (test-init-serial)
       (test-serial-println)))
