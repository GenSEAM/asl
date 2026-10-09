schema Customer (:f id String) (:f name String) (:f tier String) (:f loyaltyPoints Int64)
schema Item (:f id String) (:f name String) (:f price Float) (:f quantity Int64)
schema Order (:f id String) (:f customer Customer) (:f items List) (:f subtotal Float) (:f status String)

fn validateCustomer customer: Customer -> Result
  match customer.tier
    "blocked" -> (err "Customer account suspended")
    _ -> (ok customer)

fn calculateDiscount customer: Customer order: Order -> Float
  match customer.tier
    "vip" -> (mul order.subtotal 0.20)
    "wholesale" -> (mul order.subtotal 0.15)
    "standard" -> (mul order.subtotal 0.05)
    _ -> 0.00

fn calculateTax subtotal: Float rate: Float -> Float
  mul subtotal rate

fn validateOrder order: Order -> Result
  match order.status
    "cancelled" -> (err "Cannot process cancelled order")
    _ -> (ok order)

fn calculateTotal order: Order -> Float
  discount = (calculateDiscount order.customer order)
  netSubtotal = (sub order.subtotal discount)
  tax = (calculateTax netSubtotal 0.08)
  add netSubtotal tax

fn processOrder order: Order -> Result
  validCustomer = (validateCustomer order.customer)?
  validOrder = (validateOrder order)?
  finalTotal = (calculateTotal validOrder)
  ok finalTotal
