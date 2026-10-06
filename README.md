<p align="center">
  <img src="docs/vanadial-logo-source.png" alt="Vana'Dial" width="640">
</p>

# Vana'Dial

Standalone Ashita v4 addon for FFXI: Vana'diel time, elemental days, moon phase, zone weather, transport timers (airships, boats, RSE, lunar), and guild shop hours.

## See it in action

**Clock, days, moon phase, and Fenrir tooltip**

<img src="docs/example-moon-tooltip.png" alt="Vana'Dial moon phase and Fenrir tooltip" width="720">

<img src="docs/example-full-moon.gif" alt="Vana'Dial moon phase tooltip in motion" width="720">

**Airship, boat, RSE, and lunar timers**

<img src="docs/example-timers.png" alt="Vana'Dial airship timer panel" width="720">

<img src="docs/example-timers.gif" alt="Vana'Dial timer panel in motion" width="720">

**Settings** (`/vd config`)

<img src="docs/example-settings.png" alt="Vana'Dial settings window" width="560">

<img src="docs/example-settings.gif" alt="Vana'Dial settings window in motion" width="560">

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
| `/vd boats` | Toggle ferry boat timers (Selbina/Mhaura/Whitegate/Nashmau) |
| `/vd boatsall` | Toggle all boat timer sub-groups |
| `/vd manaclipper` | Toggle Bibiki Manaclipper timers |
| `/vd barge` | Toggle Carpenters' Landing barge timers |
| `/vd rse` | Toggle RSE timers |
| `/vd lunar` | Toggle lunar phase timers |
| `/vd guilds` | Toggle guild shop timers |
| `/vd sunbreezerace` | Toggle the independent standalone Sunbreeze Racing event window |
| `/vd popout <group>` | Pop that timer group into its own window (`ships`, `boats`, `boatsall`, `manaclipper`, `barge`, `rse`, `lunar`, `guilds`). Run again to close |
| `/vd popout close` | Close every timer pop out |
| `/vd reset` | Reset the Vana'Dial, Sunbreeze Racing, and timer pop out positions |
| `/vd update` | Download latest from GitHub (`main` branch); then `/addon reload vanadial` |
| `/vd checkupdate` | Check GitHub for a newer version |
| `/vanadial` | Alias for `/vd` |

Each timer row has a pin on the right. Click it to detach that route — Selbina <> Mhaura, for example — into a small window you can leave open with the timer panel closed. Click the pin again, or the window's ×, to close it.

On login, Vana'Dial checks GitHub once (after a short delay) and prints a chat message if a newer version is available.

**Updating:** Run `/vd update` in-game (downloads addon files from GitHub, same as Anglin). Then `/addon reload vanadial`. Per-character settings under `config/addons/vanadial/` are not overwritten.

## Requirements

- Ashita v4 with `imgui`, `settings`, and `ffxi` libs (standard Ashita v4 install)
