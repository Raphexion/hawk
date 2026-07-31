# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Two-phase Actions.** An action declaring `build: true` (or `build: :fn`)
  opts into a validate-without-commit phase: write a single `build_<handler>/3`
  that returns a `Hawk.Multi` of facade-call steps, and Hawk generates
  `<handler>_change/3` (validate) and `<handler>_run/3` (commit) as projections
  of it, so the two phases cannot drift. `Hawk.Actions.dispatch/5` routes a
  two-phase action's commit to `<handler>_run/3`. Run-only actions (no `build:`)
  keep their hand-written handler and have no validate phase.

- **`Hawk.Multi.to_changesets/1`.** Validates a multi's `:create`/`:update`
  steps through the facade `change_*` functions without committing, returning a
  map of step name to changeset. `:action`/`:run` steps raise — a multi using
  them is run-only and cannot be live-validated.

- **JSON:API action dry-run.** `POST /-actions/:action` with `dry-run: true`
  validates a two-phase action and returns a JSON:API error document without
  committing. Run-only actions reject dry-run with `400`.

- **LiveView `hawk_validate_action/6` / `hawk_action/6`.** Drive an action
  from a LiveView form: live validation through the action's `change` phase,
  commit through `run`, with `on_success` receiving the full results map.

- **LiveView `source:` path preloads.** `column`/`field` (index and show)
  accept a `source:` path (e.g. `[:teacher, :name]`) reaching an association.
  The LiveView adapter declares the shape; the reader owns loading; `mix
  hawk.validate` enforces every path association is a declared reader preload
  (symmetric to the JSON:API relationship ⊆ reader-preload check).
  `assign_index`/`assign_show` derive preloads from the adapter; the runtime
  `preloads:` opt is rejected. Form fields do not accept paths — they bind to
  root-model attrs the writer casts.

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
