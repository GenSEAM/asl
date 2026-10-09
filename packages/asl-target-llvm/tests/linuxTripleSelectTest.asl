(module asl-target-llvm/tests/linuxTripleSelectTest
  :x [runTests]
  :i [])

fn tripleStrategy unameS: String unameM: String platform: String dockerUp: Bool -> String
  (let [(hostPlatform
          (if (= unameS "Linux")
            (cond
              ((or (= unameM "x86_64") (= unameM "amd64")) "linux/amd64")
              ((or (= unameM "aarch64") (= unameM "arm64")) "linux/arm64")
              (else ""))
            ""))]
    (cond
      ((= hostPlatform platform) "native")
      (dockerUp "docker")
      (else "missingDocker")))

fn ! runTests -> Bool
  (do
    (assert (= (tripleStrategy "Darwin" "arm64" "linux/arm64" true) "docker") "darwin/arm64 dockerUp picks docker for linux/arm64")
    (assert (= (tripleStrategy "Darwin" "arm64" "linux/amd64" true) "docker") "darwin/arm64 dockerUp picks docker for linux/amd64")
    (assert (= (tripleStrategy "Darwin" "x86_64" "linux/arm64" false) "missingDocker") "darwin/x86_64 dockerDown picks missingDocker for linux/arm64")
    (assert (= (tripleStrategy "Darwin" "x86_64" "linux/amd64" false) "missingDocker") "darwin/x86_64 dockerDown picks missingDocker for linux/amd64")
    (assert (= (tripleStrategy "Linux" "x86_64" "linux/amd64" true) "native") "linux/x86_64 matches linux/amd64: native even with docker up")
    (assert (= (tripleStrategy "Linux" "x86_64" "linux/amd64" false) "native") "linux/x86_64 matches linux/amd64: native even with docker down")
    (assert (= (tripleStrategy "Linux" "x86_64" "linux/arm64" true) "docker") "linux/x86_64 does not match linux/arm64, docker up: docker")
    (assert (= (tripleStrategy "Linux" "x86_64" "linux/arm64" false) "missingDocker") "linux/x86_64 does not match linux/arm64, docker down: missingDocker")
    (assert (= (tripleStrategy "Linux" "aarch64" "linux/arm64" false) "native") "linux/aarch64 matches linux/arm64: native even with docker down")
    (assert (= (tripleStrategy "Linux" "aarch64" "linux/amd64" true) "docker") "linux/aarch64 does not match linux/amd64, docker up: docker")
    (assert (= (tripleStrategy "Linux" "aarch64" "linux/amd64" false) "missingDocker") "linux/aarch64 does not match linux/amd64, docker down: missingDocker")
    (assert (= (tripleStrategy "Linux" "amd64" "linux/amd64" false) "native") "uname -m amd64 spelling also matches linux/amd64 natively")
    true)
