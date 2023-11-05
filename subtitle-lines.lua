-- subtitle-lines 1.0.0 - 2023-Oct-22
-- https://github.com/christoph-heinrich/mpv-subtitle-lines
--
-- List and search subtitle lines of the selected subtitle track.
--
-- Usage:
-- add bindings to input.conf:
-- Ctrl+f script-binding subtitle_lines/list_subtitles

local mp = require 'mp'
local utils = require 'mp.utils'
local script_name = mp.get_script_name()

function get_pts(time)
    local h, m, s, ms = string.match(time, "(%d):(%d%d):(%d%d).(%d%d)")
    if h and m and s and ms then
        h, m, s, ms = tonumber(h), tonumber(m), tonumber(s), tonumber(ms)
        return ms/100 + s + m * 60 + h * 60 * 60
    end
    return nil
end

function parseDialogue(input)
    local start, stop, line = string.match(input, "Dialogue: %d,(%d:%d%d:%d%d%.%d%d),(%d:%d%d:%d%d%.%d%d),[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,(.*)$")
    if start and stop and line then
        return { start = get_pts(start), stop = get_pts(stop), line = line, start_s = start, stop_s = stop }
    else
        return nil
    end
end

local subtitles = nil
local menu_open = false

function acquire_subtitles()
    subtitles = {}
    local path = mp.get_property("path")
    local sid = mp.get_property("sid") - 1

    local cmd = "ffmpeg -i \"" .. path .. "\" -map s:"..sid .. " -f ass - 2> nul"
    local handle = io.popen(cmd, 'r')
    if not handle then
        mp.msg.error("Couldn’t open sub demuxer with command: " ..  cmd)
        return
    end
    local select_idx = 0
    for line in handle:lines() do
        mp.dispatch_events() -- this allows the script to remain (somewhat) responsive during demuxing so that the menu can be closed and re-opened
        if not subtitles then break end -- end-file received, abort
        -- not sure if this is more fragile than calling mp_event_loop()?
        local parsed_line = parseDialogue(line)
        if parsed_line then
            table.insert(subtitles, parsed_line)
            if menu_open then
                show_subtitle_list()
            end 
        end
    end
    handle:close()
end

function show_subtitle_list()
    local menu = {
        title = 'Subtitle lines',
        items = {},
        type = 'subtitle-lines-list',
        on_close = {
            'script-message-to',
            script_name,
            'uosc-menu-closed',
        }
    }

    local time = mp.get_property_number('time-pos', 0)
    for _, subtitle in ipairs(subtitles or {}) do
        menu.items[#menu.items + 1] = {
            title = subtitle.line,
            hint = subtitle.start_s .. ' – ' .. subtitle.stop_s,
            active = subtitle.start <= time and time <= subtitle.stop,
            value = {
                'seek',
                subtitle.start,
                'absolute+exact',
            }
        }
    end

    local json = utils.format_json(menu)
    if menu_open then mp.commandv('script-message-to', 'uosc', 'update-menu', json)
    else mp.commandv('script-message-to', 'uosc', 'open-menu', json) end
    menu_open = true
end

mp.add_key_binding(nil, 'list_subtitles', function()
    if menu_open then
        mp.commandv('script-message-to', 'uosc', 'close-menu', 'subtitle-lines-list')
        return
    end

    show_subtitle_list()
    if not subtitles then
        acquire_subtitles()
    end
end)

mp.register_script_message('uosc-menu-closed', function()
    menu_open = false
end)

mp.register_event('end-file', function()
    subtitles = nil
end)
