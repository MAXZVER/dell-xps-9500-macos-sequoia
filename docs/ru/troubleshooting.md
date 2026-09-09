# Диагностика

Конкретные команды и реальные сигнатуры в логах вместо общих советов.

## Читайте журнал *предыдущей* загрузки

Самый полезный приём. Единый журнал macOS переживает перезагрузку, поэтому, когда изменение оставило машину
без сети или иначе недоступной, можно загрузиться в рабочей конфигурации и прочитать, что происходило на
неудачной загрузке:

```bash
log show --style compact \
  --start "2026-09-09 16:22:00" --end "2026-09-09 16:36:00" \
  --predicate 'process == "airportd"' | head -60
```

Именно так была разобрана проблема с Wi-Fi — консоли на сбойной загрузке не было ни разу.

Полезные выборки:

```bash
# загрузка кекстов
log show --last 5m --style compact | grep "Received kext load notification"

# конкретный драйвер
log show --last 5m --style compact --predicate 'senderImagePath CONTAINS "AirportItlwm"'

# сгруппированные отказы ioctl 802.11
log show --last 5m --style compact \
  | grep -oE "IOCTL type [0-9]+/'[A-Z0-9_]+' return -?[0-9]+" | sort | uniq -c | sort -rn
```

## Сон

```bash
pmset -g custom                                    # что выставлено на самом деле
pmset -g log | grep -E "Sleep  |Wake  |DarkWake"   # что произошло на самом деле
ls -lh /var/vm/sleepimage                          # есть ли образ гибернации
```

Ищите **`Wake from Standby`**. Всё остальное означает, что гибернации не было. См.
[сон и гибернацию](sleep-hibernation.md#как-убедиться-что-это-действительно-гибернация).

## Bluetooth

```bash
system_profiler SPBluetoothDataType | grep -E "Address|State|Firmware"
ioreg -r -c IntelBluetoothFirmware -w0 | head -3
log show --last 5m --style compact | grep "selected configuration"
```

Правду говорит поле `Firmware Version`: `v256 c256` — жив, `v0` — мёртв. И **подождите хотя бы две минуты
после загрузки**, прежде чем судить: заливка прошивки начинается примерно на 30-й секунде.

## Кексты

```bash
kmutil showloaded | grep -v com.apple          # реально загруженные сторонние кексты
ioreg -r -c <ИмяКласса> -w0 | head -5          # прицепился ли драйвер
```

В выводе `ioreg` пометка `!registered, !matched` у экземпляра драйвера означает, что он загрузился, но ни
к какому устройству не привязался. Это различие важно: «кекст загружен» и «драйвер чем-то управляет» — разные
утверждения.

## Монтирование EFI-раздела

```bash
ESP=$(diskutil list internal physical | awk '/EFI/{print $NF}' | head -1)
sudo mkdir -p /Volumes/ESP
sudo mount -t msdos /dev/$ESP /Volumes/ESP
```

**Не** пишите `disk0s1` жёстко. При вставленной загрузочной флешке нумерация дисков смещается, и вы молча
отредактируете не тот EFI-раздел — или вообще ничего. Вывод из `diskutil list internal physical` надёжен.

Если `mount` отвечает `Resource busy`, значит уже смонтировано; найдите куда:

```bash
mount | awk -v d="/dev/$ESP" '$1==d{print $3}'
```

## Правка config.plist из командной строки

`PlistBuddy` неудобен для массивов. Python лучше и доступен после установки Command Line Tools:

```bash
xcode-select --install     # без этого /usr/bin/python3 — заглушка
```

```python
import plistlib
c = plistlib.load(open('/Volumes/ESP/EFI/OC/config.plist','rb'))
for e in c['Kernel']['Add']:
    if e['BundlePath'] == 'itlwm.kext':
        e['Enabled'] = False
plistlib.dump(c, open('/Volumes/ESP/EFI/OC/config.plist','wb'))
```

Перед перезагрузкой всегда проверяйте результат через `plutil -lint`.

> **Если пишете скрипты для Mac с машины на Windows:** Python там в текстовом режиме ставит CRLF, и bash
> такой файл не исполняет. Симптомы обманчивы — `syntax error near unexpected token` на строке, с которой
> всё очевидно в порядке, и совпадающие контрольные суммы с обеих сторон, потому что файл был битым ещё до
> отправки. Выполняйте `sed -i 's/\r$//' script.sh && bash -n script.sh`, и проверяйте `bash -n` ещё раз
> уже на Mac.

## Демоны, которые не запускаются

```bash
sudo launchctl kickstart -p system/com.local.example
sudo launchctl print system/com.local.example | grep -E 'state|last exit'
cat /var/log/<ваш StandardErrorPath>
```

Две вещи, на которых спотыкаются:

- Используйте `launchctl bootstrap` и `bootout`, а не устаревшие `load` и `unload` — последние падают с
  бессодержательным `Load failed: 5`.
- Демон, запускающий **ваш собственный скрипт**, должен вызывать его через подписанный бинарник:
  `ProgramArguments = ["/bin/bash", "/usr/local/bin/ваш-скрипт.sh"]`. Прямая ссылка на скрипт может падать
  с `EX_CONFIG (78)`.

И проверяйте демон так, как его запустит система. Скрипт, прекрасно работающий под `sudo bash script.sh`,
может не работать под launchd по причинам, никак не связанным с его логикой.

## Восстановление

Держите флешку с заведомо рабочим OpenCore. Если правка внутреннего EFI оставила машину без загрузки или
без сети, нажмите **F12** при включении и загрузитесь с флешки.

Учтите: при вставленной флешке машина может грузиться *с неё* по умолчанию, и это молча замаскирует ваши
изменения на внутреннем EFI-разделе. Если правка будто бы ни на что не повлияла, проверьте, откуда вы на
самом деле загрузились:

```bash
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version
diskutil list external physical
```
