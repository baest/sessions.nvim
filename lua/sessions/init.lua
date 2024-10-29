local util = require("sessions.util")

local levels = vim.log.levels

-- TODO: add session delete

-- default configuration
local config = {
    -- events which trigger a session save
    events = { "BufEnter", "VimLeavePre" },

    -- default session filepath
    session_filepath = "",

    hooks = {
        load = {},
        load_pre = {},
        save = {},
        save_pre = {},
    }
}

local M = {}

-- ensure full path to session file exists, and attempt to create intermediate
-- directories if needed
local ensure_path = function(path)
    local dir, name = util.path.split(path)
    if dir and vim.fn.isdirectory(dir) == 0 then
        if vim.fn.mkdir(dir, "p") == 0 then
            return false
        end
    end
    return name ~= ""
end

-- converts a given filepath to a string safe to be used as a session filename
local safe_path = function(path)
    if util.windows then
        return path:gsub(util.path.sep, "."):sub(4)
    else
        return path:gsub(util.path.sep, "."):sub(2)
    end
end


-- given a path (possibly empty or nil) returns the absolute session path or
-- the default session path if it exists. Will create intermediate directories
-- as needed. Returns nil otherwise.
---@param path string|nil
---@param ensure boolean|nil
---@return string|nil
local function get_session_path(path, ensure)
    ensure = ensure or true

    if path and path ~= "" then
        local inputPath = vim.fn.expand(path, ":p")

        --   if path is relative (may or may not contain slashes), append to basepath
        path = config.session_filepath .. util.path.sep .. inputPath

        if ensure then
            ensure_path(path)
        end

        return path
    end
    --
    --   if path is not provided:
    vim.notify(string.format("sessions.nvim: missing path"), levels.ERROR)
    return nil
end

---@param hook function|string
---@param event string|nil
---@param path string|nil
local run_hook = function(hook, event, path)
    if type(hook) == "function" then
        if hook(event, path) == false then
            return false
        end
    elseif type(hook) == "string" then
        vim.cmd(hook)
    else
        vim.notify(string.format("sessions.nvim: invalid hook '%s'", hook), levels.ERROR)
    end

    return true
end

---given a list of hooks, execute each in the order given
---@param hooks table|function|string
---@param event string|nil
---@param path string|nil
local run_hooks = function(hooks, event, path)
    if not hooks then
        return
    end

    if type(hooks) == "table" then
        for _, hook in ipairs(hooks) do
            if run_hook(hook, event, path) == false then
                return false
            end
        end
    else
        if run_hook(hooks, event, path) == false then
            return false
        end
    end

    return true
end


-- set to nil when no session recording is active
---@type string|nil
local session_file_path = nil


local write_session_file = function(event)
    run_hooks(config.hooks.save_pre, event, session_file_path)
    vim.cmd(string.format("mksession! %s", session_file_path))
    run_hooks(config.hooks.save_post, event, session_file_path)
end

-- start autosaving changes to the session file
local start_autosave = function()
    -- save future changes
    local augroup = vim.api.nvim_create_augroup("sessions.nvim", {})
    vim.api.nvim_create_autocmd(
        config.events,
        {
            group = augroup,
            pattern = "*",
            callback = function(event) write_session_file(event.event) end,
        }
    )

    -- save now
    write_session_file("Save")
end

-- stop autosaving changes to the session file
---@param opts table
M.stop_autosave = function(opts)
    if not session_file_path then return end

    opts = util.merge({
        save = true,
    }, opts)

    vim.api.nvim_clear_autocmds({ group = "sessions.nvim" })
    vim.api.nvim_del_augroup_by_name("sessions.nvim")

    -- save before stopping
    if opts.save then
        write_session_file("StopAutoSave")
    end

    session_file_path = nil
end

-- save or overwrite a session file to the given path
---@param path string|nil
---@param opts table
M.save = function(path, opts)
    -- TODO: prompt overwrite if file exists
    opts = util.merge({
        autosave = true,
    }, opts)

    path = get_session_path(path)
    if not path then
        vim.notify("sessions.nvim: failed to save session file", levels.ERROR)
        return
    end

    -- escape vim.cmd special characters
    session_file_path = vim.fn.fnameescape(path)
    write_session_file("Save")

    if opts.autosave then
        start_autosave()
    end
end

-- load a session file from the given path
---@param path string|nil
---@param opts table
---@return boolean
M.load = function(path, opts)
    opts = util.merge({
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
    session_file_path = vim.fn.fnameescape(path)
    run_hooks(config.hooks.load_pre, "Load", session_file_path)
    vim.cmd(string.format("silent! source %s", session_file_path))
    run_hooks(config.hooks.load_post, "Load", session_file_path)

    if opts.autosave then
        start_autosave()
    end

    return true
end

-- return true if currently recording a session
---@returns bool
M.recording = function()
    return session_file_path ~= nil
end

M.setup = function(opts)
    config = util.merge(config, opts)

    config.session_filepath = vim.fn.expand(config.session_filepath, ":p")

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
