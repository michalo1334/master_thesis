# Provenance

This directory contains a local fork of [`JoniBR/pi-fusion`](https://github.com/JoniBR/pi-fusion).

- Upstream commit: `29623dc904a4f5ea93b7af37544a05905fc001e3`
- Upstream package version: `0.1.1`
- Imported files: `package.json`, `README.md`, and `extensions/fusion.ts`
- Imported skill: `.pi/skills/fusion/SKILL.md`

## Local changes

- Replace the removed `modelRegistry` SDK option with Pi 0.87.1-compatible model lookup and session creation.
- Add JSON configuration for the sidekick model, timeout, exact tool allowlist, and selected extension packages.
- Load only `pi-mcp-adapter` and `context-mode` when the JSON policy selects them.
- Keep `follow_up` task IDs valid only in the current Pi process.

See the local README for the configuration and tool policy.

## License

The upstream package metadata declares `MIT`. The imported upstream commit has no `LICENSE` file. This repository
records that declaration here and does not add a license text on the upstream author's behalf.
