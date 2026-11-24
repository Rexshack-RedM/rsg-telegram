# rsg-telegram

Telegram system for RSG Framework (RedM). Send and receive telegrams at any post office, with an address book, a player directory search and an RDR2-styled NUI.

## Features
- Post offices with blips and a `[J]` prompt (configurable)
- Inbox with unread markers, read, reply, save sender and destroy, plus **Mark all read** and **Destroy read**
- **Sent folder** with delivery status: In transit, Delivered, Read / Read by X of Y (read receipts, optional toasts)
- **Block list**: block a sender from the telegram; their telegrams never reach you and they cannot tell (it still looks sent and delivered to them)
- **Attachments**: attach cash and items (taken from the sender on send, collected by the recipient from the telegram)
- **Job offices**: address a telegram to a whole job (e.g. the sheriff's office) via `Config.JobAddresses`
- **Remote mailbox**: other scripts can open the telegram UI anywhere (house, camp, mailbox) with `OpenTelegrams`
- **Draft autosave**: an unsent telegram is restored the next time you write (kept per character)
- **Unread badge**: an on-screen envelope with your unread count (corner configurable, `GetUnreadCount` export for HUDs)
- **Inbox search and paging**: search subject, sender and text; "Load more" for older telegrams
- **Anonymous telegrams** (small extra fee): the recipient sees "Anonymous", can block but not reply
- **Notices and bulletins**: `/notice` (law jobs) to everyone online, `/telegrambroadcast` (admin) to everyone online or every character, optionally scheduled
- **Mailboxes**: `/addmailbox` places a mailbox prop (rsg-gizmo) that opens the telegram UI (rsg-target)
- Optional delivery time by distance, `rsg-economy` fees (tax into the town treasury) and `rsg-reputation` standing
- **Directory privacy**: each character can hide from the player directory; citizen IDs can be hidden in the UI
- Address book with nicknames (max contacts configurable)
- Recipient search by character name or citizen ID
- Optional send fee, per-player send cooldown and delivery delay
- Unread reminder on login
- Push-to-talk keeps working while the UI is open (rsg-voice), all other controls are blocked
- UI closes automatically if you die or get moved away from the post office
- Inbox protection: per-character storage cap, automatic purge of old telegrams, rate-limited requests
- Optional: turn off the player directory / citizen ID search so IDs are not exposed
- Clipboard-and-old-paper look (typewriter font), UI fills 80% of the screen (fixed, not movable) with adjustable message text size (remembered per player)
- Server API (exports + events) so other RSG scripts can send telegrams, read inboxes and manage contacts
- Auto-creates and migrates its database tables (manual SQL in `installation/` still available)
- Locales: en, de, el, es, fr, ja, nl, pl, pt-br, ro, ru

## Dependencies
- rsg-core
- rsg-inventory (attachments)
- rsg-target and rsg-gizmo (mailboxes)
- oxmysql
- Optional: rsg-economy, rsg-reputation (`Config.Economy`, `Config.Reputation`)

## Installation
1. Drop `rsg-telegram` into your resources folder.
2. With `Config.AutoDatabase = true` the tables are created on start. Otherwise import `installation/rsg-telegram.sql`.
3. Add `ensure rsg-telegram` to your server.cfg after rsg-core.

## Developer API
Other resources can use telegrams from the server side:
```lua
-- send a telegram from a script (offline characters work too)
local ok, idOrReason = exports['rsg-telegram']:SendTelegram(citizenid, 'Bounty posted', 'A bounty has been placed on you.', {
    senderName = 'Sheriff Department', -- optional, defaults to Config.API.SystemSenderName
    delay = 0,                         -- optional seconds
})

local unread = exports['rsg-telegram']:GetUnreadCount(src) -- citizenid or server id
```
Exports: `SendTelegram` (supports `attachment`), `GetTelegrams`, `GetSentTelegrams`, `GetUnreadCount`, `MarkRead`, `DeleteTelegram`, `DeleteReadTelegrams`, `GetContacts`, `AddContact`, `RemoveContact`, `GetBlocked`, `IsBlocked`, `BlockCitizen`, `UnblockCitizen`, `OpenTelegrams` (server) and `IsOpen`, `Close` (client). Events: `rsg-telegram:server:telegramSent` and `rsg-telegram:server:telegramDelivered`.
Telegrams sent without a character use the sender id `SYSTEM` (the UI hides Reply / Save Sender for them). Set `Config.API.Enabled = false` to turn the API off. Full reference in [DOCS.md](DOCS.md).

```lua
-- open the telegram UI for a player at their house / mailbox for 15 minutes, closing if they walk 5 m away
exports['rsg-telegram']:OpenTelegrams(src, { label = 'Home Mailbox', coords = vector3(x, y, z), radius = 5.0 })

-- send a parcel from a script
exports['rsg-telegram']:SendTelegram(citizenid, 'Delivery', 'Your order has arrived.', {
    attachment = { cash = 25, items = { { name = 'bread', amount = 2 } } },
})
```
Job offices, attachments, receipts, notices, mailboxes, anonymous telegrams, the badge and the economy / reputation hooks are configured in `shared/config.lua` (`Config.JobAddresses`, `Config.Attachments`, `Config.Receipts`, `Config.Notices`, `Config.Mailbox`, `Config.Anonymous`, `Config.UnreadBadge`, `Config.Economy`, `Config.Reputation`).

### Commands
| Command | Who | What |
|---|---|---|
| `/notice <subject \| message>` | jobs in `Config.Notices.Jobs`, on duty | Official notice to everyone online |
| `/telegrambroadcast <online\|all> <minutes> <subject \| message>` | admin / console | Telegram to everyone online or every character, `minutes` > 0 schedules it |
| `/addmailbox` | admin | Place a mailbox (target it as an admin to remove it) |

See [DOCS.md](DOCS.md) for configuration and technical details.

## Support
https://buymeacoffee.com/rexshack
