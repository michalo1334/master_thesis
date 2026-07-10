# Info

A system for modeling and applying defenses (minimizing blast radius) in computer networks.

SEE README.md FIRST

## Infrastructure

### Secrets & inputs

To provide agnostic way of passing inputs and secrets, use two mechanisms: 

 - for non-sensitive inputs **environment variables**
 - for secrets **files** that have restrictive permissions or mounted into container

Good:
 - using .env for local development (gitignored!)
 - using secret managers (AWS, Hashicorp etc) to fetch state into files 
 - using sidecar or scripts that fetch vars right before starting the stack

Bad
 - hardcoding values passed in e.g. docker compose
 - "ifology" inside app (provider or SDK specific)

To discuss with user
 - "common defaults" like well-known service ports or port mappings (e.g. Grafana, PostgresSQL)

## Documentation

- Always activate `writing-clearly-and-concisely` skill before proceeding with writing documentation OR interacting with the user. UNCONDITIONALLY.
- Always use Mermaid for diagrams, including those embedded inside markdown blocks. See `mermaid-diagrams` for reference. Do not use ASCII art or other languages like PlantUML unless expliticly specified by the user
- Never copy paste source code or concrete values unless is for example purposes. It gets outdated very quickly. Instead point to relevant file/place for current values. The point is that documentation can get out of sync with aspects that change dynamically like source code
- Do not document what can be read from the config or source code. Document why, not what.

## Project tracking

Repo issues: https://github.com/michalo1334/master_thesis/
