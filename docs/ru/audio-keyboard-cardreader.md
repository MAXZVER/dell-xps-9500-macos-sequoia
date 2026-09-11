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

**Исправление. В прежней версии этого документа было написано, что картридер работает через `Sinetek-rtsx`.
Не работает и никогда не работал — просто карту туда ни разу не вставляли.** Утверждение снято, вот как
обстоит дело на самом деле.

### Почему Sinetek-rtsx здесь не может работать

Картридер в 9500 — это **Realtek RTS5260**:

```bash
ioreg -l -w0 | grep -oE '"IOName" = "pci10ec,[0-9a-f]+"' | sort -u
```

```
"IOName" = "pci10ec,5260"
```

А `Sinetek-rtsx` 2.5 обслуживает только вот эти:

```
0x5209 0x5227 0x5229 0x522A 0x5249 0x5286 0x5287 0x5289 0x525A
```

`5260` среди них нет. Поэтому кекст загружается, не выдаёт ни одной ошибки и **не подключается ни к чему** —
`ioreg -c RtsxPciChip` пуст. Добавление ID в `IOPCIMatch` не помогает: RTS5260 — следующее поколение с
другой инициализацией, и это уже пробовали
([Sinetek-rtsx, issue #17](https://github.com/cholonam/Sinetek-rtsx/issues/17)).

Вот ловушка, которую стоит запомнить: **загрузившийся кекст и работающий кекст — не одно и то же.**
Проверяйте, к чему он прикрепился, а не то, виден ли он в `kmutil showloaded`.

### Что работает

У [RealtekCardReader](https://github.com/0xFireWolf/RealtekCardReader) 0.9.7 есть личность
`RealtekRTS5260Controller` с совпадением `0x526010EC`.

```bash
sudo cp -R RealtekCardReader.kext /Library/Extensions/
sudo chown -R root:wheel /Library/Extensions/RealtekCardReader.kext
sudo chmod -R 755 /Library/Extensions/RealtekCardReader.kext
sudo cp scripts/com.local.realtekcardreader.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.realtekcardreader.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.realtekcardreader.plist
```

Первая загрузка провалится с сообщением

```
Extension with identifiers science.firewolf.rtsx not approved to load.
Please approve using System Settings.
```

Это ожидаемо для кекста, загружаемого в работающую систему, а не внедрённого через OpenCore. Разрешите его
в **Системные настройки → Конфиденциальность и безопасность** (кнопка «Разрешить»), перезагрузитесь — дальше
он грузится сам.

Проверяйте не факт загрузки, а факт подключения:

```bash
ioreg -c RealtekRTS5260Controller -w0 | grep -c '+-o'     # должно быть 1
diskutil info disk4 | grep 'Device / Media Name'          # "Built In SDXC Reader"
```

Измерено здесь: карта SDXC на 64 ГБ определяется, `Protocol: Secure Digital`, чтение **23 МБ/с**.

### Оговорки, честно

- 0.9.7 — бета, последнее обновление **октябрь 2022**, автор заявляет поддержку только до Monterey. Sequoia
  им не проверялась. Здесь драйвер прочитал 52 ГБ файлов без срывов, но это одна машина и один сеанс.
- 23 МБ/с заметно ниже того, что должен давать UHS-I (80–90 МБ/с) — быстрые режимы шины драйвер, очевидно,
  не согласовывает.
- Карты MMC и SD Express не поддерживаются вовсе.
- `Sinetek-rtsx` можно удалить из `/Library/Extensions` вместе с его LaunchDaemon — на этой машине он
  никогда ни с чем не совпадёт.

### Если карта определилась, но не монтируется

Это стоит знать, потому что выглядит как отказ драйвера, а им не является. Карта, отформатированная
видеорегистратором (или любым linux-овым `mkfs.fat`), может нести файловую систему FAT32, тогда как **байт
типа раздела** в MBR стоит `0x07`, то есть NTFS:

```bash
sudo fdisk /dev/disk4
```

```
1: 07 ... HPFS/QNX/AUX
```

macOS верит этому байту и зовёт `ntfs.fs` — а **`mount_ntfs` в Sequoia больше нет**, Apple удалила
вспомогательную программу для чтения NTFS. Результат: `Volume on disk4s1 failed to mount`. Монтируйте
вручную:

```bash
sudo mkdir -p /Volumes/SDCARD
sudo mount -t msdos -o ro,noowners /dev/disk4s1 /Volumes/SDCARD
```

Либо смените байт типа на `0x0C`, и Finder будет подхватывать карту сам — но это запись на карту, так что
делайте осознанно.
