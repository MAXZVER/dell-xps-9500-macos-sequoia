# Wi-Fi и Bluetooth

Карта — **Intel Wi-Fi 6 AX201**: `pci8086,6f0`, subsystem `1651`, на интерфейсе CNVi по адресу
`PciRoot(0x0)/Pci(0x14,0x3)`. Bluetooth — вторая половина того же модуля, подключена по USB как `8087:0026`.

## Wi-Fi

Wi-Fi работает на **`itlwm.kext` + [HeliPort](https://github.com/OpenIntelWireless/HeliPort)**. Стабильно,
и именно это в конфигурации.

`itlwm` показывает беспроводную карту системе как *Ethernet* и сам занимается подключением к сети, а
HeliPort — клиент в строке меню, который им управляет. Отсюда следствия:

- Сетевой сервис в настройках называется **Ethernet**, а не Wi-Fi. Это правильно, а не ошибка.
- HeliPort — обычное приложение, поэтому **сеть поднимается после входа в систему**, а не на экране входа.
- Службы геолокации по Wi-Fi не работают, автоматический часовой пояс по сети — тоже.
- Порталы авторизации (отели, аэропорты) сами не открываются — открывайте страницу входа вручную.

`scripts/com.heliport.autostart.plist` запускает HeliPort при входе и следит, чтобы он работал.

### Нативный AirportItlwm

Есть известный путь сделать Wi-Fi *настоящим* Wi-Fi для macOS: подсунуть системе понижённый сетевой стек
(`IOSkywalkFamily` и `IO80211FamilyLegacy` из более старой macOS), заблокировать системный
`IOSkywalkFamily` и загрузить `AirportItlwm.kext` поверх legacy-стека.

**На Sequoia одним инжектом кекстов это не работает.** Проверено здесь досконально, чтобы вам не пришлось.

Инжект отрабатывает полностью. Все три кекста грузятся без единой претензии AMFI, драйвер прикрепляется
(`CNVW@14,3/AirportItlwm/AirportItlwmInterface`), а `networksetup -listallhardwareports` показывает
настоящий `Hardware Port: Wi-Fi`. Выглядит правильно во всём.

А сетей ноль, и в меню Wi-Fi появляется бессмысленное сообщение про необходимость профиля 802.1X. В журнале
видно, почему именно:

```
IOCTL type 207/'APPLE80211_IOC_CHANNELS_INFO' return -3900     (≈160 раз за загрузку)
IOCTL type 11/'APPLE80211_IOC_SCAN_RESULT'    return -1
Apple80211Scan Failed, err[22]   scanResultsCount=0
```

Драйвер не сообщает системе список поддерживаемых каналов, поэтому macOS не может собрать запрос на
сканирование и получает `EINVAL`. Сканирование не падает — **оно вообще не начинается.** А сообщение про
802.1X — это то, что интерфейс показывает, когда драйвер не сказал ему, какие типы шифрования поддерживает.

Причина в том, что *пользовательская* часть стека Wi-Fi в Sequoia — `airportd` и CoreWLAN — новая,
скайвок-овая, и с legacy-драйвером разговаривать не умеет. Подмена кекстов — только половина работы; вторую
половину заменяет **root-патчинг OCLP**. Оба основных руководства говорят это прямым текстом:

- [5T33Z0/OCLP4Hackintosh — AirportItlwm на Sequoia](https://github.com/5T33Z0/OCLP4Hackintosh/blob/main/Enable_Features/AirportItllwm_Sequoia.md)
- [sap24601 — нативный Wi-Fi на macOS Sequoia](https://github.com/sap24601/Native-Wifi-for-Hackintoshes-with-Intel-Wireless-cards-on-macOS-sequoia)

Заодно объясняется деталь, которую вы встретите в других конфигурациях для XPS 9500 и захотите скопировать:

```xml
PciRoot(0x0)/Pci(0x14,0x3)
    IOName = pci14e4,43a0
```

Это выдаёт Intel-карту за Broadcom — **не** чтобы заработал драйвер, а чтобы OCLP согласился наложить свои
патчи для Broadcom. После патчинга запись положено убрать. Сама по себе она не даёт ничего — проверено.

### Стоит ли идти путём OCLP

Это реальный вариант, и он обратим: OCLP не правит запечатанный снимок системы, а создаёт рядом новый и
загружается с него. «Revert Root Patches» возвращает загрузку на исходный, а любое обновление macOS сносит
патчи само.

Цена тоже реальная:

- SIP придётся понизить до `csr-active-config = 03080000`.
- FileVault должен быть выключен.
- **Каждое обновление macOS сносит патчи и уносит с собой Wi-Fi** до повторного наложения.
- У AirportItlwm нет WPA3, а переподключение после пробуждения, по отзывам, ненадёжно — на машине, где сон
  дался тяжело, это существенный риск.

Взамен вы получаете нативное меню Wi-Fi, сеть на экране входа и геолокацию по Wi-Fi. Скорость **не**
вырастет — `itlwm` и `AirportItlwm` используют одно и то же ядро драйвера одной и той же версии. AirDrop,
Handoff и Continuity недостижимы в любом случае, потому что им нужно фирменное железо Apple.

Эта конфигурация остаётся на `itlwm` + HeliPort. Вы можете решить иначе — теперь у вас есть факты.

### Как убрать оставшийся значок Wi-Fi

Если вы поэкспериментируете с AirportItlwm и вернётесь обратно, macOS может сохранить сетевой сервис типа
`AirPort` и оставить в строке меню значок Wi-Fi с восклицательным знаком. Восстановите
`/Library/Preferences/SystemConfiguration/{preferences,NetworkInterfaces}.plist` из копии, снятой до
экспериментов, а если значок не ушёл:

```bash
defaults -currentHost write com.apple.controlcenter WiFi -int 8
defaults write com.apple.controlcenter 'NSStatusItem Visible WiFi' -bool false
killall -9 ControlCenter
```

Нужны оба ключа. Один `NSStatusItem Visible` ControlCenter перезаписывает при каждом запуске.

## Bluetooth

Bluetooth работает, включая аудиоустройства. Кексты: `IntelBluetoothFirmware`, `IntelBTPatcher`,
`BlueToolFixup`, плюс `-btlfxallowanyaddr` в boot-args и эти переменные NVRAM (уже в конфиге, и они
перечислены в `NVRAM → Delete`, поэтому сбрасываются каждую загрузку):

```
bluetoothExternalDongleFailed     <00>
bluetoothInternalControllerInfo   <0000000000000000000000000000>
```

### Единственная оговорка: он не переживает перезагрузку

Контроллер Intel инициализируется только при подаче питания с нуля. После `shutdown -r now` он поднимается
мёртвым и остаётся таким; после полного выключения и нажатия кнопки — работает.

**Как отличить одно от другого — смотрите на `Firmware Version`, а не на `State`:**

```
рабочий:              Address: XX:XX:XX:XX:XX:XX   State: On    Firmware: v256 c256
выключен тумблером:   Address: NULL                State: Off   Firmware: v256 c256
действительно мёртв:  Address: NULL                State: Off   Firmware: v0
```

`v256 c256` означает, что прошивка залилась и контроллер жив, а `Address: NULL` тогда — просто выключенный
Bluetooth. **Настоящая поломка — это `v0`.** В таком состоянии в журнале вообще нет строки
`IOUSBHostDevice@…: IntelBluetoothFirmware selected configuration 1` — заливка прошивки не начинается, —
а `ioreg -r -c IntelBluetoothFirmware` показывает `!registered, !matched`.

Ещё две вещи:

- **Сон не мешает.** Гибернация обесточивает машину, поэтому пробуждение равносильно холодному старту.
  Ломает Bluetooth только явная перезагрузка.
- Не торопитесь с выводами. После холодного старта прошивка заливается примерно на 30-й секунде аптайма, а
  `State: On` появляется ещё через полминуты-минуту. Ранний замер даёт ложное «сломалось» — так вышло
  дважды при разработке.

`Chipset: THIRD_PARTY_DONGLE` и `Vendor ID: 0x004C (Apple)` в сведениях о системе — это лишь то, как
BlueToolFixup представляет контроллер. Не неисправность.

### Если Bluetooth сломался после смены SMBIOS

Другая поломка с тем же симптомом. Смена серийников делает недействительным кэш настроек Bluetooth. Лечение:

```bash
sudo rm -f /Library/Preferences/com.apple.Bluetooth.plist
rm -f ~/Library/Preferences/ByHost/com.apple.Bluetooth.*.plist
sudo shutdown -h now      # полное выключение, а не перезагрузка
```
