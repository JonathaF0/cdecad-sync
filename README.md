# cde-cad-sync
https://cdecad.com
Multi-framework CDECAD **sync** resource. Auto-detects **ESX**, **QBCore**, **QBox**, **NAT2k15**, or **vRP** and loads the matching adapter at runtime, replacing the older per-framework `cde-cad-{esx,qbcore,qbox-release,nat2k15,vrp}` resources with a single drop-in.

ND_Framework is the offical framework of CDE CAD, which integrates natively and can be found at this link: https://shop.nightz.dev/products/nd-framework

Its one job is to keep framework characters + vehicles in sync with the CAD. Everything else, 911/dispatch, panic, ALPR, the tablet, civilian tools - lives in the **CDECAD** resource. Run CDECAD for the CAD features and add this alongside it purely for framework syncing.

## Features

- **Framework auto-detection** - picks the right adapter on resource start, no manual config required
- **Character sync** - synced on create / load / update / delete (identity + Discord ID)
- **Vehicle sync** - owned vehicles synced alongside the character
- **Admin commands** - manual sync, bulk DB sync, lookups

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- One of: ESX Legacy, QBCore, QBox (`qbx_core`), NAT2k15, or vRP
- [oxmysql](https://github.com/overextended/oxmysql) (required when bulk-syncing from the DB)

## Installation

1. Drop `cde-cad-sync` into your `resources/` folder
2. Configure credentials via server.cfg convars (see Configuration below)
3. Add `ensure cde-cad-sync` to your `server.cfg` (**after** your framework resource and `ox_lib`)
4. Restart your server

> **Do not** run a per-framework resource (`cde-cad-esx`, `cde-cad-qbcore`, etc.) alongside this one - both react to the same framework events and double-sync.

## Configuration

Two things to configure: the **framework** (usually auto-detected) and **what to sync**. Everything else has sensible defaults.

### Credentials (server.cfg convars)

Secrets are never stored in resource files - they come from convars:

```
##CDECAD
set CDE_CAD_API_URL "https://your-cdecad-instance.com"
set CDE_CAD_API_KEY "your-fivem-api-key"
set CDE_CAD_COMMUNITY_ID "your-discord-guild-id"
```

### Framework override

Auto-detection is preferred, but you can force a specific adapter:

```
set CDE_CAD_FRAMEWORK "esx"   # or "qbcore", "qbox", "nat2k15", "vrp"
```

### What to sync

Edit `Config.Sync` in `shared/config.lua` to toggle character load/create/update/delete and vehicle syncing. The per-framework blocks (`Config.ESX`, `Config.NAT2k15`, `Config.vRP`, …) hold the schema/field plumbing each framework needs - leave them unless your server uses a customized schema.

## Commands (Admin)

| Command | Description |
|---|---|
| `/cadsync [playerid]` | Force-sync a player |
| `/cadstatus` | CAD API health check |
| `/cadlookup [id/plate]` | Lookup civilian or vehicle |

All admin commands are ACE-gated (`command.<name>`).

## Notes

- The adapter loaded at boot is logged to the console: `[CDECAD-SYNC] Adapter ready: <name>`.
- See [`../CONFIGURING.md`](../CONFIGURING.md) for the full convar reference.
