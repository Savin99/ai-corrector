# Local macOS Text Corrector

Локальный системный корректор текста для macOS: выделяешь текст, нажимаешь `Cmd+Shift+G`, Hammerspoon копирует выделение, Python-скрипт отправляет его в Ollama, а исправленный текст вставляется обратно.

MVP использует одну модель по умолчанию:

```text
gemma3:4b
```

Это практичный вариант для MacBook Air M3 с 8 GB unified memory: модель весит около 3.3 GB и лучше отработала на русских тестовых фразах.

## Установка

```bash
./install.sh
```

Скрипт:

- проверит, что `python3` уже доступен;
- установит Ollama через официальный macOS zip с `ollama.com`, если его нет;
- установит Hammerspoon из официального GitHub-релиза, если его нет;
- скопирует `corrector.py` в `~/ai-corrector/corrector.py`;
- добавит Hammerspoon loader в `~/.hammerspoon/init.lua`;
- установит Hammerspoon-скрипт в `~/.hammerspoon/ai-corrector.lua`;
- скачает модель `gemma3:4b`.

После установки включи права для Hammerspoon:

```text
System Settings -> Privacy & Security -> Accessibility -> Hammerspoon -> On
```

## Использование

Глобальный хоткей:

```text
Cmd+Shift+G
```

Запасной хоткей:

```text
Ctrl+Option+G
```

CLI:

```bash
echo "Слушай ну я не знаю как правельно это написать" | ./corrector.py
```

Переопределить модель можно через переменную окружения:

```bash
AI_CORRECTOR_MODEL=qwen3.5:4b-q4_K_M ./install.sh
```

или для разового CLI-запуска:

```bash
echo "текст" | AI_CORRECTOR_MODEL=qwen3.5:4b-q4_K_M ./corrector.py
```

## Что делает корректор

- исправляет орфографию, пунктуацию и грамматику;
- сохраняет смысл, тон и степень неформальности;
- не добавляет новые факты;
- не меняет имена, ссылки, цифры, названия сервисов, команды и технические термины;
- возвращает только готовый исправленный текст.

## Проверка

Синтаксис Python:

```bash
python3 -m py_compile corrector.py
```

Unit-тесты локальных защит:

```bash
python3 -m unittest discover -s tests
```

Пустой ввод должен вернуть ошибку:

```bash
printf "" | ./corrector.py
```

Если Ollama не запущен, CLI вернёт понятную ошибку подключения.

## Troubleshooting

Если хоткей ничего не делает, проверь права Hammerspoon в Accessibility и перезагрузи конфиг через меню Hammerspoon.

Если видишь ошибку подключения к Ollama:

```bash
/Applications/Ollama.app/Contents/Resources/ollama serve
```

Если модель слишком медленная, оставь 4B-модель. Для 8 GB RAM не стоит делать 9B основной моделью.
