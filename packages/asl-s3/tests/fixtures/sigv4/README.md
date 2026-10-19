# AWS SigV4 fixtures

Except for `get-space`, these request, canonical-request, string-to-sign, signature, and context files are copied from the AWS C-auth SigV4 signing test suite. Source path: github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4. `get-space` is from `aws-c-auth/tests/aws-sig-v4-test-suite/normalize-path/get-space`.

| Case | Source path |
|---|---|
| get-vanilla | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/get-vanilla |
| get-vanilla-query-order-key-case | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/get-vanilla-query-order-key-case |
| get-header-value-trim | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/get-header-value-trim |
| get-utf8 | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/get-utf8 |
| post-x-www-form-urlencoded | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/post-x-www-form-urlencoded |
| get-vanilla-query-unreserved | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/get-vanilla-query-unreserved |
| post-header-key-sort | github.com/awslabs/aws-c-auth/tests/aws-signing-test-suite/v4/post-header-key-sort |
| get-space | github.com/awslabs/aws-c-auth/tests/aws-sig-v4-test-suite/normalize-path/get-space |

The vectors use the suites' example credentials (AKIDEXAMPLE).
