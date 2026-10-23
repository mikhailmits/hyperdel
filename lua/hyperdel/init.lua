local config = require("hyperdel.config")

local M = {}

function M.setup(opts)
	local cfg = config.setup(opts)
	if cfg.keymap then
		vim.keymap.set("n", cfg.keymap, "<cmd>Hyperdel<cr>", { desc = "Deliver buffer to Telegram" })
		vim.keymap.set("x", cfg.keymap, ":Hyperdel<cr>", { desc = "Deliver selection to Telegram", silent = true })
	end
end

function M.deliver(opts)
	require("hyperdel.deliver").deliver(opts)
end

function M.login()
	local nvim = require("hyperdel.nvim")
	require("hyperdel.telegram").login(function(err, me)
		if err then
			return nvim.error("login failed: " .. err)
		end
		nvim.notify("logged in as " .. me.first_name)
	end)
end

function M.logout()
	require("hyperdel.telegram").logout()
end

function M.install(opts)
	return require("hyperdel.install").run(opts)
end

return M
