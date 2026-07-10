local M = {}

local function get_json()
  if vim.json and vim.json.encode and vim.json.decode then
    return vim.json
  end
  return {
    encode = vim.fn.json_encode,
    decode = vim.fn.json_decode,
  }
end

function M.ollama(config, diff, system_prompt)
  local ok, curl = pcall(require, "plenary.curl")
  if not ok then
    return nil, "Missing plenary.curl plugin"
  end

  local json = get_json()
  local url = config.url or "http://127.0.0.1:11434"
  local model = config.model or "qwen2.5-coder:7b"

  local body = json.encode({
    model = model,
    stream = false,
    options = {
      temperature = config.temperature or 0.2,
    },
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = "Generate a commit message for this staged diff:\n\n" .. diff },
    },
  })

  local res = curl.post(url .. "/api/chat", {
    headers = { ["Content-Type"] = "application/json" },
    body = body,
    timeout = config.timeout or 120000,
  })

  if not res or res.status ~= 200 then
    local status = res and res.status or "no response"
    return nil, "Ollama error (status " .. status .. ")"
  end

  local decoded = json.decode(res.body)
  if not decoded or not decoded.message or not decoded.message.content then
    return nil, "Invalid Ollama response"
  end

  local content = decoded.message.content
  if content == "" then
    return nil, "Empty response from Ollama"
  end

  return content
end

function M.mlx(config, diff, system_prompt)
  local ok, curl = pcall(require, "plenary.curl")
  if not ok then
    return nil, "Missing plenary.curl plugin"
  end

  local json = get_json()
  local url = config.url or "http://127.0.0.1:8080"
  local model = config.model or "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"

  local body = json.encode({
    model = model,
    stream = false,
    temperature = config.temperature or 0.2,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = "Generate a commit message for this staged diff:\n\n" .. diff },
    },
  })

  local res = curl.post(url .. "/v1/chat/completions", {
    headers = { ["Content-Type"] = "application/json" },
    body = body,
    timeout = config.timeout or 120000,
  })

  if not res or res.status ~= 200 then
    local status = res and res.status or "no response"
    return nil, "MLX Server error (status " .. status .. ")"
  end

  local decoded = json.decode(res.body)
  if not decoded or not decoded.choices or not decoded.choices[1] or not decoded.choices[1].message then
    return nil, "Invalid MLX Server response"
  end

  local content = decoded.choices[1].message.content
  if content == "" then
    return nil, "Empty response from MLX Server"
  end

  return content
end

function M.openai(config, diff, system_prompt)
  local ok, curl = pcall(require, "plenary.curl")
  if not ok then
    return nil, "Missing plenary.curl plugin"
  end

  local json = get_json()
  local url = config.url or "https://api.openai.com"
  local model = config.model or "gpt-4o-mini"

  local body = json.encode({
    model = model,
    stream = false,
    temperature = config.temperature or 0.2,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = "Generate a commit message for this staged diff:\n\n" .. diff },
    },
  })

  local headers = { ["Content-Type"] = "application/json" }
  if config.api_key then
    headers["Authorization"] = "Bearer " .. config.api_key
  end

  local res = curl.post(url .. "/v1/chat/completions", {
    headers = headers,
    body = body,
    timeout = config.timeout or 120000,
  })

  if not res or res.status ~= 200 then
    local status = res and res.status or "no response"
    return nil, "OpenAI error (status " .. status .. ")"
  end

  local decoded = json.decode(res.body)
  if not decoded or not decoded.choices or not decoded.choices[1] or not decoded.choices[1].message then
    return nil, "Invalid OpenAI response"
  end

  local content = decoded.choices[1].message.content
  if content == "" then
    return nil, "Empty response from OpenAI"
  end

  return content
end

return M
