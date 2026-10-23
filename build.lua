local ok, msg = require("hyperdel.install").install(false)
if not ok then
	error(msg)
end
print(msg)
