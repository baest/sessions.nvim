local levels = vim.log.levels

-- default configuration
local config = {
    -- events which trigger a session save
    events = { "BufEnter", "VimLeavePre" },

    -- default session filepath
    session_filepath = "",
}

local M = {}

-- ensure full path to session file exists, and attempt to create intermediate
-- directories if needed
---@param path string
---@return boolean
local function ensure_path(path)
    local dirname = vim.fs.dirname(path)
    local basename = vim.fs.basename(path)
    if dirname and not vim.fn.isdirectory(dirname) then
        if not vim.fn.mkdir(dirname, "p") then
            return false
        end
    end
    return basename ~= ""
end

-- converts a given filepath to a string safe to be used as a session filename
---@param path string
---@return string
local function safe_path(path)
    local safepath = vim.fn.substitute(path, [=[\v([/\\]|^\w\zs:)\V]=], [[%]], 'g')
    return safepath
end

local function is_absolute()
    local last_chars = config.session_filepath:sub(-2)
    return last_chars == "//" or last_chars == "\\\\"
end

-- given a path (possibly empty or nil) returns the absolute session path or
-- the default session path if it exists. Will create intermediate directories
-- as needed. Returns nil otherwise.
---@param path string|nil
---@param ensure boolean|nil
---@return string|nil
local function get_session_path(path, ensure)
    if ensure == nil then
        ensure = true
    end

    if path and path ~= "" then
        path = vim.fn.fnamemodify(path, ":p")
        path = vim.fn.expand(path)
        path = vim.fn.simplify(path)
    elseif config.session_filepath ~= "" then
        local session_filepath = vim.fn.fnamemodify(config.session_filepath, ":p")
        if is_absolute() then
            local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
            path = session_filepath .. safe_path(cwd) .. "session"
        else
            path = session_filepath
        end
        path = vim.fn.expand(path)
        path = vim.fn.simplify(path)
    end

    if path and path ~= "" then
        if ensure and not ensure_path(path) then
            return nil
        end
        return path
    end

    return nil
end

-- set to nil when no session recording is active
---@type string|nil
local session_file_path = nil

---@param path? string
local function write_session_file(path)
    local target_path = path or session_file_path
    if not target_path then
        vim.notify("sessions.nvim: failed to save session file", levels.ERROR)
        return
    end
    -- escape vim.cmd special characters
    target_path = vim.fn.substitute(target_path, '[#% ]', [[\\&]], 'g')
    vim.cmd(string.format("mksession! %s", target_path))
end

---@param path string|nil
local function start_autosave_internal(path)
    session_file_path = get_session_path(path, false)

    if not session_file_path then
        vim.notify("sessions.nvim: failed to start autosave, config session_filepath is not defined", levels.ERROR)
        return
    end

    local augroup = vim.api.nvim_create_augroup("sessions.nvim", {})
    vim.api.nvim_create_autocmd(
        config.events,
        {
            group = augroup,
            pattern = "*",
            callback = function() write_session_file() end,
        }
    )
end

-- start autosaving changes to the session file
---@param path string|nil
function M.start_autosave(path)
    start_autosave_internal(path)
end

-- stop autosaving changes to the session file
---@param opts table
function M.stop_autosave(opts)
    if not session_file_path then
        return
    end

    opts = vim.tbl_deep_extend("force", {
        save = true,
    }, opts)

    vim.api.nvim_clear_autocmds({ group = "sessions.nvim" })
    vim.api.nvim_del_augroup_by_name("sessions.nvim")

    -- save before stopping
    if opts.save then
        write_session_file()
    end

    session_file_path = nil
end

-- save or overwrite a session file to the given path
---@param path string|nil
---@param opts table
function M.save(path, opts)
    opts = vim.tbl_deep_extend("force", {
        autosave = true,
    }, opts)

    path = get_session_path(path)
    if not path then
        vim.notify("sessions.nvim: failed to save session file", levels.ERROR)
        return
    end

    if opts.autosave then
        start_autosave_internal(path)
    end

    write_session_file(path)
end

-- load a session file from the given path
---@param path string|nil
---@param opts table
---@return boolean
function M.load(path, opts)
    opts = vim.tbl_deep_extend("force", {
        autosave = true,
        silent = false,
    }, opts)

    path = get_session_path(path, false)
    if not path or vim.fn.filereadable(path) == 0 then
        if not opts.silent then
            vim.notify(string.format("sessions.nvim: file '%s' does not exist", path))
        end
        return false
    end

    -- escape vim.cmd special characters
    path = vim.fn.substitute(path, '[#% ]', [[\\&]], 'g')
    vim.cmd(string.format("silent! source %s", path))

    if opts.autosave then
        start_autosave_internal(path)
    end

    return true
end

-- return true if currently recording a session
---@returns bool
function M.recording()
    return session_file_path ~= nil
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts)

    -- register commands
    vim.api.nvim_create_user_command(
        "SessionsSave",
        function(cmd_opts)
            local path = cmd_opts.fargs[1]
            local autosave = not cmd_opts.bang
            require("sessions").save(path, { autosave = autosave })
        end,
        { bang = true, nargs = "?", complete = "file" }
    )

    vim.api.nvim_create_user_command(
        "SessionsLoad",
        function(cmd_opts)
            local path = cmd_opts.fargs[1]
            local autosave = not cmd_opts.bang
            require("sessions").load(path, { autosave = autosave })
        end,
        { bang = true, nargs = "?", complete = "file" }
    )

    vim.api.nvim_create_user_command(
        "SessionsStop",
        function(cmd_opts)
            local save = not cmd_opts.bang
            require("sessions").stop_autosave({ save = save })
        end,
        { bang = true }
    )
end

return M
