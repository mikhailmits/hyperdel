local client = require("hyperdel.tdlib.client")
local config = require("hyperdel.config")
local nvim = require("hyperdel.nvim")

local uv = vim.uv or vim.loop

local M = {}

M.version = "0.1.0"

local timeouts = { offline = 2000, network = 10000, confirm = 30000 }

local state
local intent
local registered = false
local waiting = {}
local pending = {}
local early = {}
local options = {}
local chat_ids = {}
local prompts = {}

local function is_error(obj)
	return obj["@type"] == "error"
end

local function flush(err)
	local list = waiting
	waiting = {}
	for _, cb in ipairs(list) do
		cb(err)
	end
end

local function ask(name, label, read, build)
	prompts[name] = function()
		read(label, function(value)
			if not value or value == "" then
				return flush("login cancelled")
			end
			client.send(build(value), function(res)
				if is_error(res) and client.running() then
					nvim.error(res.message)
					prompts[name]()
				end
			end)
		end)
	end
end

ask("authorizationStateWaitPhoneNumber", "Telegram phone number: ", nvim.input, function(value)
	return { ["@type"] = "setAuthenticationPhoneNumber", phone_number = value }
end)

ask("authorizationStateWaitCode", "Telegram login code: ", nvim.input, function(value)
	return { ["@type"] = "checkAuthenticationCode", code = value }
end)

ask("authorizationStateWaitPassword", "Telegram password: ", nvim.secret, function(value)
	return { ["@type"] = "checkAuthenticationPassword", password = value }
end)

ask("authorizationStateWaitEmailAddress", "Telegram login email: ", nvim.input, function(value)
	return { ["@type"] = "setAuthenticationEmailAddress", email_address = value }
end)

ask("authorizationStateWaitEmailCode", "Telegram email code: ", nvim.input, function(value)
	return {
		["@type"] = "checkAuthenticationEmailCode",
		code = { ["@type"] = "emailAddressAuthenticationCode", code = value },
	}
end)

local function set_parameters()
	local cfg = config.get()
	local v = vim.version()
	local uname = uv.os_uname()
	client.send({
		["@type"] = "setTdlibParameters",
		database_directory = cfg.data_dir .. "/tdlib",
		files_directory = cfg.data_dir .. "/files",
		use_file_database = false,
		use_chat_info_database = true,
		use_message_database = false,
		use_secret_chats = false,
		api_id = cfg.api_id,
		api_hash = cfg.api_hash,
		system_language_code = "en",
		device_model = string.format("Neovim %d.%d.%d", v.major, v.minor, v.patch),
		system_version = uname.sysname .. " " .. uname.release,
		application_version = M.version,
	}, function(res)
		if is_error(res) then
			flush("setTdlibParameters failed: " .. res.message)
		end
	end)
end

local function fail_pending(err)
	local list = pending
	pending = {}
	early = {}
	for _, cb in pairs(list) do
		cb(err)
	end
end

local function log_out()
	intent = "logging_out"
	client.send({ ["@type"] = "logOut" })
end

local function on_auth_state(update)
	state = update.authorization_state["@type"]
	if state == "authorizationStateWaitTdlibParameters" then
		return set_parameters()
	elseif state == "authorizationStateReady" then
		if intent == "logout" then
			return log_out()
		end
		return flush(nil)
	elseif state == "authorizationStateClosed" then
		client.reset()
		state = nil
		chat_ids = {}
		if intent == "logging_out" then
			nvim.notify("logged out")
		end
		intent = nil
		fail_pending("telegram client closed")
		return flush("telegram client closed")
	elseif state == "authorizationStateLoggingOut" or state == "authorizationStateClosing" then
		return
	end
	if intent == "logout" then
		intent = nil
		nvim.notify("not logged in")
		return flush("not logged in")
	end
	if not prompts[state] then
		return flush("unsupported login step " .. state)
	end
	if #waiting > 0 then
		prompts[state]()
	end
end

local function finish(old_id, err)
	local cb = pending[old_id]
	if cb then
		pending[old_id] = nil
		return cb(err)
	end
	early[old_id] = err or false
end

local function register()
	if registered then
		return
	end
	registered = true
	client.on("updateAuthorizationState", on_auth_state)
	client.on("updateOption", function(update)
		options[update.name] = type(update.value) == "table" and update.value.value or nil
	end)
	client.on("updateMessageSendSucceeded", function(update)
		finish(update.old_message_id, nil)
	end)
	client.on("updateMessageSendFailed", function(update)
		local err = type(update.error) == "table" and update.error.message or update.error_message
		finish(update.old_message_id, err or "send failed")
	end)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			client.close_sync(2000)
		end,
	})
end

local function start()
	local cfg = config.get()
	if not cfg.api_id or not cfg.api_hash then
		return false,
			"api_id and api_hash are required: get them at https://my.telegram.org, then pass them to setup() or set HYPERDEL_API_ID and HYPERDEL_API_HASH"
	end
	local ok, err = client.load(cfg.tdjson_path)
	if not ok then
		return false, err
	end
	vim.fn.mkdir(cfg.data_dir, "p")
	client.execute({
		["@type"] = "setLogStream",
		log_stream = {
			["@type"] = "logStreamFile",
			path = cfg.data_dir .. "/tdlib.log",
			max_file_size = 10485760,
			redirect_stderr = false,
		},
	})
	client.execute({ ["@type"] = "setLogVerbosityLevel", new_verbosity_level = cfg.log_level })
	register()
	client.start()
	return true
end

local function when_ready(cb)
	if client.running() and state == "authorizationStateReady" then
		return cb(nil)
	end
	table.insert(waiting, cb)
	if not client.running() then
		local ok, err = start()
		if not ok then
			flush(err)
		end
	elseif prompts[state] and #waiting == 1 then
		prompts[state]()
	end
end

local function load_chats(list, cb)
	client.send({ ["@type"] = "loadChats", chat_list = { ["@type"] = list }, limit = 100 }, function(res)
		if is_error(res) then
			return cb()
		end
		load_chats(list, cb)
	end, timeouts.network)
end

local function get_chat(chat_id, cb, retried)
	client.send({ ["@type"] = "getChat", chat_id = chat_id }, function(chat)
		if not is_error(chat) then
			return cb(chat.id)
		end
		if retried then
			return cb(nil, "chat " .. chat_id .. " not found: " .. chat.message)
		end
		load_chats("chatListMain", function()
			load_chats("chatListArchive", function()
				get_chat(chat_id, cb, true)
			end)
		end)
	end, timeouts.offline)
end

local function resolve(target, cb)
	if chat_ids[target] then
		return cb(chat_ids[target])
	end
	local function done(id, err)
		if id then
			chat_ids[target] = id
		end
		cb(id, err)
	end
	if target == "saved" or target == "me" then
		client.send({ ["@type"] = "getMe" }, function(me)
			if is_error(me) then
				return done(nil, me.message)
			end
			client.send({ ["@type"] = "createPrivateChat", user_id = me.id, force = false }, function(chat)
				if is_error(chat) then
					return done(nil, chat.message)
				end
				done(chat.id)
			end, timeouts.offline)
		end, timeouts.offline)
	elseif type(target) == "string" and target:sub(1, 1) == "@" then
		client.send({ ["@type"] = "searchPublicChat", username = target:sub(2) }, function(chat)
			if is_error(chat) then
				return done(nil, target .. ": " .. chat.message)
			end
			done(chat.id)
		end, timeouts.network)
	elseif tonumber(target) then
		get_chat(tonumber(target), done)
	else
		done(nil, "unknown target " .. tostring(target))
	end
end

local function send_text(chat_id, text, cb)
	client.send({
		["@type"] = "sendMessage",
		chat_id = chat_id,
		input_message_content = {
			["@type"] = "inputMessageText",
			text = { ["@type"] = "formattedText", text = text },
		},
	}, function(message)
		if is_error(message) then
			return cb(message.message)
		end
		if message.sending_state == nil or message.sending_state == vim.NIL then
			return cb(nil)
		end
		if early[message.id] ~= nil then
			local err = early[message.id]
			early[message.id] = nil
			return cb(err or nil)
		end
		pending[message.id] = cb
		vim.defer_fn(function()
			if pending[message.id] == cb then
				pending[message.id] = nil
				cb(string.format("not confirmed after %ds, it may still be delivered", timeouts.confirm / 1000))
			end
		end, timeouts.confirm)
	end, timeouts.offline)
end

function M.text_limit()
	return tonumber(options.message_text_length_max) or 4096
end

function M.deliver(target, text, cb)
	when_ready(function(err)
		if err then
			return cb(err)
		end
		resolve(target, function(chat_id, resolve_err)
			if not chat_id then
				return cb(resolve_err)
			end
			local chunks = nvim.split(text, M.text_limit())
			if #chunks == 0 then
				return cb("nothing to deliver")
			end
			local sent = 0
			local function next_chunk(send_err)
				if send_err then
					return cb(send_err, sent)
				end
				if sent == #chunks then
					return cb(nil, sent)
				end
				sent = sent + 1
				send_text(chat_id, chunks[sent], function(e)
					if e then
						sent = sent - 1
					end
					next_chunk(e)
				end)
			end
			next_chunk()
		end)
	end)
end

function M.login(cb)
	when_ready(function(err)
		if err then
			return cb(err)
		end
		client.send({ ["@type"] = "getMe" }, function(me)
			if is_error(me) then
				return cb(me.message)
			end
			cb(nil, me)
		end, timeouts.offline)
	end)
end

function M.logout()
	if client.running() then
		if state == "authorizationStateReady" then
			return log_out()
		elseif state == "authorizationStateLoggingOut" or state == "authorizationStateClosing" then
			intent = "logging_out"
			return
		elseif prompts[state] then
			return nvim.notify("not logged in")
		end
	end
	intent = "logout"
	if not client.running() then
		local ok, err = start()
		if not ok then
			intent = nil
			nvim.error(err)
		end
	end
end

function M.state()
	return state
end

return M
