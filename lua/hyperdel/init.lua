local config = require("hyperdel.config")

local M = {}

local usage = "Hyperdel installed!\n\nUsage examples: hy saved -> publish the whole neovim buffer to Saved Notes\nPress leader+hy to publish to all channels or chats set in a config. (By default only saved messages are setup)\n\nNote: to log in with a QR code, type qr when asked for the phone number or login code."

function M.setup(opts)
	local cfg = config.setup(opts)
	if cfg.keymap then
		vim.keymap.set("n", cfg.keymap, "<cmd>Hy<cr>", { desc = "Deliver buffer to all targets" })
		vim.keymap.set("x", cfg.keymap, ":Hy<cr>", { desc = "Deliver selection to all targets", silent = true })
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

function M.install_and_login(opts)
	opts = opts or {}
	local nvim = require("hyperdel.nvim")
	local install = require("hyperdel.install")
	nvim.notify("installing TDLib " .. install.tdlib_version .. "...")
	vim.cmd("redraw")
	local ok, msg = install.install(opts.force)
	if not ok then
		return nvim.error(msg)
	end
	vim.notify(usage, vim.log.levels.INFO)
	if opts.force then
		return require("hyperdel.telegram").forget(M.login)
	end
	M.login()
end

return M
