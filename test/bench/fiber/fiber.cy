use os

var start = os.now()

var .count = 0

func inc() dyn:
    count += 1
    coyield
    count += 1

var fibers = {_}
for 0..100000:
    var f = coinit(inc)
    coresume f
    fibers.append(f)

for fibers -> f:
    coresume f

print("time: $((os.now() - start) * 1000)")
print(count)