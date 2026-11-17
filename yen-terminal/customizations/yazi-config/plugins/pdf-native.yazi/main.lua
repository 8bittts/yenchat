-- YEN native PDF previewer
-- Uses yen-pdfthumb (PDFKit) instead of pdftoppm.
-- yen-pdfthumb is found via PATH (set by browse wrapper).

local M = {}
local page_counts = {}
local page_count_order = {}
local PAGE_COUNT_CACHE_LIMIT = 512

local function path_stamp(path)
    local attrs = fs and fs.cha and fs.cha(path) or nil
    local mtime = attrs and (attrs.mtime or attrs.mtime_sec or attrs.modified or attrs.change_time) or ""
    local len = attrs and attrs.len or ""
    local mode = attrs and attrs.mode or ""
    return string.format("%s|%s|%s|%s", tostring(path), tostring(len), tostring(mtime), tostring(mode))
end

local function cache_page_count(path, stamp, page_count)
    if page_counts[path] == nil then
        page_count_order[#page_count_order + 1] = path
    end
    page_counts[path] = {
        stamp = stamp,
        page_count = page_count,
    }

    if #page_count_order > PAGE_COUNT_CACHE_LIMIT then
        local evicted = table.remove(page_count_order, 1)
        if evicted ~= nil then
            page_counts[evicted] = nil
        end
    end
end

local function page_count(path)
    local stamp = path_stamp(path)
    local cached = page_counts[path]
    if cached and cached.stamp == stamp then
        if cached.page_count > 0 then
            return cached.page_count
        end
        return nil
    end

    local child = Command("yen-pdfthumb")
        :arg(path)
        :arg("--pages")
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :output()

    if not child or not child.status or not child.status.success then
        cache_page_count(path, stamp, 0)
        return nil
    end

    local stdout = child.stdout or ""
    local pages = tonumber(stdout:match("^%s*(.-)%s*$"))
    if not pages then
        cache_page_count(path, stamp, 0)
        return nil
    end

    pages = math.floor(pages)
    if pages <= 0 then
        cache_page_count(path, stamp, 0)
        return nil
    end

    cache_page_count(path, stamp, pages)
    return pages
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

local function target_page(path, skip)
    local pages = page_count(path)
    if not pages then
        return nil, nil, nil
    end

    local requested = math.max(0, math.floor(skip or 0))
    local page = math.min(requested, pages - 1)
    local bound = requested > page and pages or nil
    return page, pages, bound
end

function M:peek(job)
    local start, cache = os.clock(), ya.file_cache(job)
    if not cache then
        return
    end

    local ok, err, bound = self:preload(job)
    if bound and bound > 0 then
        return ya.emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
    elseif not ok or err then
        return ya.preview_widget(job, err)
    end

    ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

    local _, show_err = ya.image_show(cache, job.area)
    ya.preview_widget(job, show_err)
end

function M:seek(job)
    -- Yazi convention: accumulate skip units and re-peek.
    local h = cx.active.current.hovered
    if h and h.url == job.file.url then
        local current_skip = cx.active.preview and cx.active.preview.skip or 0
        local step = ya.clamp(-1, job.units, 1)
        local new_skip = math.max(0, current_skip + step)
        ya.emit("peek", { math.floor(new_skip), only_if = job.file.url })
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
    local page, _, bound = target_page(path, job.skip or 0)
    if bound and bound > 0 then
        return false, nil, bound
    elseif page == nil then
        return true, Err("Failed to get PDF page count")
    end

    local child = Command("yen-pdfthumb")
        :arg(path)
        :arg(tostring(cache))
        :arg("--page")
        :arg(tostring(page))
        :stderr(Command.PIPED)
    local max_width, max_height = preview_bounds()

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
        return true, Err("Failed to start `yen-pdfthumb`, error: %s", err)
    elseif not output.status then
        return false, Err("`yen-pdfthumb` exited without a status")
    elseif not output.status.success then
        local stderr = (output.stderr or ""):gsub("[\r\n]+$", "")
        if stderr == "" then
            stderr = "unknown yen-pdfthumb error"
        end
        return false, Err("`yen-pdfthumb` exited with error code %s: %s", output.status.code or "?", stderr)
    end

    local rendered = fs.cha(cache)
    if rendered and rendered.len > 0 then
        return true
    end
    return false, Err("`yen-pdfthumb` did not produce a cached preview image")
end

return M
