local dap = require("dap")
local nio = require("nio")
local util = require("dapui.util")
local types = require("dapui.client.types")

---@alias dap.Session Session

---@class dapui.DAPClient
---@field request dapui.DAPRequestsClient
---@field listen dapui.DAPEventListenerClient
---@field session? dapui.SessionProxy
---@field lib dapui.DAPClientLib
---@field breakpoints dapui.BreakpointsProxy
local DAPUIClient = {}
local next_client_id = 0

---@class dapui.SessionProxy
---@field current_frame? dapui.types.StackFrame
---@field _frame_set fun(frame: dapui.types.StackFrame)
---@field stopped_thread_id integer
---@field capabilities dapui.types.Capabilities
---@field threads table<integer, dapui.types.Thread>

local proxied_session_keys = {}
for _, key in ipairs({
  "current_frame",
  "_frame_set",
  "stopped_thread_id",
  "capabilities",
  "threads",
}) do
  proxied_session_keys[key] = true
end

---@return dapui.SessionProxy
local function create_session_proxy(session)
  return setmetatable({}, {
    __index = function(_, key)
      if not proxied_session_keys[key] then
        return nil
      end
      local value = session[key]
      if type(value) == "function" then
        return function(...)
          return value(session, ...)
        end
      end
      return value
    end,
  })
end

---@class dapui.client.BreakpointArgs{
---@field condition? string
---@field hit_condition? string
---@field log_message? string

---@class dapui.BreakpointsProxy
---@field get fun(): table<integer, dapui.types.DAPBreakpoint[]>
---@field get_buf fun(bufnr: integer): dapui.types.DAPBreakpoint[]
---@field toggle fun(bufnr: integer, line: integer, args: dapui.client.BreakpointArgs)
---@field remove fun(bufnr: integer, line: integer)

---@return dapui.BreakpointsProxy
local function create_breakpoints_proxy(breakpoints, session_factory)
  local proxy = {}
  local function refresh(bufnr)
    local bps = breakpoints.get(bufnr)
    local session = session_factory()
    if session then
      session:set_breakpoints(bps)
    end
  end

  proxy.get = function()
    return breakpoints.get()
  end
  proxy.get_buf = function(bufnr)
    return breakpoints.get(bufnr)
  end
  proxy.toggle = function(bufnr, line, args)
    breakpoints.toggle(args, bufnr, line)
    refresh(bufnr)
  end
  proxy.remove = function(bufnr, line)
    breakpoints.remove(bufnr, line)
    refresh(bufnr)
  end
  return proxy
end

local Error = function(err, args)
  local err_tbl = vim.tbl_extend("keep", err, args or {})
  err_tbl.traceback = debug.traceback("test", 2)
  return setmetatable(err_tbl, {
    __tostring = function()
      local formatted = util.format_error(err)
      local message = ("DAP error: %s"):format(formatted)
      for name, value in pairs(args) do
        message = message
          .. ("\n%s: %s"):format(name, type(value) ~= "table" and value or vim.inspect(value))
      end
      message = message .. "\n" .. err_tbl.traceback
      return message
    end,
  })
end

---@param session_factory fun(): dap.Session
---@return dapui.DAPClient
local function create_client(session_factory, breakpoints)
  breakpoints = breakpoints or require("dap.breakpoints")
  local request_seqs = setmetatable({}, { __mode = "k" })
  local async_request = nio.wrap(function(command, args, cb)
    local session = session_factory()
    request_seqs[session] = request_seqs[session] or {}
    local pending = request_seqs[session]
    local seq = session.seq
    pending[seq] = true
    local function clear_request()
      pending[seq] = nil
      if next(pending) == nil and request_seqs[session] == pending then
        request_seqs[session] = nil
      end
    end
    local success, err = pcall(session.request, session, command, args, function(...)
      -- nvim-dap invokes its after-listeners after this callback. Keep the
      -- marker until both listener phases have finished to avoid feedback.
      vim.schedule(clear_request)
      cb(...)
    end)
    if not success then
      clear_request()
      error(err, 0)
    end
  end, 3)

  local request = setmetatable({}, {
    __index = function(_, command)
      return function(args)
        local start = vim.loop.now()
        local err, body = async_request(command, args)
        local diff = vim.loop.now() - start
        if err then
          error(Error(err, { command = command, args = args }))
        elseif body.error then
          error(Error(body.err, { command = command, args = args }))
        end
        return body
      end
    end,
  })

  -- Multiple clients can be constructed within the same event-loop tick.
  next_client_id = next_client_id + 1
  local listener_prefix = "DAPClient" .. next_client_id .. ":"
  local listener_count = 0
  local listener_ids = {}
  local listen = setmetatable({}, {
    __index = function(_, event)
      return function(listener, opts)
        opts = opts or {}
        local listeners
        if opts.before then
          listeners = dap.listeners.before
        else
          listeners = dap.listeners.after
        end
        local listener_id = listener_prefix .. tostring(listener_count)
        listener_count = listener_count + 1
        local is_event = not types.request[event]
        local key = is_event and "event_" .. event or event
        listener_ids[#listener_ids + 1] = { key, listener_id }

        local wrap = function(inner)
          listeners[key][listener_id] = function(session, ...)
            if inner(session, ...) then
              listeners[key][listener_id] = nil
            end
          end
        end

        if is_event then
          wrap(function(_, ...)
            return listener(...)
          end)
        else
          wrap(function(session, err, body, req, req_seq)
            if (request_seqs[session] or {})[req_seq] then
              return
            end
            return listener({ error = err, response = body, request = req })
          end)
        end
      end
    end,
  })

  local client = setmetatable({
    breakpoints = create_breakpoints_proxy(breakpoints, session_factory),
    request = request,
    listen = listen,
    shutdown = function()
      for _, listener in ipairs(listener_ids) do
        dap.listeners.before[listener[1]][listener[2]] = nil
        dap.listeners.after[listener[1]][listener[2]] = nil
      end
    end,
  }, {
    __index = function(_, key)
      if key == "session" then
        local session = session_factory()
        if not session then
          return nil
        end
        return create_session_proxy(session)
      end
    end,
  })
  client.lib = require("dapui.client.lib")(client)
  return client
end

return create_client
