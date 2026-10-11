(module demo/metaTags  (:tag :arch "d-1eed" :spec "sec-08" :d "m-meta-tags") :x [User Role verifyCredentials])

(schema User (:tag :model "db-user" :arch "d-4a1b") (:f id Int64 "Unique user identifier" (:tag :pk "true")) (:f username String "User login handle") (:f active Bool "Whether account is active" :default true))

(enum Role (:tag :domain "auth-roles") (:c admin [] "Administrator role" (:tag :level "super")) (:c guest [] "Guest role" (:tag :level "public")))

fn verifyCredentials user: User token: String -> Bool
  (do (:tag :inv "constant-time" :perf "p-120us" :doc "fn-verify-creds") (if user.active true false))

(:tag :global "provenance" :source "system")
