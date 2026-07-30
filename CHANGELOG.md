# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-07-30

### Changed

- The writer is now a required sibling for every `Hawk.Resource`. `writer: false`
  is no longer supported; gate writes with `write(:never)` in the policy
  instead of omitting the writer. The `:capabilities` map now reports only the
  optional adapters (`json_api`, `live_view`, `actions`) — the reader and
  writer are always present, so they have no capability flag.
- `Hawk.Plans.run/3` is now `Hawk.Plans.run/2`. The repo is resolved from the
  ops' resource readers, and a plan batch raises if its ops span more than one
  repo, since a single Ecto transaction cannot roll back a write through
  another repo. A reader that exposes no `repo/0` is also rejected.
- Reader sorting is a first-class `:sort` option — a keyword list of
  `{dir, column}` (the same shape Ecto `order_by` takes) — rather than riding
  inside `:page` as `column`/`dir`. Passing `:column`, `:dir`, or `:cursor` in
  `:page` now raises instead of being silently dropped.
- JSON:API controllers no longer accept a `:model` opt; the backing model is
  resolved from the resource facade. `Hawk.OpenApi.spec/2` takes `Hawk.Resource`
  facades; `Hawk.OpenApi.Controller` passes `:title`, `:version`, `:path_prefix`,
  `:license`, `:servers`, and `:security` straight through.
- The OpenAPI controller serves the spec as `application/json` instead of
  `application/vnd.api+json` (an OpenAPI document is JSON, not a JSON:API
  resource).
- `Hawk.Actions` is documented as an orchestration layer above `Reader` and
  `Writer`: compose reads and writes through the resource reader and writer,
  passing the caller's authority straight through. There is no separate
  action-level policy — authorization comes from the layer below (`read_filter/1`
  scopes reads, `create?/update?/delete?` gate writes).

### Added

- OpenAPI: `:servers` and `:security` options on `Hawk.OpenApi.spec/2` and the
  controller.
- OpenAPI documents `page[number]`, `filter`, and sparse-fieldset `fields`
  query parameters, with declared filter keys and supported operators listed
  in the description.

### Fixed

- Corrected how the resource `Reader` is found in plan specs.

## [0.4.0] - 2026-07-29

Initial tracked release. Adds the MIT License and Hex package metadata
(`licenses`, `links`, `files`) in `mix.exs`. Earlier 0.x versions are
untracked history.

[Unreleased]: https://github.com/Raphexion/hawk/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Raphexion/hawk/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Raphexion/hawk/releases/tag/v0.4.0
