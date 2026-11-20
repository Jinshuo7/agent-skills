# What the A1's local ports actually allow

Measured on serial `03919D4A2404396`, Bambu Lab A1, firmware 01.08.01.00, November 2026.
Read this before answering "can't you just send the job?".

## Ports

| Port | Service | Credential | Verdict |
|---|---|---|---|
| 990 | implicit FTPS | `bblp` + access code | **Full read/write of the SD card.** Upload and download 3MFs in `/cache` (the printer's own view of that path is `/sdcard/cache/`). Byte-verified. |
| 8883 | MQTT 3.1.1 over TLS | `bblp` + access code | **Telemetry and `info` commands.** Live state, temperatures, filament, AMS, errors. |
| 3000 | framed JSON | unknown | Replies `A5 A5` + little-endian total length + JSON. A `login_report` comes back, but no login shape ever succeeded. |
| 6000 | unknown | — | Open, silent to everything tried. |

## MQTT details worth not rediscovering

- The CONNECT flags must set the username and password bits (`0xC2`). Sending a clean-session-only `0x02` with credentials in the payload returns CONNACK 5 even though the access code is correct.
- Status: publish `{"pushing":{"sequence_id":"1","command":"pushall"}}`, then read `device/<serial>/report`.
- `{"info":{"sequence_id":"1","command":"get_version"}}` answers normally.

## The wall

Every command in the `print` namespace returns `err_code 84033543` (`0x05024007`), uniformly: `project_file`, `pause`, and even `get_version` sent to that namespace. Tested across:

- both URL forms — `ftp:///cache/<file>.3mf` and `ftp:///sdcard/cache/<file>.3mf`
- `ams_mapping` as `[]`, as 32 × 65280, as `""`, and omitted
- with and without `bed_type`, `cfg`, `file`, and every bed-levelling flag
- QoS 0 and QoS 1
- cloud mode **and** LAN-only mode, with a freshly rotated access code

The `info` namespace keeps working throughout, so the session is authenticated — the gate is on job submission, not on the connection.

**Conclusion: this firmware does not accept print jobs from a non-Bambu client.** Print from BambuStudio. A BambuStudio job descriptor left on the card (`1_<name>.bbl`) records the app's own field set, including `"file path": "/sdcard/cache/<name>.3mf"` and `md5` of the 3MF file — useful for confirming what the app sends, not for forging a request.

## Access code

Stored per serial in `~/Library/Application Support/BambuStudio/BambuStudio.conf` under `access_code`. It rotates whenever LAN-only mode is toggled, which silently invalidates anything cached. Never act on a promise that the code still works: reconnect and check CONNACK first.

## LAN-only mode

Switching it on severs the cloud link, so the Handy app and remote printing stop reaching the printer, and BambuStudio can only use the local path. It does **not** unlock `print` commands — that was the hypothesis, and it was tested and refuted here.
