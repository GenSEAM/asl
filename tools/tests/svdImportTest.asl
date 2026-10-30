(module asl/tools/tests/svdImportTest
  :x [runTests]
  :i [(asl/tools/svdImport :a svd)])

fn ! runTests -> Bool
  (do
    (assert (testGpio!) "GPIOA+GPIOB fixture matches the hand table")
    (assert (testSwapped!) "swapped ODR/BSRR offsets fail the hand-table comparison")
    (assert (testMalformed!) "mismatched close tag reports the line")
    true)

fn fixtureXml -> String
  (match (fileReadString "asl/tools/tests/fixtures/stm32f4Gpio.svd")
    ((err _) "")
    ((ok s) s))

fn handTable -> String
  "MODER:0:32,IDR:16:32,ODR:20:32,BSRR:24:32"

fn testGpio! -> Bool
  (match (svd/parseSvd (fixtureXml))
    ((err _) false)
    ((ok ps)
      (match (svd/findPeriph ps "GPIOA")
        ((none) false)
        ((some a)
          (match (svd/findPeriph ps "GPIOB")
            ((none) false)
            ((some b)
              (and (= a.baseAddress 1073872896)
                   (= b.baseAddress 1073873920)
                   (= (stringJoin (svd/regKeys a.registers) ",") (handTable))
                   (= (stringJoin (svd/regKeys b.registers) ",") (handTable))
                   (= (stringJoin (svd/fieldKeysOf a.registers "ODR") ",") "OD5:5:1")
                   (= (stringJoin (svd/fieldKeysOf b.registers "ODR") ",") "OD5:5:1")
                   (match b.derivedFrom ((some base) (= base "GPIOA")) ((none) false)))))))))

fn swappedXml -> String
  (str "<device>\n  <peripherals>\n    <peripheral>\n"
       "      <name>GPIOA</name>\n      <baseAddress>0x40020000</baseAddress>\n      <registers>\n"
       "        <register>\n          <name>ODR</name>\n          <addressOffset>0x18</addressOffset>\n          <size>32</size>\n          <resetValue>0x00000000</resetValue>\n        </register>\n"
       "        <register>\n          <name>BSRR</name>\n          <addressOffset>0x14</addressOffset>\n          <size>32</size>\n          <resetValue>0x00000000</resetValue>\n        </register>\n"
       "      </registers>\n    </peripheral>\n  </peripherals>\n</device>\n")

fn testSwapped! -> Bool
  (match (svd/parseSvd (swappedXml))
    ((err _) false)
    ((ok ps)
      (match (svd/findPeriph ps "GPIOA")
        ((none) false)
        ((some a)
          (not (= (stringJoin (svd/regKeys a.registers) ",") "ODR:20:32,BSRR:24:32"))))))

fn malformedXml -> String
  (str "<device>\n  <peripherals>\n    <peripheral>\n      <name>X</name>\n      </register>\n    </peripheral>\n  </peripherals>\n</device>\n")

fn testMalformed! -> Bool
  (match (svd/parseSvd (malformedXml))
    ((ok _) false)
    ((err e) (stringContains? e "line 5")))
