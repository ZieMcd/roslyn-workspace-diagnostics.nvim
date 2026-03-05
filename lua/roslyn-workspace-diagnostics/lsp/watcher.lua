local M = {}

local config = require("roslyn-workspace-diagnostics.config")

---@type table<string, uv_fs_event_t>
local watchers = {}

---@param path string
---@return string[]
local function default_find_csproj_files(path)
	local results = {}
	local handle = vim.uv.fs_scandir(path)
	if not handle then
		return results
	end
	while true do
		local name, type = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		local full_path = path .. "/" .. name
		if type == "directory" and name ~= "bin" and name ~= "obj" and name ~= ".git" then
			vim.list_extend(results, default_find_csproj_files(full_path))
		elseif type == "file" and name:match("%.csproj$") then
			table.insert(results, full_path)
		end
	end
	return results
end

---@param file_path string
local function notify_file_changed(file_path)
	local uri = vim.uri_from_fname(file_path)
	local clients = vim.lsp.get_clients()
	for _, client in ipairs(clients) do
		if vim.tbl_contains(config.options.roslyn_alias, client.name) then
			client:notify("workspace/didChangeWatchedFiles", {
				changes = {
					{ uri = uri, type = 2 },
				},
			})
		end
	end
end

function M.start()
	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or not vim.tbl_contains(config.options.roslyn_alias, client.name) then
				return
			end

			M.stop()

			local cwd = vim.fn.getcwd()
			local find_fn = config.options.csproj_watcher.find_csproj_files or default_find_csproj_files
			local csproj_files = find_fn(cwd)

			for _, file_path in ipairs(csproj_files) do
				M.watch_file(file_path)
			end
		end,
	})
end

---@param file_path string
function M.watch_file(file_path)
	if watchers[file_path] then
		return
	end
	local handle = vim.uv.new_fs_event()
	if handle then
		handle:start(file_path, {}, function(err, filename, events)
			if err then
				return
			end
			vim.schedule(function()
				notify_file_changed(file_path)
			end)
		end)
		watchers[file_path] = handle
	end
end

---@param file_path string
function M.unwatch_file(file_path)
	local handle = watchers[file_path]
	if handle then
		handle:stop()
		handle:close()
		watchers[file_path] = nil
		return
	end
	vim.notify("file " .. file_path .. " not being watched")
end

function M.stop()
	for _, handle in pairs(watchers) do
		handle:stop()
		handle:close()
	end
	watchers = {}
end

return M
