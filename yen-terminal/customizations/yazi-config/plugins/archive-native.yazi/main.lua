-- YEN native archive previewer
-- Uses macOS bsdtar/libarchive instead of 7zip.

local M = {}
local MAX_INDEXED_ENTRIES = 5000
local MAX_STDERR_LINES = 80
local MAX_STDERR_BYTES = 64 * 1024
local ARCHIVE_LIST_CACHE_LIMIT = 128
local archive_list_cache = {}
local archive_list_order = {}

local function trim_eol(s)
    return (s or ""):gsub("[\r\n]+$", "")
end

local function normalize_entry(raw)
    local path = trim_eol(raw)
    if path == "" or path == "." then
        return nil
    end

    path = path:gsub("^%./", "")
    if path == "__MACOSX" or path:find("^__MACOSX/", 1, true) then
        return nil
    end

    local is_dir = path:sub(-1) == "/"
    if is_dir then
        path = path:sub(1, -2)
    end
    if path == "" then
        return nil
    end

    return path, is_dir
end

local function is_encrypted_or_unsupported(stderr)
    local s = stderr:lower()
    return s:find("encrypted", 1, true)
        or s:find("passphrase", 1, true)
        or s:find("password", 1, true)
end

local function is_unsupported_encrypted_7z(stderr)
    local s = stderr:lower()
    return s:find("encrypted", 1, true) and s:find("currently not supported", 1, true)
end

function M.make_file(t)
    t = t or {}
    t.path = type(t.path or "") == "string" and Path.os(t.path or "") or t.path
    t.size = tonumber(t.size) or 0
    t.depth = tonumber(t.depth) or 0
    t.is_dir = t.is_dir or false
    return t
end

function M.treelize(files, parents, f)
    while #parents > 0 and not f.path:starts_with(parents[#parents]) do
        parents[#parents] = nil
    end

    local buf, it = {}, f.path.parent
    while it and it ~= parents[#parents] do
        buf[#buf + 1], it = it, it.parent
    end
    for i = #buf, 1, -1 do
        files[#files + 1] = M.make_file { path = buf[i], depth = #parents, is_dir = true }
        parents[#parents + 1] = buf[i]
    end

    f.depth = #parents
    if not f.is_dir then
        files[#files + 1] = f
    elseif f.path ~= parents[#parents] then
        files[#files + 1], parents[#parents + 1] = f, f.path
    end
end

function M.list_archive(path)
    local child, err = Command("bsdtar")
        :arg({ "-tf", tostring(path) })
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :spawn()
    if not child then
        return {}, Err("Failed to start `bsdtar`, error: %s", err)
    end

    local indexed, stderr = {}, {}
    local indexed_count = 0
    local indexed_limit_reached = false
    local stderr_bytes = 0
    local stderr_truncated = false
    while true do
        local next, event = child:read_line()
        if event == 0 then
            if indexed_limit_reached then
                goto continue
            end
            local entry, is_dir = normalize_entry(next)
            if entry then
                local existing = indexed[entry]
                if not existing then
                    if indexed_count < MAX_INDEXED_ENTRIES then
                        indexed[entry] = M.make_file { path = entry, is_dir = is_dir }
                        indexed_count = indexed_count + 1
                        if indexed_count >= MAX_INDEXED_ENTRIES then
                            indexed_limit_reached = true
                        end
                    end
                elseif is_dir then
                    existing.is_dir = true
                end
            end
        elseif event == 1 then
            local line = trim_eol(next)
            if line ~= "" then
                local next_bytes = stderr_bytes + #line + 1
                if #stderr < MAX_STDERR_LINES and next_bytes <= MAX_STDERR_BYTES then
                    stderr[#stderr + 1] = line
                    stderr_bytes = next_bytes
                else
                    stderr_truncated = true
                end
            end
        else
            break
        end
        ::continue::
    end

    child:start_kill()

    local flat = {}
    for _, file in pairs(indexed) do
        flat[#flat + 1] = file
    end
    table.sort(flat, function(a, b)
        return tostring(a.path) < tostring(b.path)
    end)

    local files, parents = {}, {}
    for _, file in ipairs(flat) do
        M.treelize(files, parents, file)
    end

    if #stderr > 0 and #files == 0 then
        local joined = table.concat(stderr, "\n")
        if stderr_truncated then
            joined = joined .. "\n..."
        end
        if is_unsupported_encrypted_7z(joined) then
            return {}, Err("Encrypted 7z headers are unsupported by native backend (`bsdtar`)")
        elseif is_encrypted_or_unsupported(joined) then
            return {}, Err("File list in this archive is password-protected or unsupported by native backend")
        end
        return {}, Err("bsdtar errored while listing files:\n%s", joined)
    end

    return files, nil
end

local function archive_list_stamp(path)
    -- fs.cha takes a Url; Yazi raises on a string or a Path.
    local cha = fs and fs.cha and fs.cha(Url(tostring(path))) or nil
    local mtime = cha and (cha.mtime or cha.mtime_sec or cha.modified or cha.change_time) or ""
    local len = cha and cha.len or ""
    local mode = cha and cha.mode or ""
    return string.format("%s|%s|%s|%s", tostring(path), tostring(len), tostring(mtime), tostring(mode))
end

function M.list_archive_cached(path)
    local cache_key = tostring(path)
    local stamp = archive_list_stamp(path)
    local cached = archive_list_cache[cache_key]
    if cached and cached.stamp == stamp then
        return cached.files, cached.err
    end

    local files, err = M.list_archive(path)
    if not cached then
        archive_list_order[#archive_list_order + 1] = cache_key
    end
    archive_list_cache[cache_key] = { stamp = stamp, files = files, err = err }

    while #archive_list_order > ARCHIVE_LIST_CACHE_LIMIT do
        local evicted = table.remove(archive_list_order, 1)
        if evicted ~= nil then
            archive_list_cache[evicted] = nil
        end
    end

    return files, err
end

function M:peek(job)
    local limit = job.area.h
    local files, err = self.list_archive_cached(job.file.path)
    if err then
        return ya.preview_widget(job, err)
    elseif job.skip > 0 and #files < job.skip + limit then
        return ya.emit("peek", { math.max(0, #files - limit), only_if = job.file.url, upper_bound = true })
    elseif #files == 0 then
        return ya.preview_widget(job, ui.Text({ "(empty archive)" }):area(job.area))
    end

    local left = {}
    for i = job.skip + 1, math.min(#files, job.skip + limit) do
        local f = files[i]
        local icon = File({
            url = Url(f.path),
            cha = Cha { mode = tonumber(f.is_dir and "40700" or "100644", 8) },
        }):icon()

        if icon then
            left[#left + 1] = ui.Span(" " .. icon.text .. " "):style(icon.style)
        else
            left[#left + 1] = " "
        end

        left[#left] = ui.Line {
            string.rep(" │", f.depth),
            left[#left],
            -- `name` is nil for some paths; upstream falls back the same way.
            ui.truncate(f.path.name or tostring(f.path), {
                rtl = true,
                max = math.max(0, job.area.w - ui.width(left[#left])),
            }),
        }
    end

    ya.preview_widget(job, ui.Text(left):area(job.area))
end

function M:seek(job)
    require("code"):seek(job)
end

return M
