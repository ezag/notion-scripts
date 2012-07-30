local defaults = {
  update_interval = 2 * 1000,
  bat_no = 1,
  thresholds = {
    full        = {  0,   0,   0,   0},
    charging    = {  4,  22,  67, 100},
    discharging = {  6,  16,  40, 100},
  },
  blink_on = 1750,
  blink_off = 250,
}
local settings = table.join(statusd.get_config('battery'), defaults)

local blink_phase_blank = false
local do_blink = false
local prev_info

local function getsysbase()
  if settings.bat_no then
    return '/sys/class/power_supply/BAT' .. settings.bat_no .. '/'
  end
end
local sysbase = getsysbase()

local function energy_full()
  local f = assert(io.open(sysbase .. 'energy_full'))
  local value = f:read('*n')
  f:close()
  return value
end

local function energy_now()
  local f = assert(io.open(sysbase .. 'energy_now'))
  local value = f:read('*n')
  f:close()
  return value
end

local function status()
  local f = assert(io.open(sysbase .. 'status'))
  local value = f:read()
  f:close()
  return value:lower()
end

local function energy_percentage()
  return energy_now() * 100 / energy_full()
end

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

function update_battery()
  local percentage = energy_percentage()
  local status = status()
  local threshold = effective_threshold(status, percentage)
  local info
  local hint
  if threshold then
    info = string.format("%.f%% %s", percentage, status)
    if threshold == 'blink' then
      hint = 'critical'
      do_blink = true
    else
      hint = threshold
      do_blink = false
    end
  else
    info = ""
    hint = 'normal'
  end
  local interval = settings.update_interval
  local blinking_info = info
  if do_blink or blink_phase_blank or
     (status == 'discharging' and prev_info and info ~= prev_info) then
    if blink_phase_blank then
      interval = settings.blink_on
    else
      blinking_info = string.rep(" ", info:len())
      interval = settings.blink_off
    end
    blink_phase_blank = not blink_phase_blank
  end
  statusd.inform('battery', string.format('[ %s ]', blinking_info))
  statusd.inform('battery_hint', hint)
  prev_info = info
  battery_timer:set(interval, update_battery)
end

battery_timer = statusd.create_timer()
update_battery()
