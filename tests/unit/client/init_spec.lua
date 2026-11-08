local dap = require("dap")
local nio = require("nio")
local Client = require("dapui.client")

local function emit(phase, session, seq, body)
  for _, listener in pairs(dap.listeners[phase].evaluate) do
    listener(session, nil, body or {}, {}, seq)
  end
end

local function session()
  local result = { seq = 1, pending = {} }
  function result:request(command, args, callback)
    local seq = self.seq
    self.seq = seq + 1
    self.pending[seq] = callback
  end
  function result:respond(seq, err)
    local body = { result = tostring(seq) }
    emit("before", self, seq, body)
    local callback = self.pending[seq]
    self.pending[seq] = nil
    callback(err, body, seq)
    emit("after", self, seq, body)
  end
  return result
end

describe("DAP client lifecycle", function()
  local clients
  local function client(factory)
    local result = Client(factory)
    clients[#clients + 1] = result
    return result
  end
  before_each(function()
    clients = {}
  end)
  after_each(function()
    for _, instance in ipairs(clients) do
      instance.shutdown()
    end
  end)

  it("keeps same-tick clients' listeners independent during shutdown", function()
    local first = client(function() end)
    local second = client(function() end)
    local counts = { 0, 0 }
    first.listen.evaluate(function()
      counts[1] = counts[1] + 1
    end)
    second.listen.evaluate(function()
      counts[2] = counts[2] + 1
    end)
    emit("after", {}, 1)
    assert.same({ 1, 1 }, counts)
    first.shutdown()
    emit("after", {}, 2)
    assert.same({ 1, 2 }, counts)
  end)

  nio.tests.it("handles out-of-order responses and releases completed request markers", function()
    local s = session()
    local c = client(function()
      return s
    end)
    local notifications = { before = 0, after = 0 }
    for _, phase in ipairs({ "before", "after" }) do
      c.listen.evaluate(function()
        notifications[phase] = notifications[phase] + 1
      end, { before = phase == "before" })
    end
    local results = {}
    for index = 1, 2 do
      nio.run(function()
        results[index] = c.request.evaluate({ expression = tostring(index) }).result
      end)
    end
    s:respond(2)
    s:respond(1)
    assert.same({ "1", "2" }, results)
    assert.same({ before = 0, after = 0 }, notifications)
    nio.sleep(1)
    -- Once delivery finishes, neither sequence remains marked as an owned request.
    for seq = 1, 2 do
      emit("before", s, seq)
      emit("after", s, seq)
    end
    assert.same({ before = 2, after = 2 }, notifications)
  end)

  nio.tests.it("tracks responses by their originating session after switching sessions", function()
    local first, second = session(), session()
    local active = first
    local c = client(function()
      return active
    end)
    local notifications = 0
    c.listen.evaluate(function()
      notifications = notifications + 1
    end, { before = true })
    nio.run(function()
      c.request.evaluate({})
    end)
    active = second
    emit("before", second, 1)
    assert.equal(1, notifications)
    first:respond(1)
    assert.equal(1, notifications)
    nio.sleep(1)
  end)

  nio.tests.it("cleans up failed requests without suppressing later notifications", function()
    local s = session()
    local c = client(function()
      return s
    end)
    local success
    local notifications = 0
    c.listen.evaluate(function()
      notifications = notifications + 1
    end)
    nio.run(function()
      success = pcall(c.request.evaluate, {})
    end)
    s:respond(1, { message = "adapter failure" })
    assert.False(success)
    assert.equal(0, notifications)
    nio.sleep(1)
    emit("after", s, 1)
    assert.equal(1, notifications)
  end)

  nio.tests.it("cleans up a request that throws before sending", function()
    local s = {
      seq = 1,
      request = function()
        error("send failed")
      end,
    }
    local c = client(function()
      return s
    end)
    local notifications = 0
    c.listen.evaluate(function()
      notifications = notifications + 1
    end, { before = true })
    assert.False(pcall(c.request.evaluate, {}))
    emit("before", s, 1)
    assert.equal(1, notifications)
  end)
end)
