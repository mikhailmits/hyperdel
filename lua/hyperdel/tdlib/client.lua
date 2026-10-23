local ffi = require("ffi")
local library = require("hyperdel.tdlib.library")

local uv = vim.uv or vim.loop

local M = {}

local lib
local client_id
local timer
local next_extra = 0
local callbacks = {}
local handlers = {}

local function decode(raw)
	return vim.json.decode(ffi.string(raw))
end

local function dispatch(event)
	local extra = event["@extra"]
	local cb = extra ~= nil and callbacks[extra]
	if cb then
		callbacks[extra] = nil
		return cb(event)
	end
	for _, handler in ipairs(handlers[event["@type"]] or {}) do
		handler(event)
	end
end

local function poll()
	while lib and client_id do
		local raw = lib.td_receive(0)
		if raw == nil then
			return
		end
		local event = decode(raw)
		if event["@client_id"] == nil or event["@client_id"] == client_id then
			local ok, err = pcall(dispatch, event)
			if not ok then
				vim.notify("hyperdel: " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end
end

function M.load(path)
	if lib then
		return true
	end
	local loaded, err = library.load(path)
	if not loaded then
		return false, err
	end
	lib = loaded
	return true
end

function M.execute(request)
	local raw = lib.td_execute(vim.json.encode(request))
	if raw == nil then
		return nil
	end
	return decode(raw)
end

function M.running()
	return client_id ~= nil
end

function M.start()
	if client_id then
		return
	end
	client_id = lib.td_create_client_id()
	timer = uv.new_timer()
	timer:start(0, 50, vim.schedule_wrap(poll))
	M.send({ ["@type"] = "getOption", name = "version" })
end

function M.reset()
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	client_id = nil
	callbacks = {}
end

function M.send(request, cb)
	if cb then
		next_extra = next_extra + 1
		request["@extra"] = next_extra
		callbacks[next_extra] = cb
	end
	lib.td_send(client_id, vim.json.encode(request))
end

function M.on(type, handler)
	handlers[type] = handlers[type] or {}
	table.insert(handlers[type], handler)
end

function M.close_sync(timeout_ms)
	if not client_id then
		return
	end
	local id = client_id
	lib.td_send(id, vim.json.encode({ ["@type"] = "close" }))
	local deadline = uv.hrtime() + timeout_ms * 1e6
	while uv.hrtime() < deadline do
		local raw = lib.td_receive(0.1)
		if raw ~= nil then
			local event = decode(raw)
			if
				event["@client_id"] == id
				and event["@type"] == "updateAuthorizationState"
				and event.authorization_state["@type"] == "authorizationStateClosed"
			then
				break
			end
		end
	end
	M.reset()
end

return M
