-- YEN native archive extractor
-- Uses macOS bsdtar/libarchive instead of 7zip.

local function fail(s, ...)
    error(string.format(s, ...))
end

local M = {}

local INSECURE_PASSPHRASE_ENV = "YEN_ALLOW_INSECURE_ARCHIVE_PASSPHRASE"

local function insecure_passphrase_opt_in_enabled()
    return os.getenv(INSECURE_PASSPHRASE_ENV) == "1"
end

local function needs_password(stderr)
    local s = (stderr or ""):lower()
    return s:find("wrong password", 1, true)
        or s:find("incorrect passphrase", 1, true)
        or s:find("passphrase", 1, true)
        or s:find("password", 1, true)
end

local function unsupported_encryption(stderr)
    local s = (stderr or ""):lower()
    return s:find("encrypted", 1, true) and s:find("currently not supported", 1, true)
end

function M:setup()
    ps.sub_remote("extract-native", function(args)
        local noisy = #args == 1 and ' "" --noisy' or ' ""'
        for _, arg in ipairs(args) do
            ya.emit("plugin", { self._id, ya.quote(arg, true) .. noisy })
        end
    end)
end

function M:entry(job)
    local from = job.args[1] and Url(job.args[1])
    local to_arg = job.args[2]
    local to = (to_arg and to_arg ~= "") and Url(to_arg) or nil
    if not from then
        fail("No URL provided")
    end

    local pwd = ""
    while true do
        local needs_retry = M:try_with(from, pwd, to)
        if not needs_retry then
            break
        elseif not insecure_passphrase_opt_in_enabled() then
            fail(
                "Encrypted archives are blocked by default because macOS bsdtar requires --passphrase in process args (`ps`). " ..
                "Set " .. INSECURE_PASSPHRASE_ENV .. "=1 to proceed (insecure)."
            )
        elseif not job.args.noisy then
            fail("'%s' is password-protected, please extract it individually and enter the password", from)
        end

        local value, event = ya.input {
            pos = { "top-center", y = 2, w = 50 },
            title = string.format('Password for "%s":', from.name),
            obscure = true,
        }
        if event == 1 then
            pwd = value
        else
            break
        end
    end
end

function M.spawn_bsdtar(from, pwd, out_dir)
    local args = { "-xf", tostring(from), "-C", tostring(out_dir) }
    -- macOS bsdtar does not support passphrase-fd style options.
    -- If we pass --passphrase, the value can be visible in process args (`ps`)
    -- to same-user observers while extraction runs.
    -- We only attach --passphrase when needed to minimize that exposure window.
    if pwd ~= "" and insecure_passphrase_opt_in_enabled() then
        table.insert(args, 1, pwd)
        table.insert(args, 1, "--passphrase")
    end

    return Command("bsdtar")
        :arg(args)
        :stdout(Command.NULL)
        :stderr(Command.PIPED)
        :spawn()
end

function M:try_with(from, pwd, to)
    to = to or from.parent
    if not to then
        fail("Invalid URL '%s'", from)
    end

    -- fs.unique reserves the name by creating the directory, which bsdtar -C
    -- needs to exist. It replaced fs.unique_name in Yazi 26.
    local tmp = fs.unique("dir", to:join(self.tmp_name(from)))
    if not tmp then
        fail("Failed to determine a temporary directory for %s", from)
    end

    local child, err = M.spawn_bsdtar(from, pwd, tmp)
    if not child then
        fail("Failed to start `bsdtar`, error: %s", err)
    end

    local output, wait_err = child:wait_with_output()
    if not output then
        fs.remove("dir_all", tmp)
        fail("bsdtar failed to output when extracting '%s', error: %s", from, wait_err)
    elseif output.status.code ~= 0 then
        if unsupported_encryption(output.stderr) then
            fs.remove("dir_all", tmp)
            fail("Encrypted archive is unsupported by native backend (`bsdtar`) for '%s'", from)
        elseif needs_password(output.stderr) then
            fs.remove("dir_all", tmp)
            if not insecure_passphrase_opt_in_enabled() then
                fail(
                    "Encrypted archives are blocked by default because macOS bsdtar requires --passphrase in process args (`ps`). " ..
                    "Set " .. INSECURE_PASSPHRASE_ENV .. "=1 to proceed (insecure)."
                )
            end
            return true -- Need to retry with password
        end
        fs.remove("dir_all", tmp)
        fail("bsdtar exited with error code %s when extracting '%s':\n%s", output.status.code, from, output.stderr)
    end

    self:tidy(from, to, tmp)
    return false
end

function M:cleanup_tmp_dir(tmp)
    fs.remove("dir_all", tmp)
end

function M:rename_or_cleanup(source, target, tmp)
    if os.rename(tostring(source), tostring(target)) then
        return
    end
    self:cleanup_tmp_dir(tmp)
    fail('Failed to move "%s" to "%s"', source, target)
end

function M:tidy(from, to, tmp)
    local metadata_dir = tostring(tmp) .. "/__MACOSX"
    fs.remove("dir_all", Url(metadata_dir))

    -- Two entries are enough to tell one extracted item from several. The
    -- options table is required since Yazi 26.
    local outs = fs.read_dir(tmp, { limit = 2 })
    if not outs then
        fail("Failed to read the temporary directory '%s' when extracting '%s'", tmp, from)
    elseif #outs == 0 then
        fs.remove("dir_all", tmp)
        fail("No files extracted from '%s'", from)
    end

    local only = #outs == 1
    local target
    local target_kind = "dir"
    if only then
        target = to:join(outs[1].name)
        if not outs[1].cha.is_dir then
            target_kind = "file"
        end
    else
        target = to:join(self.trim_ext(from.name))
    end

    -- fs.unique creates an empty file or directory at the unique name; the
    -- rename below replaces it with the extracted entry.
    target = fs.unique(target_kind, target)
    if not target then
        fail("Failed to determine a target for '%s'", from)
    end

    target = tostring(target)
    if only then
        self:rename_or_cleanup(outs[1].url, target, tmp)
    else
        self:rename_or_cleanup(tmp, target, tmp)
    end
    self:cleanup_tmp_dir(tmp)
end

function M.tmp_name(url)
    return ".tmp_" .. ya.hash(string.format("extract-native//%s//%.10f", url, ya.time()))
end

function M.trim_ext(name)
    -- stylua: ignore
    local exts = { ["7z"] = true, apk = true, bz2 = true, bzip2 = true, cbr = true, cbz = true, exe = true, gz = true, gzip = true, iso = true, jar = true, rar = true, tar = true, tgz = true, xz = true, zip = true, zst = true }

    while true do
        local s = name:gsub("%.([a-zA-Z0-9]+)$", function(s) return (exts[s] or exts[s:lower()]) and "" end)
        if s == name or s == "" then
            break
        else
            name = s
        end
    end
    return name
end

return M
