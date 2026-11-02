# How this was figured out (and how to redo it for your boiler)

This is the method that took an Ariston boiler from "ebusd can't see anything useful" to a verified write path in one
weekend. It is written so you can repeat it on another BridgeNet boiler. Do it with someone standing at the boiler for the
write steps.

## 0. Why the defaults don't work

Ariston-group boilers speak **BridgeNet / "eBUS2"**, a non-standard eBUS dialect. ebusd's device auto-detection fails,
and the stock configuration files describe other manufacturers, so out of the box you only get ebusd's own status
entities. You need a custom CSV (ebusd's message definitions) and a bus adapter that tolerates the Ariston bus levels.

## 1. Listen first

Run ebusd with the bare minimum and read the log. Lines look like:

```
[update notice] received unknown BC cmd: 37fe2010 04 d1 40 00 00
                                          │ │ └ PBSB 2010  └ length + data
                                          │ └ ZZ fe (broadcast)
                                          └ QQ 37 (source)
```

Group them by source, command and length. On a boiler-only system there was **one** talker (`0x37`, the boiler; the
matching listening/slave address is master + 5 = `0x3c`) and three message shapes:

| PBSB | Shape | Meaning |
|---|---|---|
| `2000` + 2-byte ID | no data | the boiler asking for a value nobody answers (~70 % of traffic) |
| `2010` | list of `[ID][value]` | value broadcasts (status, setpoint, heat request) - real data |
| `2034`, `203b`, `2004` | housekeeping / errors | reset, address announce, error code |

## 2. Start from a close CSV and trim it

Take the nearest community file ([references](#references)) and delete everything for devices you don't have. On this
boiler that removed energy-manager, heat-pump, gateway and Sensys lines (172 -> 68 definitions) and fixed two problems:

- Dead polls (to devices that don't exist) time out every cycle and delay the useful ones.
- Every dead definition creates a permanently-"unknown" Home Assistant entity.

Also check the *source address* filters: the community `heat_request` broadcast line only accepted messages from the
energy manager (`QQ 13`), so it never matched this boiler (`QQ 37`).

## 3. Change one thing on the panel, watch what moves

With a decoder for the `2010` broadcasts in place, press one front-panel button and see which value changes:

| Panel action | What moved |
|---|---|
| Right +/- (setpoint 59 -> 60) | only register `6197` (`ch_setpoint_temp`) |
| Left +/- (DHW) | nothing - no cylinder sensor, so the boiler doesn't manage hot water |
| Tap/radiator button to summer mode | `boiler_status` -> `standby`, `heat_request` -> `off` |
| Any of the above | `d140` (settings counter) +1 |

That's how `6197`, `0191`, `c04b` and `d140` were identified with certainty.

## 4. Probe candidate registers with a raw read

To find which registers the *boiler itself* holds, add a read line that returns raw hex, addressed to `3c`:

```csv
r,boiler,probe_0120,,,3c,2000,0120,raw,s,HEX:*
```

Trigger it by publishing an empty message to `ebusd/boiler/probe_0120/get` and read the reply in the log
(`sent read boiler probe_0120 QQ=31: 01 01`). The reply is a status byte `01` followed by the value, little-endian:
`01 4e 02` = `0x024e` = 590 = 59.0 °C. Once you know the type, replace the probe with a typed, named line and give the
value field a name so Home Assistant templates get a stable payload:

```csv
r,boiler,heating_enabled,Heating enabled,,3c,2000,0120,,s,IGN:1,,,,value,s,UCH,0=off;1=on
```

(`IGN:1` swallows the status byte; the named `value` field becomes `{"value": {"value": "on"}}` over MQTT.)

Candidate IDs came from other people's repos. Registers other boilers hold are not guaranteed on yours: one Mira C Green
map failed completely on a Cares S.

## 5. Test each write on its own

For one register at a time, with a person at the boiler:

1. Add a write line addressed to `3c`: `w,boiler,set_x,...,3c,2020,<id>,,m,<type>,...`.
2. Note the settings counter (`d140`) and the current value.
3. Publish the new value to `ebusd/boiler/set_x/set`.
4. Confirm: the display changed, the read-back matches, the log shows no error.
5. Restore the original value the same way.

Results on this boiler:

| Write | Result |
|---|---|
| `6571` = 58 then 59 | display and bus followed within ~4 s |
| `0120` = off / on | `standby`, radiator icon gone / heating resumed |
| `0220` = off / on | tap icon gone / back |
| `1919` = 1 / 0 | accepted, held for 3+ min, **settings counter unchanged**, but no visible effect while the `TA` input is linked (unverified path) |

After the writes the boiler re-broadcast error **236** (`0xEC`, outdoor probe disconnected) and a `2020` settings dump,
and 1-3 polls failed with `SYN received` / `wrong symbol`. All benign.

## 6. Expose it in Home Assistant, behind guard rails

- Only allow-listed writes in the CSV; `just lint` enforces it.
- Slider ranges narrower than the boiler's own range.
- A read-back automation after every write (3 s later) and a periodic / startup refresh so entities never sit at `unknown`.
- A schedule that writes only when the target differs from the current value.

## Lessons learned

- **Unknown switches render as lightning-bolt buttons.** ebusd only publishes a value when asked, so after every HA
  restart or MQTT reload an MQTT switch sits at `unknown` and the frontend shows two bolt buttons instead of a toggle.
  Tapping one *writes*. Fix: a refresh automation that sends `.../get` on startup, on `homeassistant/status online`, on
  settings-counter changes and every 5 minutes.
- **Schedule automations that react to helper edits need `mode: restart`.** The first version (`mode: queued`, target
  computed at trigger time) wrote a stale temperature while helpers were being recreated. Debounce 5 s, then compute the
  target from current state.
- **YAML-defined helpers can't be edited in the UI** ("can't be managed from the UI"), only their values. Create helpers
  in the UI (or ship the YAML variant and accept that).
- **Entity ids come from the device's area.** `suggested_area: Heating` produced `sensor.heating_ebusd_boiler_*`.
- **ebusd named-field payloads.** Unnamed fields arrive as `"0"`, `"1"`... and named ones by name; name the fields you
  template on.
- **`circulating` isn't a fault.** It's the burner waiting out the ignition delay; see the README's short-cycling note.
- **Dashboard URL paths need a hyphen** (`dashboard-heating`).
- **ebusd 26.x** broke some Ariston setups (people rolled back to 25.1); 26.1 ran fine here.

## Safety notes collected from other people's reports

- Settings live on cheap flash with limited write cycles: write on user action, not in loops.
- `2034` (bus reset) and polling `203b` (address announce) can make some boilers crash and reboot (Cares S).
- Unknown injected errors show as `---` and clear only with a bus reset: don't broadcast made-up errors.
- Some users reported "discovery loop" / blocked-boiler problems traced to adapter power draw or poor bus levels.
- Writes may be silently ignored: always read back.
- Maximum-CH-power `6329` writes reportedly failed on a Genus One; verify any register before relying on it.

## References

| Repo | Boiler | Useful for |
|---|---|---|
| [wrongisthenewright/ebusd-configuration-ariston-bridgenet](https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet) | Genus One Hybrid | the base CSV (this repo derives from it); issues #17 (DHW setpoint `6126`), #40, #45 |
| [ysard/ebusd_configuration_chaffoteaux_bridgenet](https://github.com/ysard/ebusd_configuration_chaffoteaux_bridgenet) | Chaffoteaux Mira C Green (boiler-only, same `37`/`3c`) | best register map, `2001` min/max reads, error codes, brute-force tools |
| [gnagy/ha-ariston-ebusd](https://github.com/gnagy/ha-ariston-ebusd) | Genus One System | write allow-list, design notes; `c079`: 2 = room only, 3 = outdoor only |
| [Apuka73/homeassistant-ariston-gas-boiler-ebusd](https://github.com/Apuka73/homeassistant-ariston-gas-boiler-ebusd) | Cares S System 24 | broadcast register map (Hungarian); sees the same `46xx` values |
| [Syax89/Ariston-Cares-S-Ebusd](https://github.com/Syax89/Ariston-Cares-S-Ebusd) | Cares S | `2020` settings dumps, boiler-reboot warning |
| [kredow/ariston-ebus-prococol](https://github.com/kredow/ariston-ebus-prococol) | Clas Premium Evo | registers mapped to Sensys menu numbers |
| [HA forum thread](https://community.home-assistant.io/t/ariston-group-integration-via-ebusd/738887) | many | field reports, adapter and wiring tips |
| [ebusd](https://github.com/john30/ebusd), [adapter docs](https://adapter.ebusd.eu) | - | the daemon and the Shield C5 |
