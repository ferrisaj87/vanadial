# Vana'Dial

Standalone Ashita v4 addon for Horizon XI / FFXI: Vana'diel time, elemental days, moon phase, zone weather, and transport timers (airships, boats, RSE, lunar).

Also available integrated in [XIUI](https://github.com/ferrisaj87/XIUI).

## Install

Clone or copy this folder into your Ashita `addons` directory:

```
Game/addons/vanadial/
```

Load with `/addon load vanadial` (or add to your default load list).

Per-character settings are stored under `Game/config/addons/vanadial/<character>/settings.lua`.

## Commands

| Command | Action |
|---------|--------|
| `/vd` | Toggle visibility |
| `/vd config` | Open configuration |
| `/vd ships` | Toggle airship timers (expand section) |
| `/vd boats` | Toggle boat timers |
| `/vd rse` | Toggle RSE timers |
| `/vd lunar` | Toggle lunar phase timers |
| `/vd reset` | Reset window position |
| `/vanadial` | Alias for `/vd` |

Timer subcommands also accept `vtships`, `vtboats`, `vtrse`, and `vtlunar` (same as `ships`, `boats`, `rse`, `lunar`) if you are used to XIUI’s `/xiui vtships` naming.

## Requirements

- Ashita v4 with `imgui`, `settings`, and `ffxi` libs (standard Horizon XI Ashita install)
