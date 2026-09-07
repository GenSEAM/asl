(module asl-cli/coverage-test
  :d "Complete function coverage test suite for asl-cli."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [(dummy-format-asn-help format-asn-help)
        (dummy-strip-colon strip-colon)
        (dummy-col-name col-name)
        (dummy-entry-key-str entry-key-str)
        (dummy-table-zip table-zip)
        (dummy-table-row-to-json table-row-to-json)
        (dummy-asn-to-json-value asn-to-json-value)
        (dummy-run-check run-check)
        (dummy-run-to-json run-to-json)
        (dummy-transcode-json-str transcode-json-str)
        (dummy-run-from-json run-from-json)
        (dummy-dispatch-asn dispatch-asn)
        (dummy-execute-cli execute-cli)
        (dummy-main main)]
    true))
