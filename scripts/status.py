"""Print the key boiler entities from a Home Assistant /api/states JSON document on stdin."""
import json
import sys

PREFIXES = (
    "number.boiler_",
    "switch.boiler_",
    "input_boolean.boiler_",
    "input_number.boiler_",
    "input_datetime.boiler_",
    "sensor.heating_ebusd_boiler_boiler_status",
    "sensor.heating_ebusd_boiler_flow_temp",
    "sensor.heating_ebusd_boiler_ewt_temp",
    "sensor.heating_ebusd_boiler_flame_power_kw",
)

for entity in sorted(json.load(sys.stdin), key=lambda e: e["entity_id"]):
    if entity["entity_id"].startswith(PREFIXES):
        unit = entity["attributes"].get("unit_of_measurement", "")
        print(f"{entity['entity_id']:55} {entity['state']} {unit}".rstrip())
