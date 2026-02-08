local M = {}

M.config = {
  keymap = "<C-'>",
  pull_keymap = "<C-r>",
  push_keymap = "<C-y>",
  fetch_keymap = "<C-m>",
}

local function get_current_branch()
  local result = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

local function get_local_branches()
  local result = vim.fn.system("git branch --format='%(refname:short)' 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return {}
  end
  local branches = {}
  for line in result:gmatch("[^\r\n]+") do
    table.insert(branches, line)
  end
  return branches
end

local function get_remote_branches()
  local result = vim.fn.system("git branch -r --format='%(refname:short)' 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return {}
  end
  local branches = {}
  for line in result:gmatch("[^\r\n]+") do
    -- Skip HEAD pointer (e.g., origin/HEAD)
    if not line:match("/HEAD$") then
      table.insert(branches, line)
    end
  end
  return branches
end

local function get_all_branches()
  local local_branches = get_local_branches()
  local remote_branches = get_remote_branches()

  -- Create a set of local branch names for quick lookup
  local local_set = {}
  for _, branch in ipairs(local_branches) do
    local_set[branch] = true
  end

  -- Add remote branches that don't have a corresponding local branch
  local all_branches = {}
  for _, branch in ipairs(local_branches) do
    table.insert(all_branches, { name = branch, is_remote = false })
  end

  for _, remote_branch in ipairs(remote_branches) do
    -- Extract branch name without remote prefix (e.g., "origin/feature" -> "feature")
    local branch_name = remote_branch:match("^[^/]+/(.+)$")
    if branch_name and not local_set[branch_name] then
      table.insert(all_branches, { name = remote_branch, is_remote = true })
    end
  end

  return all_branches
end

local function fuzzy_match(str, pattern)
  if pattern == "" then
    return true, 0
  end
  local score = 0
  local pattern_idx = 1
  local pattern_lower = pattern:lower()
  local str_lower = str:lower()

  for i = 1, #str_lower do
    if pattern_idx <= #pattern_lower and str_lower:sub(i, i) == pattern_lower:sub(pattern_idx, pattern_idx) then
      score = score + 1
      if i == pattern_idx then
        score = score + 1
      end
      pattern_idx = pattern_idx + 1
    end
  end

  local matched = pattern_idx > #pattern_lower
  return matched, matched and score or 0
end

local function filter_branches(branches, input)
  local results = {}
  for _, branch_info in ipairs(branches) do
    local branch_name = branch_info.name
    local matched, score = fuzzy_match(branch_name, input)
    if matched then
      -- Prioritize local branches over remote branches
      local priority = branch_info.is_remote and 0 or 100
      table.insert(results, {
        name = branch_name,
        is_remote = branch_info.is_remote,
        score = score + priority,
      })
    end
  end
  table.sort(results, function(a, b)
    return a.score > b.score
  end)
  return results
end

local function branch_exists(branches, name)
  for _, branch_info in ipairs(branches) do
    if branch_info.name == name then
      return true, branch_info.is_remote
    end
  end
  return false, false
end

local function git_switch_to_remote(remote_branch)
  -- Extract local branch name from remote branch (e.g., "origin/feature" -> "feature")
  local local_name = remote_branch:match("^[^/]+/(.+)$")
  if not local_name then
    vim.notify("Invalid remote branch name: " .. remote_branch, vim.log.levels.ERROR)
    return false
  end

  -- Create local branch tracking the remote branch
  local cmd = string.format(
    "git switch -c %s --track %s",
    vim.fn.shellescape(local_name),
    vim.fn.shellescape(remote_branch)
  )

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Git switch failed: " .. vim.trim(result), vim.log.levels.ERROR)
    return false
  end
  vim.notify("Created and switched to branch: " .. local_name .. " (tracking " .. remote_branch .. ")", vim.log.levels.INFO)
  return true
end

local function git_switch(branch_name, is_new)
  local cmd
  if is_new then
    cmd = string.format("git switch -c %s", vim.fn.shellescape(branch_name))
  else
    cmd = string.format("git switch %s", vim.fn.shellescape(branch_name))
  end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Git switch failed: " .. vim.trim(result), vim.log.levels.ERROR)
    return false
  end
  vim.notify("Switched to branch: " .. branch_name, vim.log.levels.INFO)
  return true
end

local function git_pull_in_terminal(branch_name)
  local cmd = string.format("git pull origin %s", vim.fn.shellescape(branch_name))
  vim.cmd("botright new | resize 10")
  vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.notify("Pulled from origin/" .. branch_name, vim.log.levels.INFO)
      end
    end,
  })
  vim.schedule(function()
    vim.cmd("startinsert!")
  end)
end

local function git_push_in_terminal(branch_name)
  local cmd = string.format("git push origin %s", vim.fn.shellescape(branch_name))
  vim.cmd("botright new | resize 10")
  vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.notify("Pushed to origin/" .. branch_name, vim.log.levels.INFO)
      end
    end,
  })
  vim.schedule(function()
    vim.cmd("startinsert!")
  end)
end

local function git_fetch_in_terminal(callback)
  local cmd = "git fetch --all --prune"
  vim.cmd("botright new | resize 10")
  vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.notify("Fetched from remote", vim.log.levels.INFO)
        if callback then
          vim.schedule(callback)
        end
      end
    end,
  })
  vim.schedule(function()
    vim.cmd("startinsert!")
  end)
end

function M.open()
  local current_branch = get_current_branch()
  if not current_branch then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end

  local branches = get_all_branches()
  local popup_buf = vim.api.nvim_create_buf(false, true)
  local result_buf = vim.api.nvim_create_buf(false, true)

  local width = math.floor(vim.o.columns * 0.8)
  local height = 1
  local max_result_height = math.floor(vim.o.lines * 0.5)
  local result_height = math.max(5, math.min(max_result_height, #branches))
  local row = math.floor((vim.o.lines - height - result_height - 4) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Switch Branch (Current: " .. current_branch .. ") ",
    title_pos = "center",
  })

  local result_win = vim.api.nvim_open_win(result_buf, false, {
    relative = "editor",
    width = width,
    height = result_height,
    row = row + height + 2,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Branches ",
    title_pos = "center",
  })

  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, { current_branch })
  vim.api.nvim_set_option_value("modifiable", true, { buf = popup_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = popup_buf })

  vim.cmd("startinsert!")
  vim.api.nvim_win_set_cursor(popup_win, { 1, #current_branch })

  vim.api.nvim_set_option_value("modifiable", false, { buf = result_buf })
  vim.api.nvim_set_option_value("cursorline", true, { win = result_win })

  local selected_idx = 0
  local filtered = {}

  local function update_results()
    local input = vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1] or ""
    filtered = filter_branches(branches, input)

    vim.api.nvim_set_option_value("modifiable", true, { buf = result_buf })
    local display_lines = {}
    for i, branch_info in ipairs(filtered) do
      local prefix = (i == selected_idx + 1) and "> " or "  "
      local suffix = branch_info.is_remote and " [remote]" or ""
      table.insert(display_lines, prefix .. branch_info.name .. suffix)
    end
    if #display_lines == 0 then
      display_lines = { "  (new branch)" }
    end
    vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, display_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = result_buf })

    local new_height = math.max(1, math.min(max_result_height, #display_lines))
    vim.api.nvim_win_set_config(result_win, {
      relative = "editor",
      width = width,
      height = new_height,
      row = row + height + 2,
      col = col,
    })

    if selected_idx >= #filtered then
      selected_idx = math.max(0, #filtered - 1)
    end
    if #filtered > 0 then
      vim.api.nvim_win_set_cursor(result_win, { selected_idx + 1, 0 })
    end
  end

  local function close_windows()
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
    if vim.api.nvim_win_is_valid(result_win) then
      vim.api.nvim_win_close(result_win, true)
    end
    if vim.api.nvim_buf_is_valid(popup_buf) then
      vim.api.nvim_buf_delete(popup_buf, { force = true })
    end
    if vim.api.nvim_buf_is_valid(result_buf) then
      vim.api.nvim_buf_delete(result_buf, { force = true })
    end
  end

  local function execute_switch()
    local input = vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1] or ""
    input = vim.trim(input)

    if input == "" then
      vim.notify("Branch name cannot be empty", vim.log.levels.WARN)
      return
    end

    close_windows()

    local exists, is_remote = branch_exists(branches, input)
    if is_remote then
      -- Remote branch selected: create local tracking branch
      git_switch_to_remote(input)
    else
      -- Local branch or new branch
      git_switch(input, not exists)
    end
  end

  vim.keymap.set("i", "<CR>", function()
    execute_switch()
  end, { buffer = popup_buf, noremap = true, silent = true })

  vim.keymap.set("i", "<Esc>", function()
    close_windows()
  end, { buffer = popup_buf, noremap = true, silent = true })

  vim.keymap.set("i", "<C-c>", function()
    close_windows()
  end, { buffer = popup_buf, noremap = true, silent = true })

  vim.keymap.set("i", "<C-n>", function()
    if #filtered > 0 then
      selected_idx = (selected_idx + 1) % #filtered
      update_results()
    end
  end, { buffer = popup_buf, noremap = true, silent = true })

  vim.keymap.set("i", "<C-p>", function()
    if #filtered > 0 then
      selected_idx = (selected_idx - 1) % #filtered
      if selected_idx < 0 then
        selected_idx = #filtered - 1
      end
      update_results()
    end
  end, { buffer = popup_buf, noremap = true, silent = true })

  vim.keymap.set("i", "<Tab>", function()
    if #filtered > 0 and filtered[selected_idx + 1] then
      local branch_name = filtered[selected_idx + 1].name
      vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, { branch_name })
      vim.api.nvim_win_set_cursor(popup_win, { 1, #branch_name })
    end
  end, { buffer = popup_buf, noremap = true, silent = true })

  -- Emacs-like keybindings
  vim.keymap.set("i", "<C-f>", function()
    local cursor = vim.api.nvim_win_get_cursor(popup_win)
    local line = vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1] or ""
    if cursor[2] < #line then
      vim.api.nvim_win_set_cursor(popup_win, { 1, cursor[2] + 1 })
    end
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  vim.keymap.set("i", "<C-b>", function()
    local cursor = vim.api.nvim_win_get_cursor(popup_win)
    if cursor[2] > 0 then
      vim.api.nvim_win_set_cursor(popup_win, { 1, cursor[2] - 1 })
    end
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  vim.keymap.set("i", "<C-a>", function()
    vim.api.nvim_win_set_cursor(popup_win, { 1, 0 })
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  vim.keymap.set("i", "<C-e>", function()
    local line = vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1] or ""
    vim.api.nvim_win_set_cursor(popup_win, { 1, #line })
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  vim.keymap.set("i", "<C-k>", function()
    local cursor = vim.api.nvim_win_get_cursor(popup_win)
    local line = vim.api.nvim_buf_get_lines(popup_buf, 0, 1, false)[1] or ""
    local new_line = line:sub(1, cursor[2])
    vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, { new_line })
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  -- Git pull/push keybindings
  vim.keymap.set("i", M.config.pull_keymap, function()
    close_windows()
    git_pull_in_terminal(current_branch)
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  vim.keymap.set("i", M.config.push_keymap, function()
    close_windows()
    git_push_in_terminal(current_branch)
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  -- Git fetch keybinding
  vim.keymap.set("i", M.config.fetch_keymap, function()
    close_windows()
    git_fetch_in_terminal()
  end, { buffer = popup_buf, noremap = true, silent = true, nowait = true })

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = popup_buf,
    callback = function()
      selected_idx = 0
      update_results()
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = popup_buf,
    once = true,
    callback = function()
      close_windows()
    end,
  })

  update_results()
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  vim.keymap.set("n", M.config.keymap, function()
    M.open()
  end, { noremap = true, silent = true, desc = "Git Branch Switcher" })
end

return M
