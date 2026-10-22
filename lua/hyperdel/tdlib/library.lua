local ffi = require("ffi")

ffi.cdef([[
int td_create_client_id();
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
]])

local M = {}

local lib

function M.filename()
	if ffi.os == "Windows" then
		return "tdjson.dll"
	elseif ffi.os == "OSX" then
		return "libtdjson.dylib"
	end
	return "libtdjson.so"
end

function M.install_dir()
	return vim.fn.stdpath("data") .. "/hyperdel/lib"
end

function M.candidates(path)
	local file = M.filename()
	local list = {}
	if path then
		table.insert(list, vim.fn.expand(path))
	end
	table.insert(list, M.install_dir() .. "/" .. file)
	table.insert(list, "tdjson")
	if ffi.os == "OSX" then
		table.insert(list, "/opt/homebrew/lib/" .. file)
		table.insert(list, "/usr/local/lib/" .. file)
	end
	return list
end

function M.load(path)
	if lib then
		return lib
	end
	local errors = {}
	for _, candidate in ipairs(M.candidates(path)) do
		local ok, loaded = pcall(ffi.load, candidate)
		if ok then
			lib = loaded
			M.path = candidate
			return lib
		end
		table.insert(errors, candidate .. ": " .. tostring(loaded))
	end
	return nil, "tdjson library not found, run :HyperdelInstall or set tdjson_path\n" .. table.concat(errors, "\n")
end

return M
