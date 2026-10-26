local M = {}

local after_delivery_modes = { keep = true, clear = true, close = true }

local function defaults()
	return {
		api_id = tonumber(os.getenv("HYPERDEL_API_ID") or ""),
		api_hash = os.getenv("HYPERDEL_API_HASH"),
		targets = { saved = "saved" },
		after_delivery = "keep",
		animation = true,
		on_delivered = nil,
		keymap = "<leader>hy",
		tdjson_path = nil,
		data_dir = vim.fn.stdpath("data") .. "/hyperdel",
		log_level = 1,
	}
end

local current

function M.setup(opts)
	opts = opts or {}
	local merged = vim.tbl_deep_extend("force", defaults(), opts)
	merged.targets = opts.targets or merged.targets
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

function M.resolve_targets(names)
	local cfg = M.get()
	if not names or #names == 0 then
		names = vim.tbl_keys(cfg.targets)
		table.sort(names)
	end
	local list, seen = {}, {}
	for _, name in ipairs(names) do
		local chat = cfg.targets[name] or name
		if not seen[tostring(chat)] then
			seen[tostring(chat)] = true
			table.insert(list, { name = name, chat = chat })
		end
	end
	return list
end

return M
