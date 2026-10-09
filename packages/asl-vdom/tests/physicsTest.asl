(module aslVdom/tests/physics_test :x [testCoulombRepulsionDirection testEulerDamping testHookeSpringLinearity runTests] :i [(physicsReactor :a pr)])

fn testCoulombRepulsionDirection -> Bool
  (let [(p1 (pr/makeParticle 10.0 0.0)) (p2 (pr/makeParticle 0.0 0.0)) (f (pr/coulombRepulsion p1 p2 1000.0)) (fRev (pr/coulombRepulsion p2 p1 1000.0))] (assert (> f.fx 0.0) "Coulomb repulsion must produce positive fx") (assert (< fRev.fx 0.0) "Opposite particle must be repelled in negative X direction") (assert (not (<= f.fx 0.0)) "Coulomb repulsion must not produce non-positive fx") (assert (not (> fRev.fx 0.0)) "Opposite particle repulsion must not produce positive fx") (assert (not (> f.fy 0.0)) "Pure horizontal repulsion must not produce positive fy") (assert (not (< f.fy 0.0)) "Pure horizontal repulsion must not produce negative fy") true)

fn testEulerDamping -> Bool
  (let [(p1 (pr/Particle :x 0.0 :y 0.0 :vx 10.0 :vy 0.0 :mass 1.0)) (f0 (pr/Force2D :fx 0.0 :fy 0.0)) (p2 (pr/eulerIntegrate p1 f0 1.0 0.9))] (assert (< p2.vx 10.0) "Euler damping must reduce velocity below 10.0") (assert (> p2.vx 0.0) "Damped velocity must remain positive") (assert (not (>= p2.vx 10.0)) "Damped velocity must not stay at or exceed original velocity") (assert (not (< p2.vx 0.0)) "Damped velocity must not invert direction") (assert (not (= p2.vx 10.0)) "Undamped velocity must not persist under damping factor 0.9") true)

fn testHookeSpringLinearity -> Bool
  (let [(p1 (pr/makeParticle 0.0 0.0)) (p2 (pr/makeParticle 10.0 0.0)) (f1 (pr/hookeSpringForce p1 p2 5.0 1.0)) (p3 (pr/makeParticle 5.0 0.0)) (f0 (pr/hookeSpringForce p1 p3 5.0 1.0))] (assert (> f1.fx 0.0) "Spring force on p1 toward p2 must be positive in X") (assert (= f1.fx 50.0) "Spring force fx1 must equal 50.0 for dist 10, rest 5, k 1") (assert (= f1.fy 0.0) "Spring force fy1 must equal 0.0 for horizontal displacement") (assert (= f0.fx 0.0) "At equilibrium rest distance spring force fx must be zero") true)

fn runTests -> Bool
  (and (testCoulombRepulsionDirection) (testEulerDamping) (testHookeSpringLinearity))
