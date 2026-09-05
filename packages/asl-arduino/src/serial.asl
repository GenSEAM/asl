(module asl-arduino/serial
  :d "Hardware UART Serial communications driver for embedded platforms."
  :x [SerialPort
      init-serial
      serial-print
      serial-println]
  :i [])

(dfs SerialPort
  (:f baud I64 "Serial transmission baud rate")
  (:f open Bool "Port connection status"))

(df init-serial [(baud I64)] -> SerialPort
  :d "Initializes UART serial configuration."
  (SerialPort :baud baud :open true))

(df serial-print [(port SerialPort) (msg Str)] -> Str
  :d "Transmits string payload over UART channel."
  msg)

(df serial-println [(port SerialPort) (msg Str)] -> Str
  :d "Transmits string payload with linefeed."
  (str msg "\n"))
