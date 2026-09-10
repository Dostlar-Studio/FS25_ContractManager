# FS25 Contract Manager

Advanced contract management for Farming Simulator 25 dedicated servers and single player.
A script mod by **Dostlar STUDIO**. Uses only the game's own screens, no custom HUD.

> **Beta.** The mod is in public testing on ModHub. Please report problems (see below).

## Features

**Rules** (ESC > Settings > Contract Manager, server admin only)
- Reward multiplier with minimum/maximum, failure penalty as a share of the reward, leased vehicle cost multiplier.
- Active contracts per farm, contracts on the board, per-type limits, generation interval, contract duration, expiry warnings.
- Enable/disable each contract type and weight it against the others.
- Reputation: completed contracts earn points, failures lose them; points give a reward bonus and an extra contract slot.
- Field cooldown after a finished contract; all toggles for partnership and the management page.

**Product guard** (server authoritative)
- Contract crops move only between vehicles of the same farm; ground dumping, cross-farm transfers and wrong unloading points are blocked.
- Only the delivery point of the contract accepts the protected product; a started contract cannot be cancelled.
- On timeout or forced failure the net contract product accumulated since acceptance is confiscated.

**Contracts page and Contract Management page**
- Contract details: time left, possible penalty, active contracts / limit, expected yield and delivery amounts, progress.
- Reserve a contract for your farm for a set number of minutes.
- Partner contracts: invite another farm, accept or decline, share the reward by contribution. The HUD bar shows role and expected payout for owner and partner.
- Admin tools: refresh the board, force-cancel, transfer, assign to a farm. Bottom-bar buttons, confirmation dialogs and console commands.
- Farm statistics and leaderboard in the settings tab.
- FS25_DiscordBridge integration: contract events go to Discord when that mod is loaded.
- Replaces FS25_ContractGuard and migrates its save data. Yields its rules automatically when FS25_BetterContracts is loaded.

## Installation

1. Put `FS25_ContractManager.zip` into the `mods` folder of the server and of every player.
2. Remove `FS25_ContractGuard.zip` if you still have it.
3. Enable the mod for the savegame and restart the server. All players need the same version.

PC/Mac only (script mod).

## Settings file

`Documents/My Games/FarmingSimulator2025/modSettings/FS25_ContractManager.xml` is created with defaults on first run.
Everything in it can also be changed in game. Invalid values fall back to the default and are logged.

## Reporting problems

- Email: hello@kahrastudio.art
- Issues: https://github.com/Dostlar-Studio/FS25_ContractManager/issues

Please attach the lines of `log.txt` that contain `[CM]`.

## Repository layout

```
modDesc.xml          mod descriptor, changelog (en/de/fr/tr)
scripts/             Lua sources (core, rules, gui)
gui/                 dialog XML, GUI profiles, tab icon
l10n/                translations
README.txt           Turkish player manual shipped inside the zip
```

## License

All rights reserved, Dostlar STUDIO. You may use and redistribute the unmodified mod package.
Do not re-upload modified versions under the same name.
