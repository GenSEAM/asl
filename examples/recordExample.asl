(module aslExamples/recordExample
  :x [Cart newCart totalOf addItem clearCart label])

(schema Cart (:f owner String) (:f total Int64))

fn newCart owner: String -> Cart
  (Cart :owner owner :total 0)

fn totalOf c: Cart -> Int64
  c.total

fn addItem c: Cart price: Int64 -> Cart
  (with c :total (+ c.total price))

fn clearCart c: Cart -> Cart
  (with c :total 0)

fn label c: Cart -> String
  (str c.owner ":" (stringFromInt64 c.total))
