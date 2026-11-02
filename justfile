# Common tasks for this repo. Run `just` to list them (recipes below are alphabetical).
#
# Needs SSH access to Home Assistant (Terminal & SSH app) and, for get/set/status,
# a long-lived access token. Copy .env.example to .env and fill it in (.env is gitignored);
# variables already exported in your shell win over .env. All of them are required (no fallbacks).

set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]

ebusd := env("EBUSD_APP")
ha_url := env("HA_URL")
host := env("HA_SSH")

# ask HA to validate its configuration
check:
    ssh {{ host }} 'ha core check'

# list recipes
[default]
default:
    @just --list

# validate local files, then copy CSVs + package to HA and restart ebusd
deploy: lint deploy-ebusd deploy-ha

# copy ebusd config (CSVs) to HA and restart the ebusd app
deploy-ebusd:
    scp -q ebusd/ariston.csv ebusd/_templates.csv {{ host }}:/share/ebusd/
    ssh {{ host }} 'ha apps restart {{ ebusd }} >/dev/null && echo "ebusd restarted"'

# copy the boiler package to HA, check the config, reload MQTT + automations
deploy-ha:
    ssh {{ host }} 'mkdir -p /config/packages'
    scp -q home-assistant/packages/boiler_ebus.yaml {{ host }}:/config/packages/boiler_ebus.yaml
    ssh {{ host }} 'ha core check'
    just _reload mqtt
    just _reload automation

# OPT-IN: install YAML helpers (skip if you created the helpers in the UI - ids would clash)
deploy-helpers:
    scp -q home-assistant/packages/boiler_helpers.yaml {{ host }}:/config/packages/boiler_helpers.yaml
    ssh {{ host }} 'ha core check'
    @echo "Helpers are only picked up after:  just restart-core"

# only real problems from the ebusd log (the `ebus_reset` parse error is a known harmless one)
errors:
    ssh {{ host }} 'ha apps logs {{ ebusd }}' | grep -E 'error|invalid' | grep -v ebus_reset | tail -20 || echo "no errors"

# validate YAML syntax and sanity-check the CSV
lint:
    uv run -q --with pyyaml python3 -I scripts/lint.py

# tail the ebusd log (add a grep pattern to filter, e.g. `just logs 'set_|error'`)
logs pattern='.':
    ssh {{ host }} 'ha apps logs {{ ebusd }}' | grep -E '{{ pattern }}' | tail -40

# pull the live config from HA into this repo (review with git diff)
pull:
    scp -q {{ host }}:/share/ebusd/ariston.csv {{ host }}:/share/ebusd/_templates.csv ebusd/
    scp -q {{ host }}:/config/packages/boiler_ebus.yaml home-assistant/packages/boiler_ebus.yaml
    git --no-pager diff --stat

# ask the boiler for a value now, e.g. `just read heating_enabled`, then see the result in `just logs <name>`
read name:
    just _publish "ebusd/boiler/{{ name }}/get" ""
    @sleep 3
    just logs "read boiler {{ name }} "

# restart Home Assistant core (needed for new top-level config such as helpers)
restart-core:
    ssh {{ host }} 'ha core restart'

# restart the ebusd app
restart-ebusd:
    ssh {{ host }} 'ha apps restart {{ ebusd }}'

# show the key boiler entities from Home Assistant
status:
    curl -fsS -H "Authorization: Bearer ${HA_TOKEN:?set HA_TOKEN}" "{{ ha_url }}/api/states" | python3 -I scripts/status.py

# WRITE a value to the boiler (allow-list names only), e.g. `just write set_ch_setpoint 55` or `just write set_heating_enabled off`
write name value:
    #!/usr/bin/env bash
    case "{{ name }}" in
      set_ch_setpoint|set_heating_enabled|set_dhw_enabled) ;;
      *) echo "refusing: '{{ name }}' is not in the write allow-list (see ebusd/ariston.csv)" >&2; exit 1 ;;
    esac
    echo "Reminder: settings live on the boiler's flash - write on purpose, not in loops."
    just _publish "ebusd/boiler/{{ name }}/set" "{{ value }}"

[private]
_publish topic payload:
    curl -fsS -X POST -H "Authorization: Bearer ${HA_TOKEN:?set HA_TOKEN}" -H "Content-Type: application/json" \
      -d '{"topic":"{{ topic }}","payload":"{{ payload }}"}' "{{ ha_url }}/api/services/mqtt/publish" >/dev/null && echo "published {{ topic }}"

[private]
_reload domain:
    curl -fsS -X POST -H "Authorization: Bearer ${HA_TOKEN:?set HA_TOKEN}" "{{ ha_url }}/api/services/{{ domain }}/reload" >/dev/null && echo "reloaded {{ domain }}"
