local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local fail = health.error or health.report_error
local info = health.info or health.report_info

local min_tdlib = "1.8.6"

local function older(a, b)
	local x = vim.split(a, ".", { plain = true })
	local y = vim.split(b, ".", { plain = true })
	for i = 1, 3 do
		local p, q = tonumber(x[i]) or 0, tonumber(y[i]) or 0
		if p ~= q then
			return p < q
		end
	end
	return false
end

function M.check()
	start("hyperdel")

	local v = vim.version()
	local version = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	if vim.fn.has("nvim-0.8") == 1 then
		ok("Neovim " .. version)
	else
		fail("Neovim " .. version .. " is too old, 0.8 or newer is required")
	end

	local cfg = require("hyperdel.config").get()
	if cfg.api_id and cfg.api_hash then
		ok("api_id and api_hash are set")
	else
		fail("api_id and api_hash are missing", {
			"get them at https://my.telegram.org",
			"pass them to setup() or set HYPERDEL_API_ID and HYPERDEL_API_HASH",
		})
	end

	local client = require("hyperdel.tdlib.client")
	local loaded, err = client.load(cfg.tdjson_path)
	if not loaded then
		fail(err, { "run :HyperdelSetup, or set tdjson_path in setup()" })
	else
		local path = require("hyperdel.tdlib.library").path
		local option = client.execute({ ["@type"] = "getOption", name = "version" })
		local tdlib = option and option.value
		if type(tdlib) ~= "string" then
			warn("TDLib loaded from " .. path .. ", but its version could not be read")
		elseif older(tdlib, min_tdlib) then
			fail("TDLib " .. tdlib .. " from " .. path .. " is too old, " .. min_tdlib .. " or newer is required")
		else
			ok("TDLib " .. tdlib .. " loaded from " .. path)
		end
	end

	local names = vim.tbl_keys(cfg.targets)
	table.sort(names)
	info("targets: " .. table.concat(names, ", "))
	info("session: " .. (require("hyperdel.telegram").state() or "not started"))
end

return M
