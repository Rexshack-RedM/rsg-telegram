# Changelog

All notable changes to rsg-telegram. Newest first.

## 3.3.0

### Added
- Unread badge (`Config.UnreadBadge`, client export `GetUnreadCount`), inbox search and "Load more" paging (`Config.InboxPageSize`)
- Anonymous telegrams (`Config.Anonymous`): hidden sender, blockable through the telegram id, never reveals the citizen id to the client
- `/notice` for jobs (`Config.Notices`) and `/telegrambroadcast <online|all> <minutes> <subject | message>` for admins (scheduled via delivery time)
- Admin-placed mailboxes (`Config.Mailbox`, `/addmailbox`, rsg-gizmo + rsg-target); new dependencies `rsg-target`, `rsg-gizmo`
- Delivery time by distance (`Config.DeliveryDistance`), optional `rsg-economy` fees (`Config.Economy`, post office `region`) and `rsg-reputation` standing (`Config.Reputation`)
- Directory opt-out per character (Address Book), `Config.ShowCitizenIds`

### Changed
- Blocked senders get a hidden copy (charged, shown as delivered) so blocking cannot be probed
- Job offices also reach offline characters who hold the job as a secondary multi-job (`player_jobs`)
- The inbox cap now trims read telegrams before unread ones
- Telegrams, contacts and blocks of deleted characters are purged (`Config.PurgeDeletedCharacters`)
- New columns `anonymous`, `silenced`, `kind`, new tables `rsg_telegram_settings`, `rsg_telegram_mailboxes` (all auto-migrated)
- 27 new locale keys in all 11 languages

## 3.2.1

### Fixed / hardened
- Attachments: stacks of a decaying item with quality below 100 can no longer be attached (it would have come out fresh on the other side)
- The UI no longer opens empty when the server refuses access (inbox callback answers `false`)
- Drafts are stored per character; another character on the same PC never sees your draft or its recipient
- Text cleaning also removes U+2028/2029, U+FEFF and C1 control characters
- Directory search cuts long queries on a character boundary (no broken UTF-8)

### Performance
- New `idx_inbox (citizenid, sent_at)` index on `rsg_telegrams` (added automatically; also in `installation/rsg-telegram.sql`)
- Expired send cooldowns are pruned every 6 hours

### Cleanup
- Removed leftover resize/drag CSS and the unused `ui_resize` locale key (all 11 languages)

## 3.2.0

### Documentation
- `DOCS.md`: added a generated technical reference (dependencies, database, configuration, exports, callbacks, events, commands, items, locales) with code examples, read straight from the source.
