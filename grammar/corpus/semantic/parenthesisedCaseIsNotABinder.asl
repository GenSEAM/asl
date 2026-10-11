fn code e: IoError -> Int64
  (match e ((notFound) 1) ((interrupted) 2))
