local uv = vim.uv or vim.loop

local M = {}

local frame_ms = 16
local scatter_ms = 150
local gather_ms = 500
local hold_ms = 120
local drip_ms = 600
local land_ms = 90
local gravity = 4

local function ease(t)
	if t < 0.5 then
		return 4 * t * t * t
	end
	local f = 2 * t - 2
	return 1 + f * f * f / 2
end

local function particles(view)
	local list = {}
	for _, cell in ipairs(view.cells) do
		table.insert(list, { ch = cell.ch, w = cell.w, x0 = cell.col, y0 = cell.row, x = cell.col, y = cell.row })
	end
	return list
end

local function aim(list, width, height)
	local cx, cy = (width - 1) / 2, (height - 1) / 2
	local ry = math.min(math.sqrt(#list / (2 * math.pi)), height * 0.3)
	local rx = math.min(ry * 2, width * 0.3)
	for _, p in ipairs(list) do
		local a, d = 2 * math.pi * math.random(), math.sqrt(math.random())
		p.tx = cx + rx * d * math.cos(a)
		p.ty = cy + ry * d * math.sin(a)
		p.gather_at = scatter_ms * math.random()
		p.fall_at = scatter_ms + gather_ms + hold_ms + drip_ms * math.random()
		p.vx = (math.random() * 2 - 1) * width * 0.08
	end
end

local function step(p, t, height)
	if t < p.fall_at then
		local k = ease(math.min(math.max((t - p.gather_at) / gather_ms, 0), 1))
		p.x = p.x0 + (p.tx - p.x0) * k
		p.y = p.y0 + (p.ty - p.y0) * k
		return
	end
	if p.landed_at then
		p.gone = t - p.landed_at > land_ms
		return
	end
	local s = (t - p.fall_at) / 1000
	p.x = p.tx + p.vx * s
	p.y = p.ty + 0.5 * gravity * height * s * s
	if p.y >= height - 1 then
		p.y = height - 1
		p.ch, p.w = ".", 1
		p.landed_at = t
	end
end

local function render(list, width, height)
	local grid = {}
	for _, p in ipairs(list) do
		if not p.gone then
			local r, c = math.floor(p.y + 0.5), math.floor(p.x + 0.5)
			if r >= 0 and r < height and c >= 0 and c + p.w <= width then
				grid[r] = grid[r] or {}
				grid[r][c] = p
			end
		end
	end
	local lines = {}
	for r = 0, height - 1 do
		local cells = grid[r]
		local parts = {}
		if cells then
			local c, last = 0, table.maxn(cells)
			while c <= last do
				local p = cells[c]
				table.insert(parts, p and p.ch or " ")
				c = c + (p and p.w or 1)
			end
		end
		lines[r + 1] = table.concat(parts)
	end
	return lines
end

local function play(ctx, still, finish)
	local view = ctx.view
	if not view or #view.cells == 0 or not vim.api.nvim_win_is_valid(view.win) then
		return finish()
	end
	local width, height = view.width, view.height
	local list = particles(view)
	aim(list, width, height)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].undolevels = -1
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, render(list, width, height))
	local float = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = view.win,
		row = view.winbar,
		col = view.textoff,
		width = width,
		height = height,
		focusable = false,
		style = "minimal",
		noautocmd = true,
		zindex = 60,
	})
	vim.wo[float].winblend = 100
	vim.wo[float].winhighlight = "Normal:Normal,NormalFloat:Normal"

	local start = uv.hrtime()
	local timer = uv.new_timer()
	local done = false
	local function stop()
		done = true
		timer:stop()
		timer:close()
		if vim.api.nvim_win_is_valid(float) then
			vim.api.nvim_win_close(float, true)
		end
		finish()
	end
	timer:start(
		frame_ms,
		frame_ms,
		vim.schedule_wrap(function()
			if done then
				return
			end
			if not vim.api.nvim_win_is_valid(float) or not still() then
				return stop()
			end
			local t = (uv.hrtime() - start) / 1e6
			local alive = false
			for _, p in ipairs(list) do
				step(p, t, height)
				alive = alive or not p.gone
			end
			if not alive then
				return stop()
			end
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, render(list, width, height))
		end)
	)
end

function M.collapse(ctx)
	if not ctx.cleared then
		return
	end
	local tick = vim.api.nvim_buf_get_changedtick(ctx.bufnr)
	play(ctx, function()
		return vim.api.nvim_buf_is_valid(ctx.bufnr) and vim.api.nvim_buf_get_changedtick(ctx.bufnr) == tick
	end, function() end)
end

function M.collapse_quit(ctx)
	if not ctx.closed then
		return
	end
	play(ctx, function()
		return true
	end, function()
		vim.cmd("confirm qall")
	end)
end

return M
