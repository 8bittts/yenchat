-- YEN native SVG previewer
-- Renders through yen-svgthumb, which also inflates gzip-compressed .svgz files.
-- Caps native render size to 1400px (<=2MP square) unless overridden by YEN_SVG_MAX_DIMENSION.
-- Binaries are found via PATH (set by browse wrapper).

local M = {}
local SVG_MAX_DIMENSION = tonumber(os.getenv("YEN_SVG_MAX_DIMENSION")) or 1400

local function svg_cache_path(cache)
    return Url(tostring(cache) .. ".png")
end

local function has_cached_image(path)
    local cha = fs.cha(path)
    return cha and cha.len > 0
end

local function summarize_stderr(child, fallback)
    if not child then
        return fallback
    end

    local stderr = (child.stderr or ""):gsub("[\r\n]+$", "")
    if stderr == "" then
        return fallback
    end
    return stderr
end

local function render_with_native(path, out_path)
    local preview = rt and rt.preview or nil
    local max_dimension = SVG_MAX_DIMENSION
    if preview then
        max_dimension = math.max(
            tonumber(preview.max_width) or max_dimension,
            tonumber(preview.max_height) or max_dimension
        )
    end

    local child = Command("yen-svgthumb")
        :arg(path)
        :arg(tostring(out_path))
        :arg("--max-dimension")
        :arg(tostring(max_dimension))
        :stderr(Command.PIPED)
        :output()

    if child and child.status and child.status.success and has_cached_image(out_path) then
        return true, nil
    end
    return false, summarize_stderr(child, "yen-svgthumb failed")
end

local function ensure_rendered(path, out_path)
    if has_cached_image(out_path) then
        return true, nil
    end

    local native_ok, native_err = render_with_native(path, out_path)
    if native_ok then
        return true, nil
    end

    return false, string.format("SVG preview unavailable\n%s", native_err)
end

function M:peek(job)
    local start, cache = os.clock(), ya.file_cache(job)
    if not cache then
        return
    end

    local cache_path = svg_cache_path(cache)
    local ok, err = self:preload(job)
    if not ok or err then
        return ya.preview_widget(job, err)
    end

    ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

    local _, show_err = ya.image_show(cache_path, job.area)
    ya.preview_widget(job, show_err)
end

function M:preload(job)
    local cache = ya.file_cache(job)
    if not cache then
        return true
    end

    local path = tostring(job.file.path)
    local cache_path = svg_cache_path(cache)
    local ok, err = ensure_rendered(path, cache_path)
    if not ok and err then
        ya.err(err)
        return false, ui.Text({ err }):area(job.area)
    end
    return ok, err
end

return M
