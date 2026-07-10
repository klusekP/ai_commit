local M = {}

local default_prompt = table.concat({
  "You write concise, high-quality Git commit messages.",
  "Output only the commit message.",
  "First line: short imperative subject (<= 60 chars).",
  "Then blank line, then optional body wrapped around 72 chars.",
  "Use bullet points when helpful.",
  "Always respond in English.",
}, " ")

local default_config = {
  provider = "mlx",
  providers = {
    mlx = {
      url = "http://127.0.0.1:8080",
      model = "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit",
      temperature = 0.2,
      timeout = 120000,
    },
    ollama = {
      url = "http://127.0.0.1:11434",
      model = "qwen2.5-coder:7b",
      temperature = 0.2,
      timeout = 120000,
    },
    openai = {
      url = "https://api.openai.com",
      model = "gpt-4o-mini",
      api_key = nil,
      temperature = 0.2,
      timeout = 120000,
    },
  },
  prompt = default_prompt,
  diff_excludes = { "*.cache", "*.log", "*.lock" },
}

local config = {}

local function notify(msg, level)
  if vim.notify then
    vim.notify(msg, level or vim.log.levels.INFO, { title = "AI Commit" })
  end
end

local function get_diff()
  local excludes = {}
  for _, pattern in ipairs(config.diff_excludes or {}) do
    table.insert(excludes, ":(exclude)" .. pattern)
  end

  local args = { "git", "diff", "--cached", "--", "." }
  for _, e in ipairs(excludes) do
    table.insert(args, e)
  end

  local diff = vim.fn.systemlist(args)
  if vim.v.shell_error ~= 0 then
    return nil, "git diff --cached failed"
  end
  if not diff or vim.tbl_isempty(diff) then
    return nil, "No staged changes (use git add)."
  end
  return table.concat(diff, "\n")
end

local function get_issue_from_branch()
  local branch = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "HEAD" })[1]
  if not branch or branch == "" then
    return nil
  end
  local issue = branch:match("[A-Z][A-Z]+%-[0-9]+")
  if issue then
    return issue
  end
  issue = branch:match("([0-9]+)")
  if issue then
    return "#" .. issue
  end
  return nil
end

local function call_provider(diff)
  local providers = require("ai_commit.providers")
  local provider_name = config.provider
  local provider_config = config.providers[provider_name]

  if not provider_config then
    return nil, "Unknown provider: " .. tostring(provider_name)
  end

  local provider_fn = providers[provider_name]
  if not provider_fn then
    return nil, "Provider not implemented: " .. tostring(provider_name)
  end

  return provider_fn(provider_config, diff, config.prompt)
end

function M.generate()
  local diff, err = get_diff()
  if not diff then
    return nil, err
  end

  local msg, err2 = call_provider(diff)
  if not msg then
    return nil, err2
  end

  local issue = get_issue_from_branch()
  if issue then
    local lines = vim.split(msg, "\n", { plain = true })
    if #lines > 0 then
      lines[1] = issue .. ": " .. lines[1]
      msg = table.concat(lines, "\n")
    end
  end

  return msg
end

function M.apply_to_buffer()
  local ft = vim.bo.filetype
  if ft ~= "gitcommit" then
    notify("AICommit only works in gitcommit buffer.", vim.log.levels.WARN)
    return
  end

  notify("Generating commit message...", vim.log.levels.INFO)

  local msg, err = M.generate()
  if not msg then
    notify(err or "Failed to generate commit message.", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local old = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local first_comment
  for i, line in ipairs(old) do
    if line:match("^#") then
      first_comment = i - 1
      break
    end
  end

  local new_lines = vim.split(msg, "\n", { plain = true })

  if first_comment and first_comment >= 0 and first_comment < #old then
    for i = first_comment + 1, #old do
      table.insert(new_lines, old[i])
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  notify("AI commit message inserted.", vim.log.levels.INFO)
end

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", default_config, user_config or {})

  if config.prompt == nil then
    config.prompt = default_prompt
  end

  vim.api.nvim_create_user_command("AICommit", function()
    M.apply_to_buffer()
  end, { desc = "Generate commit message from staged diff (AI)" })

  vim.api.nvim_create_user_command("AICommitConfig", function()
    local msg = string.format(
      "AICommit config:\n  provider: %s\n  prompt: %s...",
      config.provider,
      string.sub(config.prompt, 1, 50)
    )
    notify(msg, vim.log.levels.INFO)
  end, { desc = "Show current AICommit configuration" })
end

return M
