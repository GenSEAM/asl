enum Light (red) (green) (yellow)

fn changeOnce light: Light -> Light
  (match light
    ((red) (green))
    ((green) (yellow))
    ((yellow) (red)))

fn trafficLightNext light: Light steps: Int64 -> Light
  (if (= steps 0) light (trafficLightNext (changeOnce light) (- steps 1)))
