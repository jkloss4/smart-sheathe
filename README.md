# Smart Sheathe

Keeps your weapons drawn in World of Warcraft when the game puts them away on its own, such as when you loot or
leave combat. Weapons you put away yourself stay away.

Retail (Interface 120100) and WoW: Forever (Interface 16001).

## Features

- **Drawn again after the game sheathes them.** If your weapons were out and the game puts them away (looting,
  leaving combat), they're drawn again once the loot window closes.
- **Your choice wins.** Putting them away with the Sheathe/Unsheathe key (Z by default), sitting or an emote is left
  alone.
- **Out of the way.** Mounting, druid forms and Ghost Wolf, swimming, taxis and vehicles, eating and drinking, and
  dying all put weapons away on purpose, so those are left alone too.
- **Optional triggers:** draw your weapons when you target an enemy, or when you enter combat.
- **Per character.** *Enable on This Character* is saved per character, so it can stay off on a caster.

Options are in Options → AddOns → Smart Sheathe.

Slash commands: `/smartsheathe` (options), `/smartsheathe on` / `off` (this character), `/smartsheathe trace` (prints
what it sees and does to chat).

## Install

Download `SmartSheathe-<version>.zip` from the [latest release](../../releases/latest) and extract the
`SmartSheathe` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` for WoW: Forever (`_retail_`
instead of `_classic_beta_` for retail).

An addon manager that installs from GitHub releases (e.g. WowUp: *Install from URL* with this repo's URL) can also
install and update it, **but only if the repository is public**.

To update from the command line (works for a private repo, needs `gh auth login` once):

```powershell
.\scripts\update-from-release.ps1
```

## Developing / releasing

- Test local changes: `.\scripts\install-local.ps1` copies the addon folder into `AddOns` (WoW: Forever by default;
  `-AddOnsPath` for retail), then `/reload`.
- After a WoW patch: bump `## Interface:` in `SmartSheathe/SmartSheathe.toc`.
- Release: `git tag v1.0.1 && git push --tags`. The [Release workflow](.github/workflows/release.yml) stamps the
  version into the TOC, builds the zip (with a `release.json` so addon managers see it's a retail and Forever build), and
  publishes the GitHub release.

## License

MIT ([`LICENSE`](LICENSE), also included in the addon folder).
