# rsg-telegram – Documentation

## Configuration (`shared/config.lua`)
| Option | Default | Description |
|---|---|---|
| `Debug` | `false` | Extra console output |
| `AutoDatabase` | `true` | Create/update tables on start, renames legacy `rex_telegrams` / `telegrams` tables |
| `PromptKey` | `0xF3830D8E` | Prompt key (J) |
| `PromptDistance` | `2.0` | Prompt range from a post office |
| `SendCost` | `0.50` | Fee per telegram (0 = free) |
| `MoneyType` | `'cash'` | Money type charged |
| `MaxSubject` / `MaxMessage` | `50` / `1000` | Character limits |
| `MaxInbox` | `50` | Telegrams shown in the inbox |
| `SendCooldown` | `30` | Seconds between sends per character |
| `DeliveryDelay` | `0` | Seconds before a telegram arrives |
| `SearchMinChars` | `2` | Minimum characters for a directory search |
| `MaxContacts` | `50` | Address book size |
| `PurgeReadAfterDays` | `30` | Delete read telegrams older than this on start (0 = never) |
| `PostOffices` | 8 towns | `name`, `coords`, `showblip` |

## Database
- `rsg_telegrams` – one row per telegram (`citizenid` = recipient). Delayed telegrams are stored straight away with a future `sent_at`; they stay hidden from the inbox until that time, so a paid telegram survives a server restart.
- `rsg_telegram_contacts` – address book, unique on (`citizenid`, `contact_citizenid`).

## Server callbacks (rsg-core)
All validate the player, and every one except remove/delete requires the player to be at a post office.
| Name | Args | Returns |
|---|---|---|
| `rsg-telegram:server:getInbox` | – | inbox rows |
| `rsg-telegram:server:searchRecipients` | `query` | results, or `false` if throttled (500 ms) |
| `rsg-telegram:server:send` | `{citizenid, subject, message}` | `boolean` |
| `rsg-telegram:server:getContacts` | – | contacts |
| `rsg-telegram:server:addContact` | `{citizenid, nickname?}` | `boolean` (throttled 750 ms) |
| `rsg-telegram:server:removeContact` | `citizenid` | `boolean` (throttled) |
| `rsg-telegram:server:delete` | `id` | `boolean` (throttled) |

Net event `rsg-telegram:server:markRead(id)` only marks the caller's own telegrams.
Client event `rsg-telegram:client:newTelegram(senderName)` shows the arrival notification.

## Security notes
- Fee is taken server-side only after all checks; refunded if the insert fails.
- Cooldown is claimed before any DB yield so parallel sends can't bypass it.
- Text is trimmed, length-checked and stripped of control characters and `<>`; the UI also escapes all output.
- Citizen IDs are pattern-validated; all queries are parameterised.

## Changelog
### 3.1.0
- Converted `lib.callback`, `lib.notify`, `ox_lib:notify` and `cache.ped` to rsg-core (ox_lib now only loads locales)
- Delayed telegrams are stored immediately (no longer lost on restart after paying)
- Proximity checks and rate limits on search, contacts and delete
- Send refunds the fee if the DB insert fails
- Prompt no longer opens while dead; NUI callbacks ignored when the UI is closed; open aborts cleanly on a callback timeout
- Throttled searches no longer show a false "No one by that name"
- Remove-contact button disabled while the request runs
