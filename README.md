<p align="center">
  <img src="docs/vanadial-logo-source.png" alt="Vana'Dial" width="640">
</p>

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
| `/vd update` | Pull latest from GitHub (git clone installs; then `/addon reload vanadial`) |
| `/vd checkupdate` | Check GitHub for a newer release |
| `/vanadial` | Alias for `/vd` |

On login, Vana'Dial checks GitHub once and prints a chat message if a newer release is available.

**Updating:** Clone the repo into `Game/addons/vanadial/` so `/vd update` can run `git pull`. Zip-only installs should update manually from [releases](https://github.com/ferrisaj87/vanadial/releases).

Timer subcommands also accept `vtships`, `vtboats`, `vtrse`, and `vtlunar` (same as `ships`, `boats`, `rse`, `lunar`) if you are used to XIUI’s `/xiui vtships` naming.

## Requirements

- Ashita v4 with `imgui`, `settings`, and `ffxi` libs (standard Horizon XI Ashita install)
