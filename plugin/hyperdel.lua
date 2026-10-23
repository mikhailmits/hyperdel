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

vim.api.nvim_create_user_command("Hyperdel", function(args)
	require("hyperdel").deliver({ target = args.fargs[1], line1 = args.line1, line2 = args.line2 })
end, { nargs = "?", range = "%", complete = complete, desc = "Deliver the buffer or range to Telegram" })

vim.api.nvim_create_user_command("HyperdelLogin", function()
	require("hyperdel").login()
end, { desc = "Log in to Telegram" })

vim.api.nvim_create_user_command("HyperdelLogout", function()
	require("hyperdel").logout()
end, { desc = "Log out of Telegram" })

vim.api.nvim_create_user_command("HyperdelInstall", function(args)
	require("hyperdel").install({ force = args.bang })
end, { bang = true, desc = "Download the prebuilt TDLib library" })
