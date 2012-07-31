local defaults = {
  update_interval = 2 * 1000,
  bat_no = 1,
  thresholds = {
    full        = {  0,   0,   0,   0},
    charging    = {  4,  22,  67, 100},
    discharging = {  6,  16,  40, 100},
  },
  blink_pattern = {250, 1750},
}
local settings = table.join(statusd.get_config('battery'), defaults)

local function getsysbase()
  if settings.bat_no then
    return '/sys/class/power_supply/BAT' .. settings.bat_no .. '/'
  end
end
local sysbase = getsysbase()

local function read_value(name, mode, postprocess)
  local f = assert(io.open(sysbase .. name))
  local value = f:read(mode or '*n')
  f:close()
  return postprocess and postprocess(value) or value
end
local function energy_full() return read_value('energy_full') end
local function energy_now() return read_value('energy_now') end
local function status() return read_value('status', '*l', string.lower) end

local function effective_threshold(status, percentage)
  matched_threshold = nil
  for k, v in ipairs(settings.thresholds[status]) do
    if percentage <= v then
      matched_threshold = k
      break
    end
  end
  local thresholds = {'blink', 'critical', 'important', 'normal'}
  return thresholds[matched_threshold]
end

local function get_info()
  local percentage = energy_now() * 100 / energy_full()
  local status = status()
  local threshold = effective_threshold(status, percentage)
  local info, hint, blink = "", 'normal', false
  if threshold then
    info = string.format("%.f%% %s", percentage, status)
    if threshold == 'blink' then
      hint = 'critical'
      blink = true
    else
      hint = threshold
    end
  end
  return info, hint, blink
end

local function render_content(info, is_blank)
  return string.format(
    "[ %s ]",
    is_blank and string.rep(" ", info:len()) or info
  )
end

function update_battery(is_blank, next_phases)
  next_phases = next_phases or {}
  info, hint, should_blink = get_info()
  if should_blink and #next_phases == 0 then
    for k, v in ipairs(settings.blink_pattern) do
      next_phases[k] = v
    end
  end
  local interval
  if #next_phases ~= 0 then
    is_blank = not is_blank
    interval = table.remove(next_phases, 1)
  end
  statusd.inform('battery', render_content(info, is_blank))
  statusd.inform('battery_hint', hint)
  battery_timer:set(interval or settings.update_interval, function ()
    return update_battery(is_blank, next_phases)
  end)
end

battery_timer = statusd.create_timer()
update_battery()
