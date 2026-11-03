(module asl-cli/tests/nativeColdFixture
  :x [coldBuildS])

; (:m :ref FORMS-PINNED-CLI :do "the seconds a test lets a scratch checkout build its native CLI from cold: 18 min on a quiet node2 and more than 25 under load, so 5400; relayPinTest and formsPinTest both read it, a shorter literal in either killed the build and left no head")
fn coldBuildS -> Int64
  5400
