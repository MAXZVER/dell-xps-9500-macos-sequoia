# Звук, клавиатура, картридер

Мелкие правки, каждая из которых отняла больше времени, чем должна была.

## Звук

```
PciRoot(0x0)/Pci(0x1F,0x3)
    layout-id   = 13
    hda-gfx     = onboard-1
    model       = Smart Sound Technology Audio Controller
```

вместе с `AppleALC.kext`. Динамики, гнездо наушников и звук по HDMI работают сразу.

Обратите внимание: `#device-id = C8 9D 00 00` в конфиге есть, но **закомментирован** — символ `#` в начале
отключает свойство. Контроллер опознаётся и без подмены на `0x9DC8`; запись оставлена на случай, если
будущая macOS перестанет его определять.

### Беда с микрофоном

Встроенный микрофон работает, но по умолчанию все программы получают тишину. Причина конкретная и стоит
того, чтобы её назвать прямо:

AppleALC с `layout-id 13` создаёт **два** входных устройства — внутренний микрофон и вход с гнезда 3,5 мм.
Устройство гнезда появляется примерно через 15 секунд после загрузки, то есть *позже* внутреннего, а
`coreaudiod` придерживается правила «последнее появившееся устройство становится основным». В результате
основным входом оказывается гнездо, в которое ничего не воткнуто. Ваша сохранённая настройка при этом
правильная — её просто перебивают.

`tools/micguard.swift` следит за этим и возвращает основной вход на внутренний микрофон. Внешние микрофоны
(USB, Bluetooth) он намеренно не трогает и вмешивается только тогда, когда основным стало *встроенное*
устройство, отличное от внутреннего микрофона.

```bash
swiftc -O tools/micguard.swift -o ~/tools/micguard
cp scripts/com.local.micguard.plist ~/Library/LaunchAgents/   # сначала поправьте YOUR_USERNAME
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.local.micguard.plist
```

## Клавиатура и тачпад

`VoodooPS2Controller.kext` с плагином `VoodooPS2Keyboard` — клавиатура, `VoodooI2C` + `VoodooI2CHID` —
точный тачпад. Жесты работают.

### Command туда, где его ждёт пользователь Mac

На клавиатуре PC клавиша рядом с пробелом — `Alt`, и macOS читает её как `Option`. Если хочется, чтобы там
был `Cmd` как на Mac, модификаторы надо поменять местами.

`scripts/com.local.keyswap.plist` ставит LaunchDaemon, который при загрузке запускает `hidutil` и меняет
Option ↔ Command с обеих сторон.

```bash
sudo cp scripts/com.local.keyswap.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.keyswap.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.keyswap.plist
```

**Именно демон.** `hidutil property --set` не переживает перезагрузку — раскладка модификаторов слетает
каждый раз, а штатная панель «Клавиши-модификаторы» в macOS этот случай не покрывает. Если выставить
руками, всё выглядит рабочим ровно до перезагрузки.

### Русская раскладка: берите «Русская — ПК»

В обычной раскладке **Русская** точка и запятая стоят не там, где на клавиатуре PC, а `ё` — вообще в
другом месте. Если на клавишах нанесена раскладка PC, это сводит с ума.

Выбирайте **Русская — ПК** (внутреннее имя `RussianWin`, идентификатор `19458`). Тогда знаки препинания и
`ё` совпадут с гравировкой. Для английского по той же причине лучше **U.S.**, а не **ABC** — `ABC` немного
другая раскладка, и однажды она вас удивит.

Системные настройки → Клавиатура → Источники ввода → добавить *Русская — ПК*, убрать обычную *Русская*.

## Картридер SD

Ридер Realtek обслуживает `Sinetek-rtsx.kext`. Он лежит и в `EFI/OC/Kexts`, **и** установлен в
`/Library/Extensions`, а LaunchDaemon грузит его при старте:

```bash
sudo cp -R EFI/OC/Kexts/Sinetek-rtsx.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/Sinetek-rtsx.kext
sudo cp scripts/com.local.cardreader.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.cardreader.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.cardreader.plist
```

Демон просто выполняет `kmutil load -p /Library/Extensions/Sinetek-rtsx.kext`. Журнал пишется в
`/var/log/cardreader.log` — смотрите туда, если карта не монтируется.

Драйвер написан сообществом и по надёжности до фирменного не дотягивает. Относитесь к нему как к
«работает в обычных случаях»: обычные SD-карты читает, но полагаться на него в чём-то важном не стоит.
