schema Item { name: String qty: Int64 unitPrice: Int64 }

fn inventoryTotal items: (List Item) -> Int64
  (listSum (map (fn [it] (* it.qty it.unitPrice)) items))
