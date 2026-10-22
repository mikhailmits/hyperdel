local M = {}

local after_delivery_modes = { keep = true, clear = true, close = true }

local function defaults()
	return {
		api_id = tonumber(os.getenv("HYPERDEL_API_ID") or ""),
		api_hash = os.getenv("HYPERDEL_API_HASH"),
		default_target = "saved",
		targets = { saved = "saved" },
		after_delivery = "keep",
		on_delivered = nil,
		keymap = nil,
		tdjson_path = nil,
		data_dir = vim.fn.stdpath("data") .. "/hyperdel",
		log_level = 1,
	}
end

local current

function M.setup(opts)
	local merged = vim.tbl_deep_extend("force", defaults(), opts or {})
	merged.api_id = tonumber(merged.api_id)
	if not after_delivery_modes[merged.after_delivery] then
		error("hyperdel: after_delivery must be one of keep, clear, close", 2)
	end
	if merged.on_delivered ~= nil and type(merged.on_delivered) ~= "function" then
		error("hyperdel: on_delivered must be a function", 2)
	end
	current = merged
	return current
end

function M.get()
	return current or M.setup()
end

function M.resolve_target(name)
	local cfg = M.get()
	name = name or cfg.default_target
	return name, cfg.targets[name] or name
end

return M
