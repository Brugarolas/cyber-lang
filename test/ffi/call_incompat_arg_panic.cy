use os 'os'

var libPath ?String = none
if os.system == 'macos':
  -- rdynamic doesn't work atm for MacOS.
  libPath = 'test/ffi/macos_lib.dylib'
else os.system == 'windows':
  libPath = 'test/ffi/win_lib.dll'

var ffi = os.newFFI()
ffi.cfunc('testAdd', {symbol.int, symbol.int}, symbol.int)
let lib = ffi.bindLib(libPath)
lib.testAdd(123, '321')

--cytest: error
--panic: Can not find compatible method for call: `(BindLib1) testAdd(int, String)`.
--Methods named `testAdd`:
--    func testAdd(any, int, int) int
--
--main:13:1 main:
--lib.testAdd(123, '321')
--^
--