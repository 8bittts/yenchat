---@class State
---@field dirs table<string, string|CODES> Mapping between a directory and its corresponding repository
---@field repos table<string, Changes> Mapping between a repository and the status of each of its files
---@field dir_order string[] FIFO of active directory scopes participating in bounded retention
---@field repo_refcount table<string, integer> Active scope count per repository
---@field path_owners table<string, table<string, table<string, CODES>>> Active owners per repo-relative status path
---@field excluded_refcount table<string, integer> Active scope count per excluded directory marker
---@field dir_paths table<string, table<string, CODES>> Repo-relative status paths owned by each active directory scope
---@field dir_excluded table<string, table<string, boolean>> Excluded directory markers owned by each active directory scope

---@class Options
---@field order number The order in which the status is displayed
---@field renamed boolean Whether to include renamed files in the status (or treat them as modified)

-- TODO: move this to `types.yazi` once it's get stable
---@alias UnstableFetcher fun(self: unknown, job: { files: File[] }): boolean, Error?

---@alias Changes table<string, CODES>
