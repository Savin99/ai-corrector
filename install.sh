#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${AI_CORRECTOR_DOWNLOAD_DIR:-"$PROJECT_DIR/.downloads"}"
INSTALL_DIR="${AI_CORRECTOR_INSTALL_DIR:-"$HOME/ai-corrector"}"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
MODEL="${AI_CORRECTOR_MODEL:-qwen3.5:4b-q4_K_M}"
HS_LOADER="$HAMMERSPOON_DIR/init.lua"
HS_SCRIPT="$HAMMERSPOON_DIR/ai-corrector.lua"
HS_CONFIG="$HAMMERSPOON_DIR/ai-corrector-config.lua"
OLLAMA_APP_CLI="/Applications/Ollama.app/Contents/Resources/ollama"
HAMMERSPOON_VERSION="${AI_CORRECTOR_HAMMERSPOON_VERSION:-1.1.1}"
HAMMERSPOON_URL="https://github.com/Hammerspoon/hammerspoon/releases/download/${HAMMERSPOON_VERSION}/Hammerspoon-${HAMMERSPOON_VERSION}.zip"
OLLAMA_BIN=""

download_file() {
  local url="$1"
  local output="$2"
  local attempt

  mkdir -p "$(dirname "$output")"

  if [[ -f "$output" ]] && unzip -tq "$output" >/dev/null 2>&1; then
    echo "Использую уже скачанный архив: $output"
    return
  fi

  for attempt in $(seq 1 60); do
    if [[ -f "$output" ]]; then
      echo "Попытка $attempt: продолжаю с $(du -h "$output" | awk '{print $1}')"
    else
      echo "Попытка $attempt: начинаю скачивание"
    fi

    if curl --fail --location --continue-at - \
      --connect-timeout 20 --speed-limit 1024 --speed-time 30 \
      -o "$output" \
      "$url"; then
      return
    fi

    echo "Скачивание оборвалось, повторю через 2 секунды..."
    sleep 2
  done

  echo "Не получилось скачать $url" >&2
  exit 1
}

find_ollama() {
  if command -v ollama >/dev/null 2>&1; then
    OLLAMA_BIN="$(command -v ollama)"
    return 0
  fi

  if [[ -x "$OLLAMA_APP_CLI" ]]; then
    OLLAMA_BIN="$OLLAMA_APP_CLI"
    return 0
  fi

  return 1
}

install_ollama_app() {
  if find_ollama; then
    return
  fi

  echo "Ollama не найден. Скачиваю официальный Ollama.app для macOS..."

  local tmp_dir
  local archive
  tmp_dir="$(mktemp -d)"
  archive="$DOWNLOAD_DIR/Ollama-darwin.zip"

  download_file "https://ollama.com/download/Ollama-darwin.zip" "$archive"

  unzip -q "$archive" -d "$tmp_dir"

  if [[ -d /Applications/Ollama.app ]]; then
    rm -rf /Applications/Ollama.app
  fi

  mv "$tmp_dir/Ollama.app" /Applications/Ollama.app 2>/dev/null || sudo mv "$tmp_dir/Ollama.app" /Applications/Ollama.app
  OLLAMA_BIN="$OLLAMA_APP_CLI"
  rm -rf "$tmp_dir"

  echo "Ollama установлен в /Applications/Ollama.app"
}

install_hammerspoon_app() {
  if [[ -d /Applications/Hammerspoon.app ]]; then
    return
  fi

  echo "Hammerspoon не найден. Скачиваю официальный релиз ${HAMMERSPOON_VERSION}..."

  local tmp_dir
  local archive
  tmp_dir="$(mktemp -d)"
  archive="$DOWNLOAD_DIR/Hammerspoon-${HAMMERSPOON_VERSION}.zip"

  download_file "$HAMMERSPOON_URL" "$archive"

  unzip -q "$archive" -d "$tmp_dir"

  if [[ ! -d "$tmp_dir/Hammerspoon.app" ]]; then
    rm -rf "$tmp_dir"
    echo "В архиве Hammerspoon не найден Hammerspoon.app." >&2
    exit 1
  fi

  mv "$tmp_dir/Hammerspoon.app" /Applications/Hammerspoon.app 2>/dev/null || sudo mv "$tmp_dir/Hammerspoon.app" /Applications/Hammerspoon.app
  rm -rf "$tmp_dir"

  echo "Hammerspoon установлен в /Applications/Hammerspoon.app"
}

ensure_ollama_running() {
  if curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    return
  fi

  echo "Запускаю Ollama..."
  open -a Ollama --args hidden >/dev/null 2>&1 || true
  sleep 3

  if curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    return
  fi

  nohup "$OLLAMA_BIN" serve >"$HOME/ai-corrector-ollama.log" 2>&1 &
  sleep 3

  if ! curl -fsS http://localhost:11434/api/version >/dev/null 2>&1; then
    echo "Не получилось запустить Ollama автоматически." >&2
    echo "Открой Ollama вручную или запусти: ollama serve" >&2
    exit 1
  fi
}

write_hammerspoon_loader() {
  mkdir -p "$HAMMERSPOON_DIR"

  if [[ ! -f "$HS_LOADER" ]]; then
    cat >"$HS_LOADER" <<'LUA'
-- AI_CORRECTOR_MVP_BEGIN
local ok, err = pcall(dofile, os.getenv("HOME") .. "/.hammerspoon/ai-corrector.lua")
if not ok then
  hs.alert.show("AI Corrector failed: " .. tostring(err))
end
-- AI_CORRECTOR_MVP_END
LUA
    return
  fi

  if grep -q "AI_CORRECTOR_MVP_BEGIN" "$HS_LOADER"; then
    return
  fi

  local backup="$HS_LOADER.backup.$(date +%Y%m%d%H%M%S)"
  cp "$HS_LOADER" "$backup"

  cat >>"$HS_LOADER" <<'LUA'

-- AI_CORRECTOR_MVP_BEGIN
local ok, err = pcall(dofile, os.getenv("HOME") .. "/.hammerspoon/ai-corrector.lua")
if not ok then
  hs.alert.show("AI Corrector failed: " .. tostring(err))
end
-- AI_CORRECTOR_MVP_END
LUA

  echo "Существующий Hammerspoon init.lua сохранён в $backup"
}

reload_hammerspoon() {
  open -a Hammerspoon >/dev/null 2>&1 || true

  if command -v hs >/dev/null 2>&1; then
    hs -c 'hs.reload()' >/dev/null 2>&1 || true
  fi
}

model_is_installed() {
  "$OLLAMA_BIN" list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$MODEL"
}

pull_model() {
  local attempt

  if model_is_installed; then
    echo "Модель $MODEL уже установлена."
    return
  fi

  echo "Скачиваю модель $MODEL..."

  for attempt in $(seq 1 30); do
    echo "Попытка $attempt из 30..."

    if "$OLLAMA_BIN" pull "$MODEL"; then
      return
    fi

    if model_is_installed; then
      echo "Модель $MODEL установлена."
      return
    fi

    echo "Скачивание модели оборвалось, повторю через 5 секунд..."
    sleep 5
  done

  echo "Не получилось скачать модель $MODEL." >&2
  echo "Можно повторить позже: $OLLAMA_BIN pull $MODEL" >&2
  exit 1
}

main() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 не найден. Установи Python 3 и запусти install.sh ещё раз." >&2
    exit 1
  fi

  install_ollama_app
  install_hammerspoon_app

  local python_bin
  python_bin="$(command -v python3)"

  mkdir -p "$INSTALL_DIR"
  mkdir -p "$HAMMERSPOON_DIR"
  install -m 755 "$PROJECT_DIR/corrector.py" "$INSTALL_DIR/corrector.py"
  install -m 644 "$PROJECT_DIR/hammerspoon/init.lua" "$HS_SCRIPT"

  cat >"$HS_CONFIG" <<LUA
return {
  pythonPath = "$python_bin",
  scriptPath = "$INSTALL_DIR/corrector.py",
  model = "$MODEL",
}
LUA

  write_hammerspoon_loader
  ensure_ollama_running

  pull_model

  reload_hammerspoon

  cat <<EOF

Готово.

1. Дай Hammerspoon права:
   System Settings -> Privacy & Security -> Accessibility -> Hammerspoon -> On

2. Выдели текст в любом поле ввода и нажми Cmd+Shift+G.

3. CLI-проверка:
   echo "текст с ашибками" | "$INSTALL_DIR/corrector.py"

EOF
}

main "$@"
