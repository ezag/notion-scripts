local defaults = {
  update_interval = 2 * 1000,
  bat_no = nil,
  thresholds = {
      full        = {  0,   0,   0,   0},
      charging    = {  0,   0,   6, 100},
      discharging = { 12,  25,  50, 100},
  },
  blink_pattern = {125, 250, 125, 1500},
  info_data = {'percentage', 'status'},
  info_format = "%.f%% %s",
  content_format = "[ %s ]",
  blink_on_discharge = true,
}
local settings = table.join(statusd.get_config('battery'), defaults)

local function getsysbase()
  local path
  if settings.bat_no then
    path = '/sys/class/power_supply/BAT' .. settings.bat_no
  else
    local p = io.popen('ls -d /sys/class/power_supply/BAT* | head -n1')
    path = p:read()
    p:close()
  end
  return path .. '/'
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
  local data = {
    percentage = energy_now() * 100 / energy_full(),
    status = status(),
  }
  local threshold = effective_threshold(data.status, data.percentage)
  local info, hint, blink = "", 'normal', false
  if threshold then
    local display_data = {}
    for k, v in ipairs(settings.info_data) do
      display_data[k] = data[v]
    end
    info = settings.info_format:format(unpack(display_data))
    if threshold == 'blink' then
      hint = 'critical'
      blink = true
    else
      hint = threshold
    end
  end
  return info, hint, blink, data.status
end

local function render_content(info, is_blank)
  return settings.content_format:format(
    is_blank and string.rep(" ", info:len()) or info
  )
end

function update_battery(old_info, is_blank, next_phases)
  local next_phases = next_phases or {}
  local info, hint, should_blink, status = get_info()
  should_blink = should_blink or settings.blink_on_discharge and
                 status == 'discharging' and old_info and info ~= old_info
  if should_blink and #next_phases == 0 then
    for k, v in ipairs(settings.blink_pattern) do next_phases[k] = v end
  end
  local interval
  if #next_phases ~= 0 then
    is_blank = not is_blank
    interval = table.remove(next_phases, 1)
  end
  statusd.inform('battery', render_content(info, is_blank))
  statusd.inform('battery_hint', hint)
  battery_timer:set(interval or settings.update_interval, function ()
    return update_battery(info, is_blank, next_phases)
  end)
end
battery_timer = statusd.create_timer()
update_battery()
