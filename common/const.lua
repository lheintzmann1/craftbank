-- Global constants shared by every node.
-- Money is stored as INTEGER "cents": 100 cents = 1.00 Cr (the display unit).
-- 1 diamond = 1000.00 Cr = 100000 cents.
local C = {}

C.CURRENCY_NAME   = "Crown"
C.CURRENCY_SYMBOL = "Cr"
C.SCALE           = 100            -- cents per Cr
C.DIAMOND         = 1000 * 100     -- value of 1 diamond, in cents
C.PROTOCOL        = "craftbank"    -- rednet protocol name

return C
