# rsg-telegram

Telegram system for RSG Framework (RedM). Send and receive telegrams at any post office, with an address book, a player directory search and an RDR2-styled NUI.

## Features
- Post offices with blips and a `[J]` prompt (configurable)
- Inbox with unread markers, read, reply, save sender and destroy
- Address book with nicknames (max contacts configurable)
- Recipient search by character name or citizen ID
- Optional send fee, per-player send cooldown and delivery delay
- Unread reminder on login
- Movable/resizable UI and adjustable message text size (remembered per player)
- Auto-creates and migrates its database tables (manual SQL in `installation/` still available)
- Locales: en, de, el, es, fr, ja, nl, pl, pt-br, ro

## Dependencies
- rsg-core
- ox_lib (locale loading only)
- oxmysql

## Installation
1. Drop `rsg-telegram` into your resources folder.
2. With `Config.AutoDatabase = true` the tables are created on start. Otherwise import `installation/rsg-telegram.sql`.
3. Add `ensure rsg-telegram` to your server.cfg after rsg-core.

See [DOCS.md](DOCS.md) for configuration and technical details.

## Support
https://buymeacoffee.com/rexshack
