-- YEN native video previewer
-- Uses yen-vidthumb (AVFoundation) for video preview rendering instead of ffmpeg thumbnails.
-- yen-vidthumb is found via PATH (set by browse wrapper).
--
-- Seek pattern follows Yazi convention:
--   seek() calculates new skip and emits peek with updated value
--   peek() uses job.skip as percentage of video duration
--   preload() caches the default thumbnail (1s)

local M = {}
local durations = {}
local duration_order = {}
local DURATION_CACHE_LIMIT = 512

local function path_stamp(path)
    local attrs = fs and fs.cha and fs.cha(path) or nil
    local mtime = attrs and (attrs.mtime or attrs.mtime_sec or attrs.modified or attrs.change_time) or ""
    local len = attrs and attrs.len or ""
    local mode = attrs and attrs.mode or ""
    return string.format("%s|%s|%s|%s", tostring(path), tostring(len), tostring(mtime), tostring(mode))
end

local function cache_duration(path, stamp, duration)
    if durations[path] == nil then
        duration_order[#duration_order + 1] = path
    end
    durations[path] = {
        stamp = stamp,
        duration = duration,
    }

    if #duration_order > DURATION_CACHE_LIMIT then
        local evicted = table.remove(duration_order, 1)
        if evicted ~= nil then
            durations[evicted] = nil
        end
    end
end

local function duration_for(path)
    local stamp = path_stamp(path)
    local cached = durations[path]
    if cached and cached.stamp == stamp then
        if cached.duration > 0 then
            return cached.duration
        end
        return nil
    end

    local dur_child = Command("yen-vidthumb")
        :arg(path)
        :arg("--duration")
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :output()

    if not dur_child or not dur_child.status or not dur_child.status.success then
        cache_duration(path, stamp, 0)
        return nil
    end

    local stdout = dur_child.stdout or ""
    local duration = tonumber(stdout:match("^%s*(.-)%s*$"))
    if not duration or duration <= 0 then
        cache_duration(path, stamp, 0)
        return nil
    end

    cache_duration(path, stamp, duration)
    return duration
end

local function preview_bounds()
    local preview = rt.preview or {}
    local max_width = tonumber(preview.max_width)
    local max_height = tonumber(preview.max_height)

    if max_width and max_width > 0 then
        max_width = math.floor(max_width)
    else
        max_width = nil
    end

    if max_height and max_height > 0 then
        max_height = math.floor(max_height)
    else
        max_height = nil
    end

    return max_width, max_height
end

function M:peek(job)
    local start, cache = os.clock(), ya.file_cache(job)
    if not cache then
        return
    end

    local ok, err = self:preload(job)
    if not ok or err then
        return ya.preview_widget(job, err)
    end

    ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

    local _, show_err = ya.image_show(cache, job.area)
    ya.preview_widget(job, show_err)
end

function M:seek(job)
    -- Yazi convention: accumulate skip units and re-peek
    -- seek() receives job.units; current skip lives in cx.active.preview.skip
    local h = cx.active.current.hovered
    if h and h.url == job.file.url then
        local current_skip = cx.active.preview and cx.active.preview.skip or 0
        local units = job.units or 0
        local new_skip = math.max(0, math.min(100, current_skip + units))
        ya.emit("peek", { new_skip, only_if = job.file.url })
    end
end

function M:preload(job)
    local cache = ya.file_cache(job)
    if not cache then
        return true
    end

    local cha = fs.cha(cache)
    if cha and cha.len > 0 then
        return true
    end

    local path = tostring(job.file.path)
    local skip = math.max(0, job.skip or 0)
    local seek_time = nil

    if skip > 0 then
        local duration = duration_for(path)
        if not duration then
            return true, Err("Failed to get video duration")
        end
        local percent = math.min(skip, 100)
        seek_time = duration * percent / 100
    end

    local child = Command("yen-vidthumb")
        :arg(path)
        :arg(tostring(cache))
        :stderr(Command.PIPED)
    local max_width, max_height = preview_bounds()

    if seek_time ~= nil then
        child:arg("--seek")
        child:arg(string.format("%.2f", seek_time))
    end

    if max_width ~= nil then
        child:arg("--max-width")
        child:arg(tostring(max_width))
    end

    if max_height ~= nil then
        child:arg("--max-height")
        child:arg(tostring(max_height))
    end

    local output, err = child:output()
    if not output then
        return true, Err("Failed to start `yen-vidthumb`, error: %s", err)
    elseif not output.status or not output.status.success then
        local stderr = (output.stderr or ""):gsub("[\r\n]+$", "")
        if stderr == "" then
            stderr = "unknown yen-vidthumb error"
        end
        return false, Err("`yen-vidthumb` exited with error code %s: %s", output.status.code or "?", stderr)
    end

    local cha = fs.cha(cache)
    if cha and cha.len > 0 then
        return true
    end
    return false, Err("`yen-vidthumb` did not produce a cached preview image")
end

return M
