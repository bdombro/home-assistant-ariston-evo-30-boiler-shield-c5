# AGENTS.md

Ariston Clas HE System EVO 30 boiler <-> Shield C5 adapter <-> ebusd (HA app) <-> MQTT <-> Home Assistant.
Real boiler, real writes. Read `README.md` first; register facts in `docs/register-map.md`.

## Layout
- `ebusd/ariston.csv` boiler-only ebusd config (GPL-3.0, derived; keep header notice). Live copy: HA `/share/ebusd/`.
- `home-assistant/packages/boiler_ebus.yaml` controls + automations. Live: HA `/config/packages/`.
- `home-assistant/packages/boiler_helpers.yaml` optional YAML helpers. `dashboard-heating.yaml` dashboard export.
- `justfile` all common tasks (`just`); `scripts/lint.py` guards the CSV/YAML.

## Workflow
- Edit here, `just lint`, `just deploy`, then `just errors` / `just status`. `just pull` to sync from live.
- Env via `.env` (gitignored, copy `.env.example`) or shell: `HA_URL`, `HA_SSH`, `EBUSD_APP`, `HA_TOKEN`. All required, no fallbacks (even `just` errors without them). Shell wins over `.env`. Never write secrets/IPs/MACs into tracked files.
- Don't commit/push/publish unless asked. Keep README + `docs/register-map.md` in sync with what's verified.

## Hard rules (boiler safety)
- Writes: only `set_ch_setpoint` (6571), `set_heating_enabled` (0120), `set_dhw_enabled` (0220). `lint` fails otherwise.
- Never send/poll `2034` (bus reset) or `203b`. Never write `6197` (computed setpoint, read-only).
- Flash wear: write on user action or a few scheduled changes/day. No loops, no fast automations, skip no-op writes.
- New write/register: add as read probe first, test alone with a human at the boiler, read back, restore, then document as verified.
- Leave the boiler normal after tests: heating on, hot water on, setpoint restored.
- Don't add SSH keys / open ports on HA unless the user explicitly asks.

## Pitfalls
- Slider range (45-60) lives in 3 places: package `number` min/max, schedule automation guard, `input_number` helpers.
- ebusd only publishes when asked -> entities are `unknown` after any restart/MQTT reload (switches show lightning bolts that *write* when tapped). Keep `Boiler: refresh state`.
- `mqtt.reload` resets MQTT entity states; new package files/helpers need a full HA restart; run `ha core check` first.
- Schedule automation must stay `mode: restart` with the target computed *after* the 5 s delay (stale writes otherwise).
- UI helpers vs YAML helpers with the same ids clash; `just deploy` intentionally skips `boiler_helpers.yaml`.
- HA REST can't manage apps. Use `ssh ha 'ha apps ...'` (apps = add-ons) or the websocket `supervisor/api`.
- CSV: misaligned commas silently shift fields. Reads use `IGN:1` (status byte) + a field named `value`; templates rely on `value_json.value.value`.
- Log noise that is fine: `unknown BC cmd: 37fe2000...`, `ebus_reset ... invalid position`, 1-3 `SYN received` after a write, error `236` (outdoor probe missing).
- `circulating` = burner waiting out the 3 min ignition delay, not a fault.
- Dashboard URL path needs a hyphen. Entity ids assume area `Heating` (`sensor.heating_ebusd_boiler_*`).
- Left +/- (DHW) do nothing on this boiler; `1919` effect is unverified (needs `TA` unlinked).
