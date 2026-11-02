# Register map (Ariston Clas HE System EVO 30 EU)

Everything here was observed on **one** boiler (Clas HE System EVO 30 EU, gas-only, no outdoor sensor, no room
controller, eBUS slave address `0x3c` / master `0x37`). Other Ariston/Chaffoteaux/Elco models may differ. Register IDs are
written the way they appear on the wire and in `ebusd/ariston.csv`, so `6197` is register `0x9761` (little-endian).

**Confidence**

| Label | Meaning |
|---|---|
| **Verified** | Changed it on the boiler (front panel or eBUS write) and watched the display and the bus agree |
| **Held by boiler** | The boiler answers a read to `3c` with a value that matches the display / its state |
| **Plausible** | Value looks right but I haven't forced a change |
| **Unknown** | Value seen, meaning not established |

## Message types (primary command `0x20`)

| PBSB | Meaning |
|---|---|
| `2000` + ID | Read request. To `3c` the boiler replies `01` + value (little-endian). The boiler also *broadcasts* these to `fe` to ask for values nobody answers (outdoor temp, zone offsets...) - they carry no data and are ~70 % of traffic. They show as `unknown BC cmd` in the ebusd log: expected |
| `2001` + ID | Read with limits: `[len][current][min][max]` (per [ysard](https://github.com/ysard/ebusd_configuration_chaffoteaux_bridgenet)) |
| `2010` | Value broadcast: list of `[ID][value]` |
| `2020` + ID + value | Write. The boiler also broadcasts a "settings dump" in this form after a setting changes |
| `2004` | Error broadcast `[code][zone flags]` |
| `2034` / `203b` | Bus reset / address announce. **Never send or poll these** (a Cares S owner reported the boiler rebooting) |

## Heating controls (read + write)

| ID | ebusd name (read / write) | Value | Verified how |
|---|---|---|---|
| `6571` | `z1_heat_setpoint` / `set_ch_setpoint` | flow setpoint, SIN/10 °C | **Verified.** Write 58 -> display 58 within seconds; panel changes read back. Boiler accepts 35-82 °C |
| `0120` | `heating_enabled` / `set_heating_enabled` | 0 off / 1 on | **Verified.** Write off -> boiler `standby`, radiator icon disappears |
| `0220` | `dhw_enabled` / `set_dhw_enabled` | 0 off / 1 on | **Verified.** Write off -> tap icon disappears (see note below) |

`6571` is the Z1 **fixed** flow setpoint, which is what the front-panel +/- buttons edit when thermoregulation is
"fixed" (no outdoor sensor). `6197` (below) is the *computed* setpoint the boiler then broadcasts.

> **Hot water note.** On this boiler the left +/- buttons (DHW setpoint) do nothing and DHW burner hours stay 0 - no
> cylinder sensor is connected, so the tap icon only toggles a mode flag. The cylinder (upstairs, with a backup
> immersion) is heated off the heating flow, so to the boiler it is just heat demand. If your boiler has a cylinder
> sensor your result will differ.

## Read-only

| ID | ebusd name | Example | Confidence / notes |
|---|---|---|---|
| `c04b` | `boiler_status` | heating | **Verified.** 1 standby, 2 heating, 3 DHW, 5 circulating, 23 manual test, 24 comfort, 31 deaeration, 36 auto-calibration, 51 low water pressure, 52 no flame. `circulating` = pump on, burner off |
| `6197` | `ch_setpoint_temp` (2010) | 59.0 °C | **Verified.** Computed Z1 flow setpoint; follows `6571`. Read-only, never write |
| `0191` | `heat_request` (2010; z1;z2;z3) | on;off;off | **Verified.** Z1 = heating enabled **and** demanded. Goes off in summer mode / heating off |
| `d140` | `config_version_counter` | 16 | **Verified.** +1 on every setting change (panel or eBUS write). Useful trigger for "someone changed a setting" |
| `6810` | `flow_temp` | 45.4 °C | Held by boiler |
| `6910` | `ewt_temp` | 43.1 °C | Held by boiler - heating **return** temperature |
| `6847` | `flame_power_kw` | 7.3 kW | Plausible |
| `6829` | `nominal_power` | 30 kW | **Verified** (model number) |
| `4bd1` | `hours_burner_on_ch` | 4842 h | Plausible |
| `6071` / `6171` | `z1_water_max` / `z1_water_min` | 82 / 35 °C | Held by boiler - setpoint limits |
| `0520` | `auto_function` | off | Held by boiler - `auto/C` button |
| `6126` | `dhw_comfort_temp` | 60 °C | Stored but unused here (no cylinder sensor) |
| `6229` `6329` `6429` `6529` `6629` | power limit params | 86 / 78 / 18 / 60 / 60 % | DHW max / CH max / CH min / slow ignition / CH max adj. Installer parameters; others report `6329` writes failing |
| `c027` `1320` `c227` | `ignition_delay`, `ignition_delay_type`, `heat_post_circulation` | 3 min, automatic, 3 min | Held by boiler. Explains the ~4:45 gap between burner starts (see README, short cycling) |
| `7647` | outdoor temp | `7fff` | `7fff` = no sensor |
| `1919` | `z1_heat_activation` | 0 | What an eBUS room thermostat sends (per ysard). Read/write works and does **not** bump `d140`, but the effect on heating is **unverified** (needs the `TA` input unlinked). Write line left commented out |
| `6297`..`6797` | `raw_9762`..`raw_9767` (not shipped) | 40.0 °C | Z2-Z7 computed setpoints per other boilers' research - unused zones |
| `d746` `da46` `dc46` `de46` | (not shipped) | 0, 150, 75, 75 | Unknown. Same values reported on other boilers |
| `4cd1` `42d2` | DHW burner hours, pump hours | 0, 0 | Likely unused on this boiler |
| `c428` | `boiler_type` | ext_tank_thermostat | Held by boiler. Hot-water configuration: 0 mixed_instant, 1 ext_tank_ntc, 2 ext_tank_thermostat, 3 micro_storage, 4 stratification_storage, 6 storage |
| `40d2` `c012` | `diverter_cycles`, `diverter_valve` | 0, dhw | Held by boiler. 0 cycles after 2332 ignitions = the boiler's own hot-water path has never been used (see hot-water note above) |

## Errors

The `2004` broadcast is `[error code][zone flags]`. After a write the boiler re-announced code **236** (`0xEC`), which
[ysard](https://github.com/ysard/ebusd_configuration_chaffoteaux_bridgenet) documents as "external probe disconnected":
true here, there is no outdoor sensor. It is harmless and the display showed no fault. The shipped CSV's `error` line
uses a template without that code, so it prints `236` rather than a name.

## Front-panel reference

- **Right +/-**: heating setpoint. The first press only enters edit mode (value blinks, icons hide); further presses change
  it; it saves itself after a few seconds.
- **Tap/radiator button**: cycles tap+radiator (normal) -> radiator only (DHW off) -> tap only (**summer: heating off**) -> back.
- Don't touch `Reset` or the wrench knob unless an error is showing.
