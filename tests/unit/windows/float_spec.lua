local api = vim.api
local floats = require("dapui.windows.float")

describe("floating windows", function()
  local windows, buffers

  local function open()
    local buffer = api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = buffer
    local win = floats.open_float({
      buffer = buffer,
      width = 20,
      height = 4,
      position = { line = 1, col = 1 },
    })
    windows[#windows + 1] = win
    return win, buffer
  end

  before_each(function()
    windows = {}
    buffers = {}
  end)

  after_each(function()
    for _, win in ipairs(windows) do
      if api.nvim_win_is_valid(win.win_id) then
        api.nvim_win_close(win.win_id, true)
      end
    end
    for _, buffer in ipairs(buffers) do
      api.nvim_buf_delete(buffer, { force = true })
    end
  end)

  it("only notifies listeners belonging to the closed window", function()
    local first, first_buffer = open()
    local second, second_buffer = open()
    local first_events, second_events = {}, {}
    first:listen("close", function(event)
      first_events[#first_events + 1] = event
    end)
    second:listen("close", function(event)
      second_events[#second_events + 1] = event
    end)

    assert.True(first:close(true))
    assert.same({ { buffer = first_buffer } }, first_events)
    assert.same({}, second_events)

    assert.True(second:close(true))
    assert.same({ { buffer = first_buffer } }, first_events)
    assert.same({ { buffer = second_buffer } }, second_events)
  end)

  it("notifies close listeners only once", function()
    local win, buffer = open()
    local events = {}
    win:listen("close", function(event)
      events[#events + 1] = event
    end)

    assert.True(win:close(true))
    assert.True(win:close(true))
    assert.same({ { buffer = buffer } }, events)
  end)

  it("does not notify listeners when an active window stays open", function()
    local win, buffer = open()
    local events = {}
    win:listen("close", function(event)
      events[#events + 1] = event
    end)
    api.nvim_set_current_win(win.win_id)

    assert.False(win:close(false))
    assert.same({}, events)
    assert.True(api.nvim_win_is_valid(win.win_id))

    assert.True(win:close(true))
    assert.same({ { buffer = buffer } }, events)
  end)

  it("notifies listeners once when WinClosed also requests cleanup", function()
    local win, buffer = open()
    local events = {}
    win:listen("close", function(event)
      events[#events + 1] = event
    end)
    api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win.win_id),
      once = true,
      callback = function()
        win:close(true)
      end,
    })

    assert.True(win:close(true))
    assert.same({ { buffer = buffer } }, events)
  end)

  it("notifies listeners once after the window is closed externally", function()
    local win = open()
    local count = 0
    win:listen("close", function()
      count = count + 1
    end)
    api.nvim_win_close(win.win_id, true)

    assert.True(win:close(false))
    assert.True(win:close(false))
    assert.equal(1, count)
  end)

  it("can retry closing after a textlock prevents closing the window", function()
    local win, buffer = open()
    local events = {}
    local closed
    win:listen("close", function(event)
      events[#events + 1] = event
    end)
    api.nvim_buf_attach(buffer, false, {
      on_lines = function()
        closed = win:close(true)
        return true
      end,
    })
    api.nvim_buf_set_lines(buffer, 0, -1, false, { "updated" })

    assert.False(closed)
    assert.True(api.nvim_win_is_valid(win.win_id))
    assert.same({}, events)

    assert.True(win:close(true))
    assert.same({ { buffer = buffer } }, events)
  end)
end)
