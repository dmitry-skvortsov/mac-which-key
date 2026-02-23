# SKHD HUD Overlay (Hammerspoon + skhd)

Минималистичный HUD-оверлей для macOS: показывает стек текущих режимов `skhd` и доступные клавиши.

Английская версия: `README.md`.

## Что умеет

- Команды `push/pop/reset/show/hide` через `~/.config/skhd/hud.sh`
- Отрисовка HUD через `hs.canvas` (Hammerspoon), без JSON и polling
- Цвет фона зависит от глубины стека режимов
- Fade in/out 150 мс
- Перетаскивание HUD мышью при зажатом `Cmd`
- Сохранение позиции между перезагрузками Hammerspoon

## Требования

- macOS
- Установлен и запущен `Hammerspoon`
- Установлен `skhd`
- Установлен `hs` CLI (Hammerspoon -> Preferences -> Install Command Line Tool)

## Файлы

- `~/.config/skhd/hud.sh`
- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/skhd_hud.lua`
- `~/.hammerspoon/skhd_hud_position.lua` (создаётся автоматически после перетаскивания)

## Установка

1. Скопируйте файлы в домашние конфиги:

```bash
mkdir -p ~/.config/skhd ~/.hammerspoon
cp .config/skhd/hud.sh ~/.config/skhd/hud.sh
cp .hammerspoon/skhd_hud.lua ~/.hammerspoon/skhd_hud.lua
```

2. Сделайте скрипт исполняемым:

```bash
chmod +x ~/.config/skhd/hud.sh
```

3. Подключите модуль в `~/.hammerspoon/init.lua`:

```lua
require("skhd_hud")
```

Если в `init.lua` уже есть конфиг, просто добавьте строку `require("skhd_hud")` (один раз).

4. Перезагрузите Hammerspoon (`hs.reload()` в Console или пункт меню Reload Config).

## Настройка в skhd

Пример для `~/.skhdrc`:

```sh
window < r ; window_resize : ~/.config/skhd/hud.sh push window_resize "h(smaller)|l(larger)|k(taller)|j(shorter)"
window_resize < escape ; window : ~/.config/skhd/hud.sh pop
window < escape ; default : ~/.config/skhd/hud.sh reset
```

Можно вызывать и вручную:

```bash
~/.config/skhd/hud.sh push window "s|r"
~/.config/skhd/hud.sh push swap "h|j|k|l"
~/.config/skhd/hud.sh pop
~/.config/skhd/hud.sh reset
~/.config/skhd/hud.sh show
~/.config/skhd/hud.sh hide
```

## Использование

- `push <mode> "<options>"`: добавить уровень в стек и показать/обновить HUD
- `pop`: удалить верхний уровень
- `reset`: очистить стек и скрыть HUD
- `show` / `hide`: принудительно показать/скрыть HUD без изменения стека
  - если стек пуст, `show` покажет тестовую плашку `SKHD HUD`

Формат текста: `MODE1 → MODE2 → ... → options`.

## Перетаскивание и позиция

- Зажмите `Cmd` и тяните HUD мышью.
- Позиция сохраняется в `~/.hammerspoon/skhd_hud_position.lua` при отпускании кнопки мыши.
- После `hs.reload()` HUD подхватит сохранённые координаты.

## Быстрая проверка

1. Выполните `~/.config/skhd/hud.sh push window "s|r"` и проверьте, что HUD появился.
2. Выполните `~/.config/skhd/hud.sh push swap "h|j|k|l"` и проверьте, что цвет сменился на синий, текст обновился.
3. Выполните `~/.config/skhd/hud.sh pop` и проверьте возврат к предыдущему уровню.
4. Выполните `~/.config/skhd/hud.sh reset` и проверьте fade-out и скрытие.
5. Выполните `~/.config/skhd/hud.sh show` после `reset` и проверьте, что видна тестовая плашка `SKHD HUD`.

## Частые проблемы

- `hs: command not found`: установите CLI из Hammerspoon Preferences.
- HUD не появляется: проверьте, что `require("skhd_hud")` есть в `~/.hammerspoon/init.lua`, затем сделайте Reload Config.
- Команды из `skhd` не срабатывают: проверьте абсолютный путь до `hud.sh` и права `chmod +x`.
