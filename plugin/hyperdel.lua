if vim.g.loaded_hyperdel then
	return
end
vim.g.loaded_hyperdel = true

local function complete(arglead)
	local names = vim.tbl_keys(require("hyperdel.config").get().targets)
	table.sort(names)
	return vim.tbl_filter(function(name)
		return vim.startswith(name, arglead)
	end, names)
end

vim.api.nvim_create_user_command("Hy", function(args)
	require("hyperdel").deliver({ targets = args.fargs, line1 = args.line1, line2 = args.line2 })
end, { nargs = "*", range = "%", complete = complete, desc = "Deliver the buffer or range to Telegram targets" })

vim.cmd([[cnoreabbrev <expr> hy v:lua.require'hyperdel.nvim'.expand_hy()]])

vim.api.nvim_create_user_command("HyperdelSetup", function(args)
	require("hyperdel").install_and_login({ force = args.bang })
end, { bang = true, desc = "Install TDLib and log in to Telegram" })

vim.api.nvim_create_user_command("HyperdelLogout", function()
	require("hyperdel").logout()
end, { desc = "Log out of Telegram" })
