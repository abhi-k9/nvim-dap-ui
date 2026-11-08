local dap = require("dap")
local dapui = require("dapui")

describe("repeated setup", function()
  local listener_key = "dapui_setup_spec"

  local function listener_count()
    local count = 0
    for _, phase in ipairs({ "before", "after" }) do
      for _, listeners in pairs(dap.listeners[phase]) do
        for key in pairs(listeners) do
          if type(key) == "string" and key:match("^DAPClient") then
            count = count + 1
          end
        end
      end
    end
    return count
  end

  after_each(function()
    require("dapui.util").stop_render_tasks()
    dap.listeners.before.event_stopped[listener_key] = nil
    dap.listeners.after.event_stopped[listener_key] = nil
  end)

  it("replaces element listeners without removing other plugins' listeners", function()
    local external_listener = function() end
    dap.listeners.before.event_stopped[listener_key] = external_listener
    dap.listeners.after.event_stopped[listener_key] = external_listener

    dapui.setup({ controls = { enabled = false } })
    local before = listener_count()
    assert.True(before > 0)
    for _ = 1, 5 do
      -- Exercise setup across event-loop ticks, as when reloading a config.
      vim.wait(10, function()
        return false
      end, 1)
      dapui.setup({ controls = { enabled = false } })
      assert.equal(before, listener_count())
      assert.equal(external_listener, dap.listeners.before.event_stopped[listener_key])
      assert.equal(external_listener, dap.listeners.after.event_stopped[listener_key])
    end
  end)
end)
