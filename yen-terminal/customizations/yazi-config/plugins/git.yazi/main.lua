--- @since 26.1.22
--- @pinned yazi-rs/plugins commit: e84f4fe5 (https://github.com/yazi-rs/plugins/tree/main/git.yazi)
-- Yazi git plugin - displays git status indicators in file list
-- Source: https://github.com/yazi-rs/plugins/tree/main/git.yazi

local WINDOWS = ya.target_family() == "windows"

-- The code of supported git status,
-- also used to determine which status to show for directories when they contain different statuses
-- see `bubble_up`
---@enum CODES
local CODES = {
	unknown = 100, -- status cannot/not yet determined
	excluded = 99, -- ignored directory
	ignored = 6, -- ignored file
	untracked = 5,
	modified = 4,
	added = 3,
	deleted = 2,
	updated = 1,
	clean = 0,
}

local PATTERNS = {
	{ "!$", CODES.ignored },
	{ "?$", CODES.untracked },
	{ "[MT]", CODES.modified },
	{ "[AC]", CODES.added },
	{ "D", CODES.deleted },
	{ "U", CODES.updated },
	{ "[AD][AD]", CODES.updated },
}

-- Guard against unbounded state growth across long-running sessions.
local MAX_TRACKED_DIRS = 2048

---@param line string
---@return CODES, string
local function match(line)
	local signs = line:sub(1, 2)
	for _, p in ipairs(PATTERNS) do
		local path, pattern, code = nil, p[1], p[2]
		if signs:find(pattern) then
			path = line:sub(4, 4) == '"' and line:sub(5, -2) or line:sub(4)
			path = WINDOWS and path:gsub("/", "\\") or path
		end
		if not path then
		elseif path:find("[/\\]$") then
			-- Mark the ignored directory as `excluded`, so we can process it further within `propagate_down`
			return code == CODES.ignored and CODES.excluded or code, path:sub(1, -2)
		else
			return code, path
		end
		---@diagnostic disable-next-line: missing-return
	end
end

---@param cwd Url
---@return string?
local function root(cwd)
	local is_worktree = function(url)
		local file, head = io.open(tostring(url)), nil
		if file then
			head = file:read(8)
			file:close()
		end
		return head == "gitdir: "
	end

	repeat
		local next = cwd:join(".git")
		local cha = fs.cha(next)
		if cha and (cha.is_dir or is_worktree(next)) then
			return tostring(cwd)
		end
		cwd = cwd.parent
	until not cwd
end

---@param changed Changes
---@return Changes
local function bubble_up(changed)
	local new, empty = {}, Url("")
	for path, code in pairs(changed) do
		if code ~= CODES.ignored then
			local url = Url(path).parent
			while url and url ~= empty do
				local s = tostring(url)
				new[s] = (new[s] or CODES.clean) > code and new[s] or code
				url = url.parent
			end
		end
	end
	return new
end

---@param excluded string[]
---@param cwd Url
---@param repo Url
---@return Changes
local function propagate_down(excluded, cwd, repo)
	local new, rel = {}, cwd:strip_prefix(repo)
	for _, path in ipairs(excluded) do
		if rel:starts_with(path) then
			-- If `cwd` is a subdirectory of an excluded directory, also mark it as `excluded`
			new[tostring(cwd)] = CODES.excluded
		elseif cwd == repo:join(path).parent then
			-- If `path` is a direct subdirectory of `cwd`, mark it as `ignored`
			new[path] = CODES.ignored
		else
			-- Skipping, we only care about `cwd` itself and its direct subdirectories for maximum performance
		end
	end
	return new
end

---@param st State
---@param cwd string
local function remove_dir_order(st, cwd)
	for i = #st.dir_order, 1, -1 do
		if st.dir_order[i] == cwd then
			table.remove(st.dir_order, i)
			break
		end
	end
end

local function strongest_code(owners)
	local code = nil
	for _, owner_code in pairs(owners) do
		code = code and (code > owner_code and code or owner_code) or owner_code
	end
	return code
end

local function dec_repo_ref(st, repo_key)
	if not repo_key or repo_key == CODES.excluded then
		return
	end
	local count = st.repo_refcount[repo_key]
	if not count then
		return
	end
	if count <= 1 then
		st.repo_refcount[repo_key] = nil
		st.path_owners[repo_key] = nil
		st.repos[repo_key] = nil
	else
		st.repo_refcount[repo_key] = count - 1
	end
end

local function inc_repo_ref(st, repo_key)
	if not repo_key or repo_key == CODES.excluded then
		return
	end
	st.repo_refcount[repo_key] = (st.repo_refcount[repo_key] or 0) + 1
end

local function dec_repo_path_ref(st, repo_key, cwd, path)
	if not repo_key or repo_key == CODES.excluded then
		return
	end

	local paths = st.path_owners[repo_key]
	if not paths then
		if st.repos[repo_key] then
			st.repos[repo_key][path] = nil
		end
		return
	end

	local owners = paths[path]
	if not owners then
		if st.repos[repo_key] then
			st.repos[repo_key][path] = nil
		end
		return
	end

	owners[cwd] = nil
	local code = strongest_code(owners)
	if code == nil then
		paths[path] = nil
		if st.repos[repo_key] then
			st.repos[repo_key][path] = nil
		end
	elseif st.repos[repo_key] then
		st.repos[repo_key][path] = code
	end

	if next(paths) == nil then
		st.path_owners[repo_key] = nil
	end
end

local function inc_repo_path_ref(st, repo_key, cwd, path, code)
	if not repo_key or repo_key == CODES.excluded or code == CODES.clean then
		return
	end

	st.path_owners[repo_key] = st.path_owners[repo_key] or {}
	st.path_owners[repo_key][path] = st.path_owners[repo_key][path] or {}
	st.path_owners[repo_key][path][cwd] = code
	st.repos[repo_key] = st.repos[repo_key] or {}
	st.repos[repo_key][path] = strongest_code(st.path_owners[repo_key][path])
end

local function dec_excluded_ref(st, path)
	local count = st.excluded_refcount[path]
	if not count then
		if st.dirs[path] == CODES.excluded then
			st.dirs[path] = nil
		end
		return
	end

	if count <= 1 then
		st.excluded_refcount[path] = nil
		if st.dirs[path] == CODES.excluded then
			st.dirs[path] = nil
		end
	else
		st.excluded_refcount[path] = count - 1
	end
end

local function inc_excluded_ref(st, path)
	st.excluded_refcount[path] = (st.excluded_refcount[path] or 0) + 1
	st.dirs[path] = CODES.excluded
end

local function release_scope(st, cwd)
	local repo = st.dirs[cwd]
	local paths = st.dir_paths[cwd] or {}
	local excluded = st.dir_excluded[cwd] or {}

	for path in pairs(paths) do
		dec_repo_path_ref(st, repo, cwd, path)
	end
	for path in pairs(excluded) do
		dec_excluded_ref(st, path)
	end

	st.dir_paths[cwd] = nil
	st.dir_excluded[cwd] = nil
	st.dirs[cwd] = nil
	remove_dir_order(st, cwd)
	dec_repo_ref(st, repo)
end

---@param cwd string
---@param repo string
---@param changed Changes
local add = ya.sync(function(st, cwd, repo, changed)
	---@cast st State
	st.repo_refcount = st.repo_refcount or {}
	st.path_owners = st.path_owners or {}
	st.excluded_refcount = st.excluded_refcount or {}
	st.dir_paths = st.dir_paths or {}
	st.dir_excluded = st.dir_excluded or {}

	st.dir_order = st.dir_order or {}
	if st.dirs[cwd] == nil then
		st.dir_order[#st.dir_order + 1] = cwd
	end

	local prev_repo = st.dirs[cwd]
	local prev_paths = st.dir_paths[cwd] or {}
	local prev_excluded = st.dir_excluded[cwd] or {}
	local next_paths, next_excluded = {}, {}

	for path, code in pairs(changed) do
		if code == CODES.excluded then
			next_excluded[path] = true
		elseif code ~= CODES.clean then
			next_paths[path] = code
		end
	end

	if prev_repo ~= repo then
		for path in pairs(prev_paths) do
			dec_repo_path_ref(st, prev_repo, cwd, path)
		end
	else
		for path in pairs(prev_paths) do
			if next_paths[path] == nil then
				dec_repo_path_ref(st, repo, cwd, path)
			end
		end
	end

	for path in pairs(prev_excluded) do
		if not next_excluded[path] then
			dec_excluded_ref(st, path)
		end
	end

	if prev_repo ~= repo then
		dec_repo_ref(st, prev_repo)
		inc_repo_ref(st, repo)
	end

	st.dirs[cwd] = repo
	st.repos[repo] = st.repos[repo] or {}

	for path, code in pairs(next_paths) do
		if prev_repo ~= repo or prev_paths[path] ~= code then
			inc_repo_path_ref(st, repo, cwd, path, code)
		end
	end
	for path in pairs(next_excluded) do
		if not prev_excluded[path] then
			inc_excluded_ref(st, path)
		end
	end

	st.dir_paths[cwd] = next_paths
	st.dir_excluded[cwd] = next_excluded

	while #st.dir_order > MAX_TRACKED_DIRS do
		local evicted = table.remove(st.dir_order, 1)
		release_scope(st, evicted)
	end

	ui.render()
end)

---@param cwd string
local remove = ya.sync(function(st, cwd)
	---@cast st State
	st.repo_refcount = st.repo_refcount or {}
	st.path_owners = st.path_owners or {}
	st.excluded_refcount = st.excluded_refcount or {}
	st.dir_paths = st.dir_paths or {}
	st.dir_excluded = st.dir_excluded or {}

	local repo = st.dirs[cwd]
	if not repo then
		return
	end

	release_scope(st, cwd)
	ui.render()
end)

---@param st State
---@param opts Options
local function setup(st, opts)
	st.dirs = {}
	st.repos = {}
	st.dir_order = {}
	st.repo_refcount = {}
	st.path_owners = {}
	st.excluded_refcount = {}
	st.dir_paths = {}
	st.dir_excluded = {}

	opts = opts or {}
	opts.order = opts.order or 1500

	local t = th.git or {}
	local mgr = th.mgr or {}
	local notify = th.notify or {}
	local status = th.status or {}
	local styles = {
		[CODES.unknown] = t.unknown or ui.Style(),
		[CODES.ignored] = t.ignored or status.perm_sep or mgr.border_style or ui.Style():fg("darkgray"),
		[CODES.untracked] = t.untracked or mgr.find_position or ui.Style():fg("magenta"),
		[CODES.modified] = t.modified or mgr.find_keyword or ui.Style():fg("yellow"),
		[CODES.added] = t.added or notify.title_info or ui.Style():fg("green"),
		[CODES.deleted] = t.deleted or notify.title_error or ui.Style():fg("red"),
		[CODES.updated] = t.updated or notify.title_warn or mgr.find_keyword or ui.Style():fg("yellow"),
		[CODES.clean] = t.clean or ui.Style(),
	}
	local signs = {
		[CODES.unknown] = t.unknown_sign or "",
		[CODES.ignored] = t.ignored_sign or " ",
		[CODES.untracked] = t.untracked_sign or "? ",
		[CODES.modified] = t.modified_sign or " ",
		[CODES.added] = t.added_sign or " ",
		[CODES.deleted] = t.deleted_sign or " ",
		[CODES.updated] = t.updated_sign or " ",
		[CODES.clean] = t.clean_sign or "",
	}

	Linemode:children_add(function(self)
		if not self._file.in_current then
			return ""
		end

		local url = self._file.url
		local repo = st.dirs[tostring(url.base or url.parent)]
		local code = CODES.unknown
		if repo then
			code = repo == CODES.excluded and CODES.ignored or st.repos[repo][tostring(url):sub(#repo + 2)] or CODES.clean
		end

		if signs[code] == "" then
			return ""
		elseif self._file.is_hovered then
			return ui.Line { " ", signs[code] }
		else
			return ui.Line { " ", ui.Span(signs[code]):style(styles[code]) }
		end
	end, opts.order)
end

---@type UnstableFetcher
local function fetch(_, job)
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local repo = root(cwd)
	if not repo then
		remove(tostring(cwd))
		return true
	end

	local paths = {}
	for _, file in ipairs(job.files) do
		paths[#paths + 1] = tostring(file.url)
	end

	-- stylua: ignore
	local output, err = Command("git")
		:cwd(tostring(cwd))
		:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames", "--ignored=matching" })
		:arg(paths)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()
	if not output then
		return true, Err("Cannot spawn `git` command, error: %s", err)
	elseif not output.status or not output.status.success then
		local code = output.status and output.status.code or "?"
		local stderr = (output.stderr or ""):gsub("[\r\n]+$", "")
		if stderr == "" then
			stderr = "unknown git error"
		end
		return true, Err("`git status` failed (exit %s): %s", code, stderr)
	end

	local changed, excluded = {}, {}
	for line in output.stdout:gmatch("[^\r\n]+") do
		local code, path = match(line)
		if code == CODES.excluded then
			excluded[#excluded + 1] = path
		else
			changed[path] = code
		end
	end

	if job.files[1].cha.is_dir then
		ya.dict_merge(changed, bubble_up(changed))
	end
	ya.dict_merge(changed, propagate_down(excluded, cwd, Url(repo)))

	-- Reset the status of any files that don't appear in the output of `git status` to `clean`,
	-- so that cleaning up outdated statuses from `st.repos`
	for _, path in ipairs(paths) do
		local s = path:sub(#repo + 2)
		changed[s] = changed[s] or CODES.clean
	end

	add(tostring(cwd), repo, changed)

	return false
end

return { setup = setup, fetch = fetch }
