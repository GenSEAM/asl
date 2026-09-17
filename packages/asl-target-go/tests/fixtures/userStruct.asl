(module asl-target-go/tests/fixtures/userStruct
  :d "Localized user struct and constructor fixture for Go target code emission."
  :x [User newUser]
  :i [])

(dfs User
  (:f id I64 "Unique user identifier")
  (:f name Str "User full name")
  (:f email Str "User email address"))

(df newUser [(id I64) (name Str) (email Str)] -> User
  :d "Constructs a new User struct instance."
  (User :id id :name name :email email))
