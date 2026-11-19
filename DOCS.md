# rsg-telegram – Documentation

Technical reference for server owners and developers. For a short overview see [README.md](README.md).

## Contents
1. [Overview and file layout](#overview-and-file-layout)
2. [Installation and setup](#installation-and-setup)
3. [Configuration](#configuration-sharedconfiglua)
4. [Database](#database)
5. [Data formats](#data-formats)
6. [How it works](#how-it-works)
7. [Server callbacks and events](#server-callbacks-rsg-core)
8. [API for other resources](#api-for-other-resources)
9. [Integration examples](#examples)
10. [Security notes](#security-notes)
11. [Troubleshooting](#troubleshooting)
12. [Changelog](#changelog)

## Overview and file layout
| File | Purpose |
|---|---|
| `fxmanifest.lua` | Resource manifest. Dependencies: `rsg-core`, `rsg-inventory`, `oxmysql` |
| `shared/config.lua` | All settings (loaded on client and server) |
| `server/server.lua` | Schema setup, purge job, data layer (`TelegramInternal`), UI callbacks, attachments, job offices, access control |
| `server/api.lua` | Public server exports, built on the same data layer as the UI |
| `server/versionchecker.lua` | Checks the published version on start |
| `client/client.lua` | Prompts, blips, NUI focus + push-to-talk whitelist, NUI callbacks, remote-open event |
| `html/` | NUI: `index.html`, `style.css` (clipboard / old paper theme), `script.js` |
| `locales/*.json` | `en`, `de`, `el`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru` (identical keys) |
| `installation/rsg-telegram.sql` | Manual schema, identical to the auto-created tables |

Flow: the client opens the NUI (post office prompt, or the `OpenTelegrams` export) and every NUI action goes through an rsg-core callback. The server re-validates the player, the access grant, throttling and every argument before touching the database, so the UI is only a view.

## Installation and setup
1. Put `rsg-telegram` in your resources folder and `ensure rsg-telegram` after `rsg-core`, `rsg-inventory` and `oxmysql`.
2. Tables are created and migrated on start while `Config.AutoDatabase = true`. To install by hand set it to `false` and import `installation/rsg-telegram.sql`.
3. Pick the language in `server.cfg`: `setr rsg:locale "en"`.
4. Optional: add job offices (see below), tune `Config.Attachments`, `Config.Receipts` and the purge options.

Job offices (players can write to a whole job):
```lua
Config.JobAddresses = {
    { job = 'vallaw',   label = 'Valentine Sheriff Office' },
    { job = 'valmedic', label = 'Valentine Doctor' },
}
```
`job` must be a real job name. Members are found among online players (including secondary jobs, via `HasPlayerJob`) and offline characters through the `job` JSON column of the `players` table. If that column does not exist the feature is disabled and a warning is printed.

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
| `PurgeReadAfterDays` | `30` | Delete read telegrams older than this many days (0 = never). Runs on start and every 6 hours |
| `PurgeUnreadAfterDays` | `0` | Same for unread telegrams (0 = keep forever) |
| `MaxStoredPerPlayer` | `200` | Most telegrams one character can hold. The oldest are removed when a new one arrives beyond this (0 = unlimited) |
| `DirectorySearch` | `true` | Players can search every character by name when writing / adding contacts. `false` = address book only (fill it with `AddContact` from other scripts, or by replying) |
| `SearchByCitizenId` | `true` | Directory search also matches an exact citizen ID. Set `false` so players cannot look up IDs |
| `AllowPushToTalkWhileOpen` | `true` | Keep push-to-talk working while the UI is open (all other controls are blocked) |
| `PushToTalkControls` | `{ 0x4BC9DABB }` | Controls left enabled while the UI is open |
| `API.Enabled` | `true` | Master switch for the exports in the API section (they return `false` / empty when off) |
| `API.SystemSenderName` | `'Telegraph Office'` | Sender name used when a script sends without a character |
| `MaxSent` | `50` | Sent folder rows shown |
| `MaxBlocked` | `100` | Block list size per character |
| `Receipts.Enabled` | `true` | Sent folder shows Read / Read by X of Y. `false` hides read status |
| `Receipts.NotifyDelivered` / `NotifyRead` | `false` / `false` | Notify the sender when a telegram is delivered / read (never for `SYSTEM` telegrams) |
| `Attachments.Enabled` | `true` | Allow cash/item attachments |
| `Attachments.Fee` | `0.50` | Extra fee when a telegram carries an attachment |
| `Attachments.MaxCash` | `500` | Most cash per telegram (UI only, scripts are not capped) |
| `Attachments.MaxItems` / `MaxItemAmount` | `3` / `20` | Item kinds per telegram / amount of each |
| `Attachments.BlockedItems` / `AllowedItems` | money items / `{}` | Items that can never be attached / optional whitelist (empty = any normal item). Weapons and unique items are never attachable |
| `JobAddresses` | `{}` | List of `{ job = 'vallaw', label = 'Valentine Sheriff' }`. Players can write to the whole job (online members, secondary jobs and offline holders). Needs a `job` JSON column on `players`; disabled with a console warning if it is missing |
| `MaxJobRecipients` | `25` | Most recipients one office telegram is copied to |
| `API.AccessSeconds` | `900` | Default length of an `OpenTelegrams` remote-access grant |
| `PostOffices` | 8 towns | `name`, `coords`, `showblip` |
| `Blip` | `{ sprite = 1861010125, style = 1664425300 }` | Blip sprite and style used for post offices that have `showblip = true` |

## Database
Created automatically (or from `installation/rsg-telegram.sql`):
```sql
CREATE TABLE IF NOT EXISTS `rsg_telegrams` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,              -- recipient
    `recipient_name` VARCHAR(100) NOT NULL,
    `sender_citizenid` VARCHAR(50) NOT NULL,       -- 'SYSTEM' for script-sent telegrams
    `sender_name` VARCHAR(100) NOT NULL,
    `subject` VARCHAR(100) NOT NULL,
    `message` TEXT NOT NULL,
    `is_read` TINYINT(1) NOT NULL DEFAULT 0,
    `sent_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- future = still in transit
    `batch` VARCHAR(40) NULL DEFAULT NULL,         -- groups the copies of one office telegram
    `has_attachment` TINYINT(1) NOT NULL DEFAULT 0,
    `attachment` TEXT NULL DEFAULT NULL,           -- JSON {cash, items}, NULL once collected
    PRIMARY KEY (`id`), INDEX `idx_citizenid` (`citizenid`), INDEX `idx_sender` (`sender_citizenid`)
);
-- rsg_telegram_contacts: id, citizenid, contact_citizenid, contact_name, nickname, added_at  (UNIQUE citizenid + contact_citizenid)
-- rsg_telegram_blocks:   id, citizenid, blocked_citizenid, blocked_name, added_at           (UNIQUE citizenid + blocked_citizenid)
```
- `rsg_telegrams` – one row per telegram (`citizenid` = recipient). Delayed telegrams are stored straight away with a future `sent_at`; they stay hidden from the inbox until that time, so a paid telegram survives a server restart.
- `rsg_telegram_contacts` – address book, unique on (`citizenid`, `contact_citizenid`).
- `rsg_telegram_blocks` – block list, unique on (`citizenid`, `blocked_citizenid`).
- New `rsg_telegrams` columns: `batch` (groups the copies of one office telegram for the Sent folder), `has_attachment`, `attachment` (JSON `{cash, items}`, `NULL` once collected) and an `idx_sender` index. Existing tables are migrated automatically.

## Data formats
Inbox row (UI and `GetTelegrams`):
```lua
{
    id = 42, sender_citizenid = 'ABC12345', sender_name = 'John Marston',
    subject = 'Meet me', message = 'Behind the saloon at dusk.',
    is_read = 0, sent_at = 1760000000,            -- unix time
    has_attachment = 1,                            -- 1 once a parcel was attached (stays 1 after collecting)
    attachment = {                                 -- only present while something is uncollected
        cash = 25,
        items = { { name = 'bread', amount = 2, label = 'Bread' } },
    },
}
```
Sent row (`GetSentTelegrams`, one per send; an office send is one row):
```lua
{ id = 42, subject = '...', message = '...', recipient_name = 'Valentine Sheriff Office', sent_at = 1760000000,
  recipients = 3, delivered = 3, read_count = 1, has_attachment = 0, unclaimed = 0 }
```
`read_count` is `0` when `Config.Receipts.Enabled = false`. A row is *in transit* while `delivered = 0`.

Attachment (what you pass to `SendTelegram` and what is stored as JSON):
```lua
{ cash = 25.5, items = { { name = 'bread', amount = 2 }, { name = 'apple', amount = 1 } } }
```
Cash is rounded to cents. Items must exist in `RSGCore.Shared.Items`, appear once each, have a whole positive amount and not be unique items, weapons or in `BlockedItems`.

Contact: `{ citizenid, name, nickname }`. Blocked entry: `{ citizenid, name }`.

## How it works
- **Delivery:** every telegram is written to the database immediately with a `sent_at` in the future when a delay is used. It is hidden from the inbox until then, so a paid telegram survives a restart. `telegramDelivered` fires from a server timer when the delay elapses; if the server restarts first, the telegram simply appears once its time has passed, without the event.
- **Sending (UI):** cooldown, sanitise, resolve recipient or office, validate the attachment, claim the cooldown slot, resolve recipients, skip recipients who blocked the sender, take the fee (`SendCost` plus `Attachments.Fee` when there is a parcel), take the attachment, store one row per recipient, refund and roll back everything if any step fails.
- **Attachments:** escrowed on the telegram row. Collecting checks `CanAddItem`, claims with an atomic `UPDATE ... SET attachment = NULL WHERE attachment IS NOT NULL`, then pays out. Whatever does not fit is written back as the remaining attachment.
- **Access:** a player may use the UI when standing at a post office or when they hold an `OpenTelegrams` grant. The grant expires after `seconds` and is revoked when the UI closes or the player drops.
- **Housekeeping:** every 6 hours old read (and optionally unread) telegrams are purged; telegrams holding an uncollected attachment are never purged or trimmed. Each character keeps at most `MaxStoredPerPlayer` telegrams.
- **Throttles:** per player and action: search 500 ms, delete / collect / contacts / blocks / bulk actions 750 ms, list reads 400 ms; sending is limited by `Config.SendCooldown`.

## Server callbacks (rsg-core)
All validate the player and require the player to be at a post office.
| Name | Args | Returns |
|---|---|---|
| `rsg-telegram:server:getInbox` | – | inbox rows, or `false` if throttled (400 ms) |
| `rsg-telegram:server:searchRecipients` | `query` | results, or `false` if throttled (500 ms) |
| `rsg-telegram:server:send` | `{citizenid \| job, subject, message, attachment?}` | `boolean` (job must exist in `Config.JobAddresses`; no attachments to offices) |
| `rsg-telegram:server:getSent` | – | one row per send with `recipients`, `delivered`, `read_count`, `unclaimed` |
| `rsg-telegram:server:collect` | `id` | `{ ok, attachment? }` (attachment = leftover that did not fit) or `false` |
| `rsg-telegram:server:getAttachables` | – | `{ cash, items = {{name,label,amount}} }` |
| `rsg-telegram:server:markAllRead` / `deleteRead` | – | `boolean` (destroying skips telegrams with an uncollected attachment) |
| `rsg-telegram:server:getBlocked` | – | `{ {citizenid, name} }` |
| `rsg-telegram:server:block` / `unblock` | `citizenid` | `boolean` |
| `rsg-telegram:server:getContacts` | – | contacts, or `false` if throttled (400 ms) |
| `rsg-telegram:server:addContact` | `{citizenid, nickname?}` | `boolean` (throttled 750 ms) |
| `rsg-telegram:server:removeContact` | `citizenid` | `boolean` (throttled) |
| `rsg-telegram:server:delete` | `id` | `boolean` (throttled) |

Net event `rsg-telegram:server:markRead(id)` only marks the caller's own telegrams, requires a post office and is throttled (150 ms).
The UI treats a `false` from the throttled read callbacks as "keep what is shown".
Client event `rsg-telegram:client:newTelegram(senderName)` shows the arrival notification.
Client event `rsg-telegram:client:open(label, coords?, radius?)` opens the UI; it is only accepted from the server (used by `OpenTelegrams`).
Net event `rsg-telegram:server:closed` is sent by the client when the UI closes and revokes a remote-access grant.

## API for other resources
Server exports live in `server/api.lua`. Wherever a *citizen* argument is listed you can pass a **citizenid string** or an **online player's server id**. Telegram and contact data work for offline characters too, since they come from the database.

These calls are **server-side and trusted**: they skip the post office, fee and cooldown checks that apply to players in the UI. Subject/message are still sanitised and limited by `Config.MaxSubject` / `Config.MaxMessage`. Never forward client input into them without your own validation.

### Server exports
| Export | Returns | Notes |
|---|---|---|
| `SendTelegram(recipient, subject, message, opts?)` | `ok, idOrReason` | See options below |
| `GetTelegrams(citizen, opts?)` | rows | Newest first. `opts.unreadOnly`, `opts.limit` (default `MaxInbox`, max 200). Telegrams still in transit are not returned |
| `GetUnreadCount(citizen)` | `number` | Delivered, unread telegrams |
| `MarkRead(citizen, id?)` | `number` marked | Omit `id` to mark all as read |
| `DeleteTelegram(citizen, id)` | `ok, reason` | Only deletes delivered telegrams addressed to that citizen. `false, 'attachment'` while an attachment is uncollected |
| `DeleteReadTelegrams(citizen)` | `number` deleted | Read telegrams without an uncollected attachment |
| `GetSentTelegrams(citizen, opts?)` | rows | Sent folder (`opts.limit`, max 200) |
| `GetBlocked(citizen)` | `{ {citizenid, name} }` | |
| `IsBlocked(citizen, other)` | `boolean` | Whether `citizen` blocked `other` |
| `BlockCitizen(citizen, target)` | `ok, reason` | `true, 'added'/'already'` or `false` with `self`, `blocks_full`, `not_found` |
| `UnblockCitizen(citizen, target)` | `boolean` | |
| `OpenTelegrams(src, opts?)` | `boolean` | Opens the UI for an online player anywhere. `opts.label`, `opts.coords` + `opts.radius` (UI closes when the player leaves it), `opts.seconds` (grant length). The grant ends when the UI closes |
| `GetContacts(citizen)` | `{ {citizenid, name, nickname}, ... }` | Address book |
| `AddContact(citizen, contact, nickname?)` | `ok, reason` | `true, 'added'` / `true, 'updated'`, or `false` with `disabled`, `invalid`, `self`, `contacts_full`, `not_found` |
| `RemoveContact(citizen, contact)` | `boolean` | |

`SendTelegram` options (`opts` table, all optional):
| Option | Description |
|---|---|
| `sender` | Citizenid or server id of a real character to send as. Default: the system sender (stored as `SYSTEM`) |
| `senderName` | Display name. Default: the character's name, or `Config.API.SystemSenderName` |
| `delay` | Seconds before it arrives (default `0`) |
| `silent` | `true` = no "new telegram" toast for the recipient |
| `attachment` | `{ cash?, items? = {{name, amount}} }`. Created for the recipient, nothing is taken from anyone; items are validated against `RSGCore.Shared.Items`. Not capped by `Attachments.MaxCash` |

`SendTelegram` failure reasons: `disabled`, `invalid_recipient`, `invalid_subject`, `invalid_message`, `invalid_sender`, `recipient_not_found`, `invalid_attachment`, `blocked` (the recipient blocked that sender), `db_error`.

Inbox row: `{ id, sender_citizenid, sender_name, subject, message, is_read (0/1), has_attachment, attachment? = { cash?, items = {{name, amount, label}} }, sent_at (unix time) }`. Telegrams from `SYSTEM` can never be blocked.
Telegrams sent by a script have `sender_citizenid = 'SYSTEM'` (unless `opts.sender` is used); the UI hides Reply / Save Sender for them.

### Client exports
| Export | Returns | Notes |
|---|---|---|
| `IsOpen()` | `boolean` | Whether the telegram UI is open |
| `Close()` | – | Closes the UI if open |

The UI can be opened at a post office, or anywhere after a script calls `OpenTelegrams` (a time-limited grant that ends when the UI closes); the server enforces that for every UI callback.

### Server events
Local server events (listen with `AddEventHandler`, they are not net events). Payload: `{ id, recipient, recipientName, sender, senderName, subject, delay }`.
| Event | When |
|---|---|
| `rsg-telegram:server:telegramSent` | Telegram stored (UI or API), possibly still in transit |
| `rsg-telegram:server:telegramDelivered` | The delivery delay has elapsed and it is now in the inbox |

### Examples
```lua
-- notify a player's target by telegram from a job script
local ok, reason = exports['rsg-telegram']:SendTelegram(targetCitizenId, 'Rent Due', 'Your rent is due by Friday.', {
    senderName = 'Valentine Land Office',
})
if not ok then print(('telegram failed: %s'):format(reason)) end

-- reply as a real character, arriving in 60 seconds
exports['rsg-telegram']:SendTelegram(otherSrc, 'Meet me', 'Behind the saloon at dusk.', { sender = src, delay = 60 })

-- show unread count on login
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local n = exports['rsg-telegram']:GetUnreadCount(Player.PlayerData.source)
    if n > 0 then print(('%d unread telegrams'):format(n)) end
end)

-- react to deliveries
AddEventHandler('rsg-telegram:server:telegramDelivered', function(info)
    print(('telegram %d delivered to %s'):format(info.id, info.recipient))
end)
```

### More examples
```lua
-- 1) open the mailbox UI at a player's house for 10 minutes, closing if they walk more than 5 units away
exports['rsg-telegram']:OpenTelegrams(src, {
    label = 'Home Mailbox', coords = vector3(-300.0, 790.0, 118.0), radius = 5.0, seconds = 600,
})
-- without coords the UI stays open until the player closes it or the grant expires

-- 2) send a parcel (nothing is taken from anyone, the items are created for the recipient)
local ok, reason = exports['rsg-telegram']:SendTelegram(citizenid, 'Prize', 'Congratulations!', {
    senderName = 'Valentine Land Office',
    attachment = { cash = 100, items = { { name = 'bread', amount = 3 } } },
})
if not ok and reason == 'invalid_attachment' then print('bad item name or amount') end

-- 3) respect blocks before sending as a real character
if exports['rsg-telegram']:IsBlocked(targetCid, senderCid) then return end

-- 4) manage the block list from another script
exports['rsg-telegram']:BlockCitizen(src, otherCid)      -- true, 'added'
exports['rsg-telegram']:UnblockCitizen(src, otherCid)

-- 5) clean up a player's inbox
local removed = exports['rsg-telegram']:DeleteReadTelegrams(src)

-- 6) show what a player has sent
for _, row in ipairs(exports['rsg-telegram']:GetSentTelegrams(src, { limit = 10 })) do
    print(row.subject, row.recipient_name, row.delivered, row.read_count)
end

-- 7) client side: do not open another UI while the telegram UI is open
if exports['rsg-telegram']:IsOpen() then exports['rsg-telegram']:Close() end
```

## Security notes
- Fee is taken server-side only after all checks; refunded if the insert fails.
- Cooldown is claimed before any DB yield so parallel sends can't bypass it.
- Text is trimmed, length-checked and stripped of control characters and `<>`; the UI also escapes all output.
- Citizen IDs are pattern-validated; all queries are parameterised.
- Every UI action (read, delete, contacts, search, send) requires the player to be at a post office; the UI closes itself when the player moves away.
- Inbox, address book and mark-read requests are rate limited, so a modified client cannot hammer the database.
- A character can hold at most `MaxStoredPerPlayer` telegrams, so spamming someone cannot bloat the table or bury their inbox. Old telegrams are purged automatically.
- Text also has zero-width and bidirectional-override characters removed (stops spoofed sender/subject text).
- The directory search can expose citizen IDs of every character; use `DirectorySearch = false` or `SearchByCitizenId = false` if that matters on your server.
- Attachments are escrowed: cash and items are removed from the sender on send (rolled back if anything fails) and stored on the telegram. The recipient claims them with an atomic `UPDATE ... SET attachment = NULL`, so they cannot be duplicated by double-clicking or racing two requests. If the inventory cannot hold everything, the rest stays on the telegram. Telegrams with an uncollected attachment are never purged, trimmed or destroyed.
- Attachments need `rsg-inventory`; money items, weapons and unique items are not attachable.
- Job offices are resolved from `Config.JobAddresses` only; the client can never choose an arbitrary job.
- Blocked senders see a normal "sent" result; nothing is stored, charged or taken, so blocking cannot be probed.
- Remote access (`OpenTelegrams`) is a server-side, expiring grant per player, revoked when the UI closes or the player leaves.
- API exports are server-only (never reachable from clients); other scripts must validate any client-supplied data before passing it in. `Config.API.Enabled = false` disables them all.

## Troubleshooting
| Problem | Check |
|---|---|
| Tables are missing | `Config.AutoDatabase` must be `true`, or import `installation/rsg-telegram.sql`. Check the console for a red database error |
| "Config.JobAddresses is set but the players table has no job column" | Your `players` table has no `job` JSON column, so offices are disabled. Use the correct column or leave `JobAddresses` empty |
| Office telegram says nobody could be reached | No online or offline character holds that job, or everyone blocked the sender |
| Cannot attach an item | It is unique, a weapon, in `BlockedItems`, not in `AllowedItems` (when used) or missing from `RSGCore.Shared.Items` |
| Attachment cannot be collected | Not enough inventory space; the rest stays on the telegram. Free space and collect again |
| Telegram cannot be destroyed | It still holds an uncollected attachment |
| Nothing happens in the UI away from a post office | The server requires a post office or an `OpenTelegrams` grant for every action |
| Typewriter font missing | Special Elite loads from Google Fonts; offline clients fall back to Courier New |
| No push-to-talk while open | `Config.AllowPushToTalkWhileOpen` must be `true` and the control listed in `PushToTalkControls` |
| API exports return `false` | `Config.API.Enabled` is `false`, or an argument failed validation (see the failure reasons above) |

## Changelog
### 3.2.0
- Sent folder with delivery / read status and optional read-receipt notifications
- Mark all read and Destroy read
- Block list (UI + API), blocked senders are dropped silently
- Cash and item attachments (escrowed, atomic collect), `attachment` option for `SendTelegram`
- Telegrams to job offices (`Config.JobAddresses`)
- `OpenTelegrams` export to open the UI anywhere (houses, camps, mailboxes)
- Draft autosave, new API exports `GetSentTelegrams`, `DeleteReadTelegrams`, `GetBlocked`, `IsBlocked`, `BlockCitizen`, `UnblockCitizen`
- New table `rsg_telegram_blocks` and new `rsg_telegrams` columns (auto-migrated); `rsg-inventory` is now a dependency
- UI now fills 80% of the screen and is fixed (no move/resize)
- New look: a leather clipboard with a metal clip holding an aged paper sheet, typewriter font (Special Elite) for telegrams
- 50 new locale keys in all 11 languages

#### Audit and cleanup (part of 3.2.0)
- Push-to-talk now works while the UI is open (`Config.AllowPushToTalkWhileOpen`, `Config.PushToTalkControls`); NUI focus is handled in one place
- UI closes automatically if the player dies or is moved away from the post office (actions used to fail silently)
- Rate limits on inbox / address book loads and mark-read; mark-read, delete and remove-contact now require a post office like everything else
- Inbox cap per character (`MaxStoredPerPlayer`) and optional unread purge (`PurgeUnreadAfterDays`); purge now also runs every 6 hours instead of only on start
- `DirectorySearch` and `SearchByCitizenId` options to stop the directory exposing citizen IDs
- Zero-width / bidi-override characters stripped from telegram text
- Fee shown as `$0.50` instead of `$0.5` in the "cannot afford" message
- UI: Reply / Save Sender hidden for script-sent (`SYSTEM`) telegrams, throttled refreshes no longer blank the inbox, Ctrl+Enter sends, add-contact button disabled while it runs, date formatting can no longer break the list
- Cleanup: UI callbacks and the public API now share one data layer (removed ~60 lines of duplicated queries), removed redundant branches

#### API (part of 3.2.0)
- New API: server exports `SendTelegram`, `GetTelegrams`, `GetUnreadCount`, `MarkRead`, `DeleteTelegram`, `GetContacts`, `AddContact`, `RemoveContact`; client exports `IsOpen`, `Close`
- New server events `rsg-telegram:server:telegramSent` and `rsg-telegram:server:telegramDelivered`
- New `Config.API` (`Enabled`, `SystemSenderName`)
- UI sends and API sends now share one store/deliver function (`server/api.lua` added)

### 3.1.1
- Fully removed ox_lib: locales now load via `@rsg-core/shared/locale.lua`, `lib.locale()` calls dropped, NUI locale table from `locale()` (was `lib.getLocales()`)
- `ox_lib` removed from fxmanifest dependencies
- Set language with `setr rsg:locale "en"` in server.cfg

### 3.1.0
- Converted `lib.callback`, `lib.notify`, `ox_lib:notify` and `cache.ped` to rsg-core (ox_lib now only loads locales)
- Delayed telegrams are stored immediately (no longer lost on restart after paying)
- Proximity checks and rate limits on search, contacts and delete
- Send refunds the fee if the DB insert fails
- Prompt no longer opens while dead; NUI callbacks ignored when the UI is closed; open aborts cleanly on a callback timeout
- Throttled searches no longer show a false "No one by that name"
- Remove-contact button disabled while the request runs

## Support
https://buymeacoffee.com/rexshack

<!-- BEGIN AUTO-REFERENCE (generated from the code; re-run the generator instead of editing by hand) -->

## Technical reference

Generated from the source of **rsg-telegram 3.2.0**. Names, arguments and defaults below are read straight from the code.

### Dependencies

`rsg-core`, `rsg-inventory`, `oxmysql`

### Database

Tables: `rsg_telegrams`, `rsg_telegram_contacts`, `rsg_telegram_blocks`.

Tables are created automatically on start while `Config.AutoDatabase = true` (default). Nothing is ever dropped or overwritten.
For a manual install set `Config.AutoDatabase = false` and import `installation/rsg-telegram.sql` once.

```lua
-- shared/config.lua
Config.AutoDatabase = true -- false = import the SQL file yourself
```

### Configuration

| Option | Default | Notes |
|---|---|---|
| `Config.Debug` | `false` |  |
| `Config.AutoDatabase` | `true` | create / update the rsg_telegrams tables automatically on start |
| `Config.PromptKey` | `0xF3830D8E` | [J] |
| `Config.PromptDistance` | `2.0` |  |
| `Config.SendCost` | `0.50` | cash cost to send a telegram (0 = free) |
| `Config.MoneyType` | `'cash'` |  |
| `Config.MaxSubject` | `50` |  |
| `Config.MaxMessage` | `1000` |  |
| `Config.MaxInbox` | `50` | max telegrams returned in the inbox |
| `Config.SendCooldown` | `30` | seconds between telegrams per player |
| `Config.DeliveryDelay` | `0` | seconds before the telegram arrives (0 = instant) |
| `Config.SearchMinChars` | `2` |  |
| `Config.MaxContacts` | `50` | max entries in a player's address book |
| `Config.PurgeReadAfterDays` | `30` | delete READ telegrams older than this days (0 = keep forever); runs on start and every 6 hours |
| `Config.PurgeUnreadAfterDays` | `0` | delete UNREAD telegrams older than this many days (0 = keep forever) |
| `Config.MaxStoredPerPlayer` | `200` | most telegrams one character can hold; oldest are removed beyond this (0 = unlimited) |
| `Config.DirectorySearch` | `true` | let players search all characters by name when writing / adding contacts |
| `Config.SearchByCitizenId` | `true` | directory search also matches an exact citizen ID (set false to avoid exposing IDs) |
| `Config.AllowPushToTalkWhileOpen` | `true` | The telegram UI keeps game input so voice keeps working; all other controls are blocked while it is open |
| `Config.PushToTalkControls` | `table` |  |
| `Config.API` | `table` |  |
| `Config.Enabled` | `true` |  |
| `Config.SystemSenderName` | `'Telegraph Office'` |  |
| `Config.AccessSeconds` | `900` |  |
| `Config.MaxSent` | `50` | sent telegrams listed in the Sent tab |
| `Config.MaxBlocked` | `100` | block list size per character |
| `Config.Receipts` | `table` |  |
| `Config.NotifyDelivered` | `false` |  |
| `Config.NotifyRead` | `false` |  |
| `Config.Attachments` | `table` |  |
| `Config.Fee` | `0.50` |  |
| `Config.MaxCash` | `500` |  |
| `Config.MaxItems` | `3` |  |
| `Config.MaxItemAmount` | `20` |  |
| `Config.BlockedItems` | `{ 'dollar', 'cent', 'blood_dollar', 'blood_cent' }` | unique items (items with their own data) and weapons can never be attached; these are blocked on top of that |
| `Config.AllowedItems` | `{}` |  |
| `Config.JobAddresses` | `table` |  |
| `Config.MaxJobRecipients` | `25` |  |
| `Config.PostOffices` | `table` |  |
| `Config.Blip` | `table` |  |

### Exports

**Server**

| Export | Arguments | File |
|---|---|---|
| `SendTelegram` | `recipient, subject, message, opts` | `server/api.lua` |
| `GetTelegrams` | `citizen, opts` | `server/api.lua` |
| `GetSentTelegrams` | `citizen, limit` | `server/api.lua` |
| `GetUnreadCount` | `citizen` | `server/api.lua` |
| `MarkRead` | `citizen, id` | `server/api.lua` |
| `DeleteTelegram` | `citizen, id` | `server/api.lua` |
| `DeleteReadTelegrams` | `citizen` | `server/api.lua` |
| `GetContacts` | `citizen` | `server/api.lua` |
| `AddContact` | `citizen, contact, nickname` | `server/api.lua` |
| `RemoveContact` | `citizen, contact` | `server/api.lua` |
| `GetBlocked` | `citizen` | `server/api.lua` |
| `IsBlocked` | `citizen, sender` | `server/api.lua` |
| `BlockCitizen` | `citizen, target` | `server/api.lua` |
| `UnblockCitizen` | `citizen, target` | `server/api.lua` |
| `OpenTelegrams` | `src, opts` | `server/api.lua` |

**Client**

| Export | Arguments | File |
|---|---|---|
| `IsOpen` | `` | `client/client.lua` |
| `Close` | `` | `client/client.lua` |

```lua
-- example
local result = exports['rsg-telegram']:SendTelegram(recipient, subject, message, opts)
```

### Callbacks

| Callback | Side | Arguments | File |
|---|---|---|---|
| `rsg-telegram:server:getInbox` | server | `source, cb` | `server/server.lua` |
| `rsg-telegram:server:getSent` | server | `source, cb` | `server/server.lua` |
| `rsg-telegram:server:searchRecipients` | server | `source, cb, query` | `server/server.lua` |
| `rsg-telegram:server:getAttachables` | server | `source, cb` | `server/server.lua` |
| `rsg-telegram:server:send` | server | `source, cb, data` | `server/server.lua` |
| `rsg-telegram:server:collect` | server | `source, cb, id` | `server/server.lua` |
| `rsg-telegram:server:getContacts` | server | `source, cb` | `server/server.lua` |
| `rsg-telegram:server:addContact` | server | `source, cb, data` | `server/server.lua` |
| `rsg-telegram:server:removeContact` | server | `source, cb, citizenid` | `server/server.lua` |
| `rsg-telegram:server:getBlocked` | server | `source, cb` | `server/server.lua` |
| `rsg-telegram:server:block` | server | `source, cb, citizenid` | `server/server.lua` |
| `rsg-telegram:server:unblock` | server | `source, cb, citizenid` | `server/server.lua` |
| `rsg-telegram:server:delete` | server | `source, cb, id` | `server/server.lua` |
| `rsg-telegram:server:markAllRead` | server | `source, cb` | `server/server.lua` |
| `rsg-telegram:server:deleteRead` | server | `source, cb` | `server/server.lua` |

```lua
-- client side
RSGCore.Functions.TriggerCallback('rsg-telegram:server:getInbox', function(result)
    -- use result
end)
```

### Events

Server events can be fired by any client, so every handler re-validates the player, the arguments and any permission, distance or cooldown on the server. Never add a reward to a handler without those checks.

| Event | Side | Arguments | File |
|---|---|---|---|
| `rsg-telegram:client:open` | client | `label, coords, radius` | `client/client.lua` |
| `rsg-telegram:client:newTelegram` | client | `senderName` | `client/client.lua` |
| `rsg-telegram:server:markRead` | server | `id` | `server/server.lua` |
| `rsg-telegram:server:closed` | server | `` | `server/server.lua` |

```lua
-- from a client script
TriggerServerEvent('rsg-telegram:server:markRead', id)
-- from a server script
TriggerClientEvent('rsg-telegram:client:open', source, label, coords, radius)
```

### Locales

Language files in `locales/`: `de`, `el`, `en`, `es`, `fr`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru`. Set the language with `setr rsg:locale "en"`.

<!-- END AUTO-REFERENCE -->
