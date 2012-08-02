-- Requires xkb-switch binary under $PATH.
-- https://github.com/ierton/xkb-switch/

local defaults = {
  update_interval = 100,
  xkb_switch = 'xkb-switch',
  syms_map = {},
}
local settings = table.join(statusd.get_config('xkblayout'), defaults)
local timer = statusd.create_timer()

local function current_layout()
  local p = io.popen(settings.xkb_switch)
  layout = p:read()
  p:close()
  return settings.syms_map[layout] or layout
end

function update_xkblayout()
  statusd.inform('xkblayout', current_layout())
  timer:set(settings.update_interval, update_xkblayout)
end
update_xkblayout()
