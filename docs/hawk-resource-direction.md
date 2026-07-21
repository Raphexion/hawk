# Hawk Resource Direction

Hawk is a resource-oriented Phoenix backend framework. JSON:API and LiveView are first-class adapters over Hawk Resources, not the core abstraction themselves.

## Core shape

- Hawk Resources are the product: Reader, Writer, Policy, Actions, and adapter contracts define how a domain resource is read, mutated, authorized, documented, and exposed.
- Resources model domain resources, not necessarily database tables. Table-backed schemas, views, projections, summaries, and computed resources should all fit.
- JSON:API and LiveView should feel native and work well together while consuming the same resource capability model.
- Related resource rendering should discover adapter metadata through resource facades instead of forcing duplicate model-level JSON:API declarations.

## Convention with explicit absence

The golden path should be low-boilerplate:

```elixir
defmodule MyApp.Courses do
  use Hawk.Resource, model: MyApp.Course
end
```

By convention this expects modules such as:

- `MyApp.Courses.Reader`
- `MyApp.Courses.Policy`
- `MyApp.Courses.Writer`
- `MyApp.Courses.JsonApi`
- `MyApp.Courses.LiveView`

Hawk should fail at compile time when expected modules are missing or malformed. Absence should be explicit and self-documenting:

```elixir
use Hawk.Resource,
  model: MyApp.Course,
  writer: false,
  json_api: false,
  live_view: false
```

Actions are optional by default, because many resources do not have broad workflow commands.

## Adapter contracts

JSON:API and LiveView should have separate adapter modules and DSLs:

- `MyApp.Courses.JsonApi` owns external API shape: type, attributes, relationships, renamed fields, cached/computed values, docs, examples, writable request mapping, OpenAPI metadata.
- `MyApp.Courses.LiveView` owns LiveView presentation and event contracts: tables, forms, actions, params, filters, assigns, and event plumbing.

The current `json_api do` block on models is a compatibility stepping stone. Explicit adapter contracts beside the resource are the preferred shape, and Hawk discovers those adapters when rendering included/related resources.

## LiveView direction

Hawk should provide the boring data plumbing, not decide the HTML/CSS.

LiveView helpers should establish a consistent lifecycle for:

- assigning index/show data
- pagination, sorting, filters, and params
- create/update form validation
- live changeset errors while users type
- submit handling
- delete handling
- action handling
- policy-aware errors

Developers should focus on UI markup while Hawk makes the data, authorization, validation, and event pattern hard to get wrong. Live validation should use the same writer pipeline as persistence without crossing the repository boundary: `Hawk.Writer.Resource` generates non-persisting changeset helpers from declared writer pipelines, while hand-written writers can expose `change_create/2` and `change_update/3` beside `create/2` and `update/3` when they need custom pipelines. Generated LiveView form helpers are keyed by resource assign name, for example `:course_form`, so multiple forms can coexist without relying on a single global `:hawk_form` assign. Create and update forms have separate metadata because not every create field is updatable. Form assignment supports server-owned `forced_attrs` for values known from context, and those values win over client params during validation and save. `use Hawk.LiveView` generates default events for low-boilerplate screens plus `hawk_validate/2` and `hawk_save/2,3` helpers; applications can set `events: false` and call those helpers from their own `handle_event/3` clauses when they need custom flow such as navigation after save.

LiveView should not define a second visibility system. Different authorities see different rows through the same policy-aware Reader path used by JSON:API. LiveView filters and searches are UX narrowing only: they must use declared Reader filters and can never widen policy. LiveView sort controls must be declared in the adapter and backed by Reader sort keys. Index state is normalized before reading so search/sort changes reset to page 1, page changes keep the current query, and stream-backed UIs can replace the current page window instead of accumulating rows in socket memory.

## Read invariant

**Hawk Read Invariant:** every read is:

```text
policy_filter AND caller_filter AND resource_forced_filter
```

Policy is the security boundary. Adapter filters from JSON:API, LiveView params, or internal callers are additional narrowing only. Unknown filters fail closed. Preloads use the related resource's own Reader and Policy.

Policy declarations are introspectable so resource contracts can validate the seam between Policy and Reader: every scoped policy filter key must be declared as a reader filter or custom filter handler. Role matrices should be tested with Hawk's policy assertion helpers rather than repeated hand-written `read_filter/1` assertions. Apps can use the session/assign authority convention helpers for Plug and LiveView handoff, but authentication remains application-owned.

There are no hidden read bypasses. Even system reads should use `Authority.system()` and flow through the same machinery.

## Write/action invariant

**Hawk Write Invariant:** every create/update/delete/action passes through a declared Writer or Action pipeline that validates input, validates policy, and crosses the repository boundary or an equivalent workflow boundary.

System writes should also validate policy explicitly; `system` can be allowed, but it should not bypass the policy-validation path.

JSON:API relationship reads can expose projections over internal database shape, including `many_to_many` associations where the join schema is not itself part of the external API. JSON:API relationship writes are intentionally limited to `belongs_to` associations because those map cleanly to writer attrs through the owning foreign key. `has_many`, `has_one`, and `many_to_many` mutations need explicit writer/action workflows instead of being implied from JSON:API relationship linkage. Plain CRUD deletion can use the writer DSL's `delete(:default)` helper. Simple owner-scoped writers can use `write(..., owned_by: [field: :scope])`; cascading deletes and multi-resource ownership rules should remain explicit writer/action workflows.

Actions are resource-scoped workflows/commands. They may orchestrate across resources, use `Ecto.Multi`, send emails, enqueue jobs, and perform broader side effects. They remain declared, authorized, documented, telemetry-instrumented, and testable.

Member actions first resolve the primary resource through the policy-aware Reader, then validate action permission:

- cannot read/see target -> `404`
- can read target but cannot act -> `403`

## Errors

Hawk should move toward one canonical internal error representation used by readers, writers, actions, JSON:API, LiveView, and telemetry.

Internally, errors use atoms and structured fields:

```elixir
%Hawk.Error{
  status: 400,
  code: :invalid_uuid,
  title: "Bad request",
  detail: "id must be a valid UUID",
  source: %{parameter: "id"}
}
```

Adapters render this differently:

- JSON:API renders `errors: [...]`
- LiveView maps to assigns/form errors
- telemetry maps to `result`
- tests assert stable `code`

Details should have good defaults and be customizable later, but stable codes are the contract.

## Short IDs

Short IDs are a pragmatic read-only convenience, not a general identifier type.

Accepted:

- simple member `show` reads, e.g. `GET /courses/:id`

Rejected:

- mutations
- custom actions
- relationship endpoints
- request body relationship identifiers

Short ID lookup uses an indexed UUID range and checks up to two matches:

- zero matches -> `404`
- one match -> return the resource
- multiple matches -> `400` ambiguous prefix

This keeps human-friendly URLs without making writes ambiguous.

## Telemetry

Phoenix request metrics already cover endpoint-level latency/status. Hawk telemetry is only valuable when it adds resource semantics Phoenix cannot know:

- Hawk resource
- action
- result category
- ID kind (`:uuid`, `:short_id`, `:invalid`)

Telemetry should avoid raw IDs, request params, mutation attrs, and sensitive payloads by default.

## Route and capability consistency

Hawk's resource generator can produce the first Phoenix layer — JSON:API controller, clickable LiveView index/show files, and a router snippet — while apps still decide where routes belong. Full route macros can come later if repeated apps show the snippets are still too manual. Hand-written routes remain possible, but contract tests should catch route/capability drift.

`use Hawk.JsonApi.Controller` and `use Hawk.LiveView` should eventually need only `resource: MyApp.Courses`, with model and adapter metadata inferred from the resource facade.
