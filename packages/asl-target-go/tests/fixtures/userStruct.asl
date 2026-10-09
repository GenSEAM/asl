(module asl-target-go/tests/fixtures/userStruct :x [User newUser] :i [])

(dfs User (:f id I64) (:f name Str) (:f email Str))

fn newUser id: I64 name: Str email: Str -> User
  (User :id id :name name :email email)
