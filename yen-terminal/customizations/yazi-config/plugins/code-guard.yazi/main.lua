-- YEN code preview guard
-- Uses built-in `code` preview for normal files, but downgrades very large or
-- minified text files to a plain wrapped preview to keep rendering responsive.

local M = {}

local MAX_CODE_BYTES = 1024 * 1024
local SAMPLE_BYTES = 64 * 1024
local MAX_PLAIN_BYTES = 256 * 1024
local MAX_WRAP_COLUMNS = 220
local MAX_TOTAL_LINES = 2200
local MINIFIED_LINE_THRESHOLD = 1200
local MINIFIED_NEWLINE_LIMIT = 12
local DECISION_CACHE_LIMIT = 512
local PLAIN_PREVIEW_CACHE_LIMIT = 64

local decision_cache = {}
local decision_order = {}
local plain_preview_cache = {}
local plain_preview_order = {}

local function readable_size(bytes)
    local n = tonumber(bytes) or 0
    if n >= 1024 * 1024 then
        return string.format("%.1f MB", n / (1024 * 1024))
    elseif n >= 1024 then
        return string.format("%.1f KB", n / 1024)
    end
    return string.format("%d B", n)
end

local function file_stats(path)
    local f = io.open(path, "rb")
    if not f then
        return nil, nil, nil, nil
    end

    local size = f:seek("end") or 0
    f:seek("set", 0)
    local sample = f:read(SAMPLE_BYTES) or ""
    f:close()

    local newline_count = 0
    local longest_line = 0
    local current = 0

    for i = 1, #sample do
        local b = sample:byte(i)
        if b == 10 then
            newline_count = newline_count + 1
            if current > longest_line then
                longest_line = current
            end
            current = 0
        else
            current = current + 1
        end
    end
    if current > longest_line then
        longest_line = current
    end

    return size, newline_count, longest_line, sample
end

local function cache_stamp(path, cha)
    -- fs.cha takes a Url; Yazi raises on a string or a Path.
    local attrs = cha or fs.cha(Url(tostring(path)))
    if not attrs then
        return nil
    end

    -- `mtime` field names can vary across Yazi/libarchive versions; keep fallback set broad.
    local mtime = attrs.mtime or attrs.mtime_sec or attrs.modified or attrs.change_time or ""
    local len = attrs.len or ""
    local mode = attrs.mode or ""
    return string.format("%s|%s|%s|%s", path, tostring(len), tostring(mtime), tostring(mode))
end

local function cache_get(path, stamp)
    local entry = decision_cache[path]
    if entry and entry.stamp == stamp then
        return entry.use_plain, entry.reason, entry.size
    end
    return nil
end

local function cache_put(path, stamp, use_plain, reason, size)
    if decision_cache[path] == nil then
        decision_order[#decision_order + 1] = path
    end

    decision_cache[path] = {
        stamp = stamp,
        use_plain = use_plain,
        reason = reason,
        size = size,
    }

    while #decision_order > DECISION_CACHE_LIMIT do
        local evicted = table.remove(decision_order, 1)
        if evicted and evicted ~= path then
            decision_cache[evicted] = nil
        end
    end
end

local function plain_cache_get(path, stamp)
    local entry = plain_preview_cache[path]
    if entry and entry.stamp == stamp then
        return entry.lines
    end
    return nil
end

local function plain_cache_put(path, stamp, lines)
    if plain_preview_cache[path] == nil then
        plain_preview_order[#plain_preview_order + 1] = path
    end

    plain_preview_cache[path] = {
        stamp = stamp,
        lines = lines,
    }

    while #plain_preview_order > PLAIN_PREVIEW_CACHE_LIMIT do
        local evicted = table.remove(plain_preview_order, 1)
        if evicted and evicted ~= path then
            plain_preview_cache[evicted] = nil
        end
    end
end

local function should_use_plain(path, cha)
    local stamp = cache_stamp(path, cha)
    if stamp then
        local cached_use_plain, cached_reason, cached_size = cache_get(path, stamp)
        if cached_use_plain ~= nil then
            return cached_use_plain, cached_reason, cached_size
        end
    end

    local size, newline_count, longest_line = file_stats(path)
    if not size then
        return false, "", 0
    end

    if size > MAX_CODE_BYTES then
        if stamp then
            cache_put(path, stamp, true, "large file", size)
        end
        return true, "large file", size
    end

    local minified = longest_line >= MINIFIED_LINE_THRESHOLD and newline_count <= MINIFIED_NEWLINE_LIMIT
    if minified then
        if stamp then
            cache_put(path, stamp, true, "minified content", size)
        end
        return true, "minified content", size
    end

    if stamp then
        cache_put(path, stamp, false, "", size)
    end
    return false, "", size
end

local function append_wrapped(lines, value, limit)
    local text = value or ""
    if text == "" then
        lines[#lines + 1] = ""
        return #lines < limit
    end

    local i = 1
    while i <= #text do
        lines[#lines + 1] = text:sub(i, i + MAX_WRAP_COLUMNS - 1)
        if #lines >= limit then
            return false
        end
        i = i + MAX_WRAP_COLUMNS
    end
    return true
end

local function build_plain_lines(path, reason, size, cha)
    local stamp = cache_stamp(path, cha)
    if stamp then
        local cached_lines = plain_cache_get(path, stamp)
        if cached_lines ~= nil then
            return cached_lines
        end
    end

    local f = io.open(path, "rb")
    if not f then
        return { "Unable to open file for preview." }
    end

    local data = f:read(MAX_PLAIN_BYTES) or ""
    local has_more = f:read(1) ~= nil
    f:close()

    local lines = {
        string.format("Plain preview (%s, %s).", reason, readable_size(size)),
        "Syntax highlighting disabled for responsiveness.",
        "",
    }

    local limit = MAX_TOTAL_LINES
    local line = {}
    for i = 1, #data do
        local b = data:byte(i)
        if b == 10 then
            if not append_wrapped(lines, table.concat(line), limit) then
                break
            end
            line = {}
        elseif b == 9 then
            line[#line + 1] = "    "
        elseif b == 13 then
            -- Ignore CR in CRLF sequences.
        else
            line[#line + 1] = string.char(b)
        end
    end

    if #line > 0 and #lines < limit then
        append_wrapped(lines, table.concat(line), limit)
    end

    if has_more and #lines < limit then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("… truncated after %s of data", readable_size(MAX_PLAIN_BYTES))
    end

    if stamp then
        plain_cache_put(path, stamp, lines)
    end

    return lines
end

local function render_plain(job, reason, size)
    local lines = build_plain_lines(tostring(job.file.path), reason, size, job.file and job.file.cha or nil)

    if job.skip > 0 and #lines < job.skip + job.area.h then
        ya.emit("peek", { math.max(0, #lines - job.area.h), only_if = job.file.url, upper_bound = true })
        return
    end

    local out = {}
    for i = job.skip + 1, math.min(#lines, job.skip + job.area.h) do
        out[#out + 1] = lines[i]
    end

    ya.preview_widget(job, ui.Text(out):area(job.area))
end

function M:peek(job)
    local use_plain, reason, size = should_use_plain(tostring(job.file.path), job.file and job.file.cha or nil)
    if not use_plain then
        return require("code"):peek(job)
    end

    render_plain(job, reason, size)
end

function M:seek(job)
    local use_plain = should_use_plain(tostring(job.file.path), job.file and job.file.cha or nil)
    if not use_plain then
        return require("code"):seek(job)
    end

    local units = job.units or 0
    local viewport_height = job.area and job.area.h or 0
    local step = math.floor(units * viewport_height / 10)
    step = step == 0 and ya.clamp(-1, units, 1) or step

    local current_skip = cx.active.preview and cx.active.preview.skip or 0
    local next_skip = math.max(0, current_skip + step)
    ya.emit("peek", { next_skip, only_if = job.file.url, upper_bound = true })
end

return M
