-- AI_CORRECTOR_MVP
-- Global hotkeys:
--   cmd+shift+G fixes selected text with the local Ollama corrector.
--   ctrl+alt+G is kept as a fallback.

local defaultConfig = {
  pythonPath = "/usr/bin/env",
  scriptPath = os.getenv("HOME") .. "/ai-corrector/corrector.py",
  model = os.getenv("AI_CORRECTOR_MODEL") or "gemma3:4b",
  timeout = "120",
}

local configPath = os.getenv("HOME") .. "/.hammerspoon/ai-corrector-config.lua"
local ok, loadedConfig = pcall(dofile, configPath)

if ok and type(loadedConfig) == "table" then
  for key, value in pairs(loadedConfig) do
    defaultConfig[key] = value
  end
end

local activeTask = nil
local logPath = os.getenv("HOME") .. "/ai-corrector/hammerspoon.log"

local function log(message)
  local file = io.open(logPath, "a")

  if file == nil then
    return
  end

  file:write(os.date("%Y-%m-%d %H:%M:%S"), " ", message, "\n")
  file:close()
end

local function trim(value)
  if value == nil then
    return ""
  end

  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clipboardSnapshot()
  local snapshotOk, snapshot = pcall(hs.pasteboard.readAllData, nil)

  if snapshotOk and type(snapshot) == "table" and next(snapshot) ~= nil then
    return snapshot
  end

  return nil
end

local function restoreClipboard(snapshot)
  if snapshot ~= nil then
    local restoreOk, restored = pcall(hs.pasteboard.writeAllData, nil, snapshot)

    if restoreOk and restored then
      return
    end
  end

  hs.pasteboard.clearContents()
end

local function removeFile(path)
  if path ~= nil and path ~= "" then
    os.remove(path)
  end
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function writeInputFile(selectedText)
  local tmpDir = os.getenv("TMPDIR") or "/tmp/"
  local path = tmpDir .. "ai-corrector-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000000)) .. ".txt"
  local file = io.open(path, "w")

  if file == nil then
    return nil
  end

  file:write(selectedText)
  file:close()

  return path
end

local function newTask(inputPath, clipboardBefore)
  local executable = defaultConfig.pythonPath
  local arguments = {
    defaultConfig.scriptPath,
    "--input-file", inputPath,
    "--model", defaultConfig.model,
    "--timeout", defaultConfig.timeout,
  }

  if executable == "/usr/bin/env" then
    arguments = {
      "python3",
      defaultConfig.scriptPath,
      "--input-file", inputPath,
      "--model", defaultConfig.model,
      "--timeout", defaultConfig.timeout,
    }
  end

  log("starting task: " .. executable .. " " .. table.concat(arguments, " "))

  local task = hs.task.new(
    executable,
    function(exitCode, stdOut, stdErr)
      activeTask = nil
      removeFile(inputPath)
      log("task finished exit=" .. tostring(exitCode) .. " stdout_len=" .. tostring(#(stdOut or "")) .. " stderr=" .. trim(stdErr))

      if exitCode == 0 and trim(stdOut) ~= "" then
        hs.pasteboard.setContents(trim(stdOut))

        hs.timer.doAfter(0.05, function()
          hs.eventtap.keyStroke({"cmd"}, "v", 0)
        end)

        hs.timer.doAfter(1.0, function()
          restoreClipboard(clipboardBefore)
        end)

        hs.alert.show("Готово")
        return
      end

      restoreClipboard(clipboardBefore)

      local message = "Ошибка исправления"
      if trim(stdErr) ~= "" then
        message = message .. ": " .. trim(stdErr)
      end

      hs.alert.show(message)
    end,
    nil,
    arguments
  )

  return task
end

local function runCorrection(inputPath, clipboardBefore)
  local command = table.concat({
    shellQuote(defaultConfig.pythonPath),
    shellQuote(defaultConfig.scriptPath),
    "--input-file", shellQuote(inputPath),
    "--model", shellQuote(defaultConfig.model),
    "--timeout", shellQuote(defaultConfig.timeout),
  }, " ") .. " 2>&1"

  activeTask = true
  log("execute command: " .. command)

  hs.timer.doAfter(0.01, function()
    local output, status, exitType, rc = hs.execute(command, true)
    activeTask = nil
    removeFile(inputPath)
    log(
      "execute finished status="
      .. tostring(status)
      .. " type="
      .. tostring(exitType)
      .. " rc="
      .. tostring(rc)
      .. " output_len="
      .. tostring(#(output or ""))
      .. " output="
      .. trim(output)
    )

    if status and trim(output) ~= "" then
      hs.pasteboard.setContents(trim(output))

      hs.timer.doAfter(0.05, function()
        hs.eventtap.keyStroke({"cmd"}, "v", 0)
      end)

      hs.timer.doAfter(1.0, function()
        restoreClipboard(clipboardBefore)
      end)

      hs.alert.show("Готово")
      return
    end

    restoreClipboard(clipboardBefore)

    local message = "Ошибка исправления"
    if trim(output) ~= "" then
      message = message .. ": " .. trim(output)
    end

    hs.alert.show(message)
  end)
end

local function correctSelectedText()
  if activeTask ~= nil then
    hs.alert.show("Уже исправляю текст")
    return
  end

  local clipboardBefore = clipboardSnapshot()
  local marker = "AI_CORRECTOR_COPY_SENTINEL_" .. tostring(os.time()) .. "_" .. tostring(math.random())

  hs.pasteboard.setContents(marker)
  hs.eventtap.keyStroke({"cmd"}, "c", 0)

  hs.pasteboard.callbackWhenChanged(nil, 1.0, function(changed)
    local selectedText = hs.pasteboard.getContents()

    if not changed or selectedText == marker or trim(selectedText) == "" then
      restoreClipboard(clipboardBefore)
      hs.alert.show("Сначала выдели текст")
      return
    end

    hs.alert.show("Исправляю...")
    log("selected text length=" .. tostring(#selectedText))

    local inputPath = writeInputFile(selectedText)
    if inputPath == nil then
      restoreClipboard(clipboardBefore)
      hs.alert.show("Не получилось создать временный файл")
      log("failed to create input file")
      return
    end

    runCorrection(inputPath, clipboardBefore)
  end)
end

hs.hotkey.bind({"cmd", "shift"}, "G", correctSelectedText)
hs.hotkey.bind({"ctrl", "alt"}, "G", correctSelectedText)

hs.alert.show("AI Corrector: Cmd+Shift+G")
