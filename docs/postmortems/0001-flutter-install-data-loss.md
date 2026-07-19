# 0001. `flutter install` wiped unsynced device data (debug build reinstall)

- **Date**: 2026-07-18
- **Status**: resolved
- **Severity**: high
- **Services involved**: frontend (Android debug device)

## Symptom

During phase-6 (background-capture) device validation, installing the session-B build with
`flutter install` printed "Uninstalling old version..." and replaced the app instead of updating
it. All local app data was wiped — including ~2 months of transactions that had never been
synced to the server.

## Root cause

`flutter install` falls back to uninstall + install when the installed APK's signature differs
from the new build. Uninstalling wipes `/data/user/0/app.pocketpilot.debug`, and the device was
the only holder of the unsynced rows. The dump script's full-DB temp copy from earlier that day
was already gone: `scripts/dump_captured_notifications.sh` used `mktemp` + `trap 'rm -f' EXIT`,
so the copy was deleted the moment the script finished. No APFS local snapshots existed on the
host.

## Fix

Not recoverable. 325 raw captured notifications survived in
`frontend/test_data/captured_raw.json` (the dump had run ~1h before the wipe). The user chose to
restart from the last server sync rather than rebuild transactions from the raw notifications.

## Prevention

- Rule (runbook + this file): on a device holding unsynced data, always update with
  `adb install -r <apk>` — never `flutter install`.
- `scripts/dump_captured_notifications.sh` now keeps a permanent timestamped DB backup
  (including the `-wal`/`-shm` sidecars) under `~/.pocket_pilot/db_backups` instead of deleting
  its temp copy on exit.
- Longer-term [INFERRED]: background sync (explicitly deferred by phase 6 / ADR 0005) would
  bound the blast radius of any future device data loss.
