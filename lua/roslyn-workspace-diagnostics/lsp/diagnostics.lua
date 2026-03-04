-- a lot this is copied from https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/diagnostic.lua
-- I need some of the private method in that file for setting diagnostics
local M = {}

local result_ids = {}

-- Tracking open files is a bit of hack.
-- Their is a bit of weird behaviour when handling workspace diagnostics for open files, this is probably because neovim it self makes request for open files which mess with previous results ids
---@type table<integer, table<string, boolean>>
local open_files = {}

local protocol = require("vim.lsp.protocol")
local lsp = require("vim.lsp")

--- @param diagnostic lsp.Diagnostic
--- @param client_id integer
--- @return table?
local function tags_lsp_to_vim(diagnostic, client_id)
	local tags ---@type table?
	for _, tag in ipairs(diagnostic.tags or {}) do
		if tag == protocol.DiagnosticTag.Unnecessary then
			tags = tags or {}
			tags.unnecessary = true
		elseif tag == protocol.DiagnosticTag.Deprecated then
			tags = tags or {}
			tags.deprecated = true
		else
			lsp.log.info(string.format("Unknown DiagnosticTag %d from LSP client %d", tag, client_id))
		end
	end
	return tags
end

---@param severity lsp.DiagnosticSeverity
---@return vim.diagnostic.Severity
local function severity_lsp_to_vim(severity)
	if type(severity) == "string" then
		return protocol.DiagnosticSeverity[severity] --[[@as vim.diagnostic.Severity]]
	end
	return severity
end

---@param bufnr integer
---@return string[]|nil
local function get_buf_lines(bufnr)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil
	end
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---@param diagnostics lsp.Diagnostic[]
---@param bufnr integer
---@param client_id integer
---@return vim.Diagnostic.Set[]
function M.lsp_to_vim(diagnostics, bufnr, client_id)
	local buf_lines = get_buf_lines(bufnr)
	local client = lsp.get_client_by_id(client_id)
	local position_encoding = client and client.offset_encoding or "utf-16"
	--- @param diagnostic lsp.Diagnostic
	--- @return vim.Diagnostic.Set
	return vim.tbl_map(function(diagnostic)
		local start = diagnostic.range.start
		local _end = diagnostic.range["end"]
		local message = diagnostic.message
		if type(message) ~= "string" then
			vim.notify_once(
				string.format("Unsupported Markup message from LSP client %d", client_id),
				lsp.log_levels.ERROR
			)
			--- @diagnostic disable-next-line: undefined-field,no-unknown
			message = diagnostic.message.value
		end
		local line = buf_lines and buf_lines[start.line + 1] or ""
		local end_line = line
		if _end.line > start.line then
			end_line = buf_lines and buf_lines[_end.line + 1] or ""
		end
		--- @type vim.Diagnostic.Set
		return {
			lnum = start.line,
			col = vim.str_byteindex(line, position_encoding, start.character, false),
			end_lnum = _end.line,
			end_col = vim.str_byteindex(end_line, position_encoding, _end.character, false),
			severity = severity_lsp_to_vim(diagnostic.severity),
			message = message,
			source = diagnostic.source,
			code = diagnostic.code,
			_tags = tags_lsp_to_vim(diagnostic, client_id),
			user_data = {
				lsp = diagnostic,
			},
		}
	end, diagnostics)
end

--- @param uri string
--- @param client_id integer
--- @param diagnostics lsp.Diagnostic[]
--- @param is_pull boolean
local function handle_diagnostics(uri, client_id, diagnostics, is_pull)
	local fname = vim.uri_to_fname(uri)

	if #diagnostics == 0 and vim.fn.bufexists(fname) == 0 then
		return
	end

	local bufnr = vim.fn.bufadd(fname)
	if not bufnr then
		return
	end

	local namespace = vim.lsp.diagnostic.get_namespace(client_id, is_pull)

	vim.diagnostic.set(namespace, bufnr, M.lsp_to_vim(diagnostics, bufnr, client_id))
end

---@param err any
---@param doc_report table
---@param ctx table
function M.handle(err, doc_report, ctx, _)
	if err or not doc_report then
		return
	end

	if doc_report.resultId then
		result_ids[ctx.client_id] = result_ids[ctx.client_id] or {}
		result_ids[ctx.client_id][doc_report.uri] = doc_report.resultId
	end

	if doc_report.kind == "unchanged" then
		return
	end

	local bufnr = vim.uri_to_bufnr(doc_report.uri)
	local ns = vim.lsp.diagnostic.get_namespace(ctx.client_id)
	local diagnostics = M.lsp_to_vim(doc_report.items, bufnr, ctx.client_id)
	vim.diagnostic.set(ns, bufnr, diagnostics)
end

---@param err any
---@param result table
---@param ctx table
function M.handle_workspace_result(err, result, ctx, _)
	if not result or not result.items then
		return
	end

	for _, doc_report in ipairs(result.items) do
		if doc_report.resultId then
			result_ids[ctx.client_id] = result_ids[ctx.client_id] or {}
			result_ids[ctx.client_id][doc_report.uri] = doc_report.resultId
		end
		-- local is_open = open_files[ctx.client_id] and M._open_files[ctx.client_id][doc_report.uri]
		if
			doc_report.kind ~= "unchanged" --[[ and not is_open ]]
		then
			handle_diagnostics(doc_report.uri, ctx.client_id, doc_report.items, true)
		end
	end
end

---@param client_id integer
---@param uri string
---@return string|nil
function M.get_result_id(client_id, uri)
	if result_ids[client_id] then
		return result_ids[client_id][uri]
	end
	return nil
end

---@param client_id integer
---@return table[]
function M._build_previous_result_ids(client_id)
	local previous = {}
	local open = open_files[client_id] or {}
	for uri, value in pairs(result_ids[client_id] or {}) do
		if not open[uri] then
			table.insert(previous, { uri = uri, value = value })
		end
	end
	return previous
end

---@param client_id integer
---@param uri string
function M._track_open(client_id, uri)
	if not open_files[client_id] then
		open_files[client_id] = {}
	end
	open_files[client_id][uri] = true
end

---@param client_id integer
---@param uri string
function M._track_close(client_id, uri)
	if open_files[client_id] then
		open_files[client_id][uri] = nil
	end
end

---@param client_id integer
function M._reset_result_ids(client_id)
	result_ids[client_id] = {}
end

return M
