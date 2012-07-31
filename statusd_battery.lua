local defaults = {
  -- Data to display; any value may be ommited or listed multiple times.
  info_data = {
    -- Number within range of 0..100 indicating current battery level.
    -- Note that value is not rounded; use format options (below) to
    -- drop unwanted decimal digits.
    'percentage',  
    -- String representing battery status: full, charging or
    -- discharging.
    'status',
  },

  -- Customize battery status representation. Example (resembling
  -- statusd_linuxbatt behaviour):
  --
  -- status_display = {full = " ", charging = "+", discharging = "-"}
  status_display = {
    full        = "full",
    charging    = "charging",
    discharging = "discharging",
  },

  -- Format string used to display data. Number and order of
  -- placeholders should correspond to 'info_data'. Some examples:
  --
  -- info_data = {'percentage'}  -- show only percentage with
  -- info_format = "%.2f"        -- precision of 2 decimal digits
  --
  -- info_data = {'status', 'percentage'}  -- verbose one
  -- info_format = "Battery is %s, level is %.f percent"
  --
  -- info_data = {'status', 'status'}  -- show both rounded and exact
  -- info_format = "%.f (exact: %f)"   -- percentages
  info_format = "%.f%% %s",

  -- Format string used to wrap data; doesn't dissappear while
  -- blinking. This allows to keep place and to avoid statusbar content
  -- flickering. Beware of hanging whitespaces - they will be stripped.
  content_format = "[ %s ]",

  -- Update interval in milliseconds.
  update_interval = 2 * 1000,

  -- Number of battery, will attempt to autodetect if not set.
  bat_no = nil,

  -- Percentage thresholds:
  --
  --   1) blink     - if value drops below specified threshold,
  --                  statusbar starts to blink;
  --   2) critical  - threshold for 'critical' hint;
  --   3) important - 'important' hint;
  --   4) normal    - if value is greater than specified one, nothing
  --                  is displayed at all.
  --
  -- Each battery status has separate set of thresholds. Values
  -- of 0 or 100 may be used to disable some thresholds for some
  -- battery statuses.
  --
  -- Note that full table should be specified in order to override
  -- default settings, partial specification will not work:
  --
  -- thresholds = {charging = {0, 0, 0, 0}}  -- *not allowed*
  thresholds = {
    full        = {  0,   0,   0,   0},
    charging    = {  0,   0,   6, 100},
    discharging = { 12,  25,  50, 100},
  },

  -- Intervals in milliseconds which define blink pattern. Should be of
  -- even length, otherwise blinking will be unpredictale. Examples:
  --
  -- blink_pattern = {1000, 1000} -- one second off, one second on
  -- blink_pattern = {150, 1750}  -- short off, long on
  -- blinn_pattern = {100, 100, 100, 100, 100, 100,  -- strobo each
  --                  100, 100, 100, 100, 10000}     -- 10 seconds
  blink_pattern = {125, 250, 125, 1500},

  -- If set to true, indicator will blink once each time when info is
  -- updated during discharging.
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
      display = data[v]
      if v == 'status' then
        display = settings.status_display[display]
      end
      display_data[k] = display
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
