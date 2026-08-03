# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Actions are explicitly trusted application code.** Hawk passes authority to
  action handlers but does not enforce their implementation. Protected reads
  and writes must go through policy-aware Readers and Writers; direct Repo calls
  and other side effects are outside Hawk's authorization guarantees.

### Fixed

- **OpenAPI content-negotiation responses.** Every generated operation documents
  the `406` and `415` JSON:API error documents returned by controller media-type
  negotiation.

- **Required OpenAPI relationship linkage.** Write relationship objects require
  `data`; non-null to-one and every to-many resource identifier require `type`
  and `id`, while to-one linkage explicitly permits `null`.

- **Complete OpenAPI success-document shapes.** Generated schemas describe
  top-level and resource/relationship links, compound-document `included`, and
  pagination `meta.page` using reusable JSON:API components.

- **Required OpenAPI response members.** Generated response schemas require
  top-level `data`, resource `type`/`id`, and error-document `errors`, matching
  the JSON:API documents Hawk emits and producing non-optional client types.

- **JSON:API include aliases.** Runtime include parsing resolves external
  relationship names declared with `source:` at every path segment, matching
  the values generated in OpenAPI.

- **JSON:API action request documents.** Custom actions require a top-level
  `meta` object at runtime and in OpenAPI, including actions with no declared
  parameters; missing or non-object `meta` returns `400`.

- **JSON:API query-parameter names.** Unknown bare lowercase parameter names
  reserved by JSON:API now return `400`; implementation-specific names with a
  non-letter separator remain available to host applications.

- **JSON:API relationship endpoint semantics.** Unknown relationship names on
  linkage and related-resource URLs return `404` instead of being treated as
  malformed query input with `400`.

- **JSON:API multi-field sorting.** Collection requests accept ordered,
  comma-separated sort fields such as `sort=title,-id`; OpenAPI documents the
  syntax and allowed Reader fields without restricting the value to one field.

- **JSON:API compound-document uniqueness.** Cyclic include paths no longer
  repeat a primary resource in `included`.

- **JSON:API media negotiation.** Controllers emit the exact
  `application/vnd.api+json` media type without the forbidden `charset`
  parameter, reject unsupported request media types/parameters with `415`, and
  return `406` when `Accept` does not allow a JSON:API response.

- **Consistent controller authority lookup.** JSON:API controllers read the
  `:hawk_authority` assign produced by `Hawk.Authority.Plug`,
  `Hawk.Authority.Session`, and `Hawk.PhoenixAuth`.

- **Atomic multis and transaction-safe broadcasts.** Failed `Hawk.Multi` steps
  now roll back prior writes. A Multi supports one Repo and rejects resource
  steps backed by a different Repo before execution. PubSub events are deferred
  until the transaction owned by the Multi commits and discarded for failed
  multis and plan previews. Direct broadcasting Writers and broadcasting Multis
  invoked inside an unmanaged caller transaction are rejected rather than
  publishing prematurely or silently dropping events.

- **Ownership checks preserve explicit `nil` changes.** Clearing an `owned_by`
  field no longer falls back to the model's previous value during authorization.

- **Server-owned LiveView delete authority.** Generated delete events now resolve
  authority from socket assigns instead of accepting it in browser parameters,
  and index refreshes retain caller-supplied reader options.

- **Stricter JSON:API request handling.** Malformed query-parameter shapes return
  `400` documents instead of escaping as function-clause errors. Update documents
  require matching `type` and `id` members, and unloaded to-many relationships
  omit linkage rather than claiming to be empty.

- **Accurate OpenAPI contracts.** Write schemas declare required identity members,
  relationship endpoints describe target cardinality, and host applications can
  define `components.securitySchemes` through `:security_schemes`.

- **Hex package metadata.** The package now includes the required description.

- **Clearer LiveView source-path preload errors.**
  Hawk now validates declared LiveView `source:` paths after loading records and
  raises a targeted error when a required association is still unloaded or was
  filtered out by the associated resource policy.

- **No more stale-bake of sibling metadata in generated consumers.**
  `Hawk.LiveView` helpers now pass the resource facade and resolve
  `__hawk_live_view__/0` at runtime; `Hawk.Resource.action/4` resolves
  `Actions.__hawk_actions__/0` at runtime through `Hawk.Actions.dispatch/5`.
  Facades no longer generate one public function per action, and JSON:API
  controllers expose a stable `hawk_action/2` entrypoint that returns not found when
  no matching action exists. See the "Compile-time contracts and runtime
  lookup" section in the README.

### Added

- **Real-time updates via `Hawk.PubSub`.** A writer declaring `:pubsub`
  (the host application's `Phoenix.PubSub`) broadcasts a `Hawk.PubSub.Event`
  on every successful `create`/`update`/`delete`, fired after the write's
  transaction commits. The event carries the resource, operation, and identity
  value — not the model — so each subscriber re-queries through its own
  authority and the read policy is never bypassed. The optional `:topics` opt
  accepts a `Hawk.PubSub.TopicStrategy` (defaulting to
  `Hawk.PubSub.DefaultTopics`) so host applications can scope topics per-tenant
  for isolation. `Hawk.LiveView.subscribe/2` reads `:pubsub` and the topic
  strategy from the resource and subscribes the LiveView process (routing,
  not authorization); `Hawk.LiveView.refresh/3` re-runs the current index or
  show screen through the socket's authority. Resources without `:pubsub`
  never broadcast. See the "Real-time updates" section in the README.

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
