<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Raphexion/hawk/main/assets/hawk-light.png">
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Raphexion/hawk/main/assets/hawk-dark.png">
    <img alt="hawk logo" src="https://raw.githubusercontent.com/Raphexion/hawk/main/assets/hawk-light.png" width="320">
  </picture>
</p>

<p align="center">
Hawk is an independent project developed on my own time, with support from
<a href="https://github.com/landfolk">Landfolk</a>. Landfolk provided encouragement,
a strong engineering environment, and AI tooling that helped make this work possible.
The project direction, implementation choices, and any remaining rough edges are my own.
</p>

<p align="center">
If you are interested in AI-assisted software development and thoughtful product engineering,
see <a href="https://github.com/landfolk/jobs">Landfolk Jobs</a>.
</p>

# Hawk

> [!WARNING]
> Hawk is under heavy development. Until a stable release, expect breaking
> changes to APIs, generated code, conventions, and recommended patterns. Hawk
> prioritizes improving the design over backward compatibility.

Hawk is designed for the shape that appears in many backends: Ecto resources with
role-aware reads and writes, a JSON:API surface for clients and integrations, and
LiveView screens for internal administration. Hawk tries to make that repeated
middle layer boring: resource contracts, policies, readers, writers, adapters,
and tests follow one convention instead of being rebuilt per project.

Hawk depends on Ecto, Ecto SQL, Postgrex, and Phoenix (with Phoenix LiveView
and Phoenix Ecto). It does not define or supervise a concrete `Ecto.Repo`.
Applications provide their own Repo modules, database configuration, migrations,
authentication, and supervision tree.

## Installation

Hawk is not published on Hex yet. Install it from GitHub while the API is still
moving quickly:

```elixir
def deps do
  [
    {:hawk, github: "Raphexion/hawk", tag: "v0.7.0"}
  ]
end
```

Then fetch, compile, and run Hawk's contract gate in the host app:

```sh
mix deps.get
mix compile
mix hawk.validate
```

If you are trying Hawk in a fresh Phoenix app, start with one existing Ecto schema
and build the resource siblings around it. Hawk expects the app to own the Repo,
migrations, authentication, endpoint, and router; Hawk owns the reusable resource
boundary on top.

## Golden path

A Hawk resource facade ties the resource parts together and follows convention by default:

```elixir
defmodule MyApp.Courses do
  use Hawk.Resource, model: MyApp.Course
end
```

By convention Hawk expects sibling modules such as `MyApp.Courses.Reader`,
`MyApp.Courses.Policy`, `MyApp.Courses.Writer`, `MyApp.Courses.JsonApi`, and
`MyApp.Courses.LiveView`. A *missing* conventional module emits a compile-time
warning (so a facade can compile before its siblings during incremental edits
or code generation), while a *present but malformed* module still fails fast.
Run `mix hawk.validate` as the authoritative, order-independent gate once the
whole resource set is written — it validates every discovered Hawk resource
in strict mode (missing siblings raise) plus the full adapter contract.
Intentional absence is explicit and disables the corresponding adapter entrypoint:

```elixir
defmodule MyApp.CourseSummaries do
  use Hawk.Resource,
    model: MyApp.CourseSummary,
    json_api: false,
    live_view: false
end
```

The facade generates public reader/writer functions plus `action/4`, and exposes
resource introspection through `__hawk_resource__/1`. For JSON:API-enabled resources,
`json_api_select_fields/2` returns the schema-field projection Hawk will use for a
role and sparse fieldset, giving tests a side-effect-free way to assert visibility
without attaching global repo telemetry. JSON:API rendering discovers
sibling adapter metadata from related models' resource facades, so each resource
has a single source of JSON:API truth. JSON:API controllers generate a stable
`hawk_action/2` entrypoint; at runtime it returns not found when no matching
action module or action exists. Read actions are always available, create/update/delete
are always generated (the writer is a required sibling), and writes are gated by
the policy, not by the controller shape. It also validates adapter contracts
at compile time; JSON:API adapter `source:` entries must point at real model
fields or associations, writable fields must be declared, and LiveView fields /
filters must reference real model fields and declared reader filters.

A Hawk resource has four small modules plus Phoenix-facing helpers:

- `Model` declares the Ecto schema and association resource metadata.
- `Policy` declares who can read/write.
- `Reader` owns filtering, sorting, pagination, and policy-aware preloads; cohesive filter groups may live in `Hawk.Reader.FilterSet` modules.
- `Writer` owns validation and mutations.
- `Actions` is optional and declares imperative JSON:API custom actions under `/-actions/`.
- JSON:API, OpenAPI, LiveView, and Plans helpers are generated from those declarations.

## Core modules

### Model

The model declares the Ecto schema and association resource metadata. The
external JSON:API shape lives in the sibling adapter, not on the model.

```elixir
defmodule MyApp.Course do
  use Hawk.Model

  model "courses" do
    field(:title, :string)
    belongs_to(:school, MyApp.School)
    belongs_to(:teacher, MyApp.Teacher)
    has_many(:grades, MyApp.Grade)
  end
end
```

Association resource metadata (`:policy`, `:reader`, `:resource` opts on
`belongs_to`/`has_many`/`many_to_many`) is still declared at the association
site so Hawk readers preload through the associated resource reader instead
of duplicating preload query logic.

### Resource identity

Hawk assumes a resource's JSON:API `id` and member-lookup key is the model's
`:id` by default. Resources whose backing table has no `:id` — a database
view keyed by another column, a projection, a summary — declare a different
identity instead of working around the assumption in every adapter:

```elixir
defmodule MyApp.CourseGradeSummaries do
  use Hawk.Resource,
    model: MyApp.CourseGradeSummary,
    identity: :course_id
end
```

Drop the surrogate primary key on the model with `primary_key: false`:

```elixir
defmodule MyApp.CourseGradeSummary do
  use Hawk.Model

  model "course_grade_summaries", primary_key: false do
    field(:course_id, :binary_id)
    field(:grade_count, :integer)
    field(:average_score, :float)
  end
end
```

The declared identity drives the JSON:API `id` rendered by `Document`, the
member-lookup filter and short-id UUID range in the controller, and the
LiveView `assign_show`/delete lookup key — so a view-backed resource stops
forcing every adapter to special-case `:id`. Identity is a single field today
(composite keys are a future extension); the field must exist on the model,
enforced at compile time.

Hawk enforces that the identity field *exists* on the model, but uniqueness,
non-nullability, and a UUID index on it are the resource author's
responsibility — the same trust model Hawk already uses for the default `:id`
(primary key). Declare `identity:` on a column that is actually a stable
member key: a non-unique identity makes `show` ambiguous (the reader's `one`
raises on multiple matches), and a non-indexed identity makes the short-id
range query scan. Resources that cannot offer a unique member key should keep
the surrogate `:id`.

`belongs_to` relationship linkage is rendered from the foreign key value, so the
related resource's declared identity must equal the association's `related_key`
(the default `:id`). The common cases satisfy this: a belongs_to to a default
`:id` resource, or to a declared-identity resource whose foreign key is named
after the identity (e.g. `course_id` → a `CourseRosters` resource with
`identity: :course_id`). Divergence fails at compile time with a clear message,
because Hawk renders JSON:API relationship linkage as pure data and cannot load
the related record to read a non-FK identity — model such relationships as an
explicit writer/action workflow instead.

### Policy

```elixir
defmodule MyApp.Courses.Policy do
  use Hawk.Policy

  read do
    role(:system, :all)
    role(:public, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id, :teacher_id])
  end

  write(roles: [:school_admin])
end
```

`public` is anonymous readonly access. It is not system access and still goes
through the resource policy. Policies expose their read declarations for
contract validation, so `ResourceContract` can catch scoped policy filters that
are not declared by the reader. For simple ownership-based writes, pass
`owned_by:` to require model/changeset fields to match authority scopes:

```elixir
write(roles: [:teacher], owned_by: [teacher_id: :teacher_id])
```

Policy matrix tests can use `Hawk.Policy.Assertions` to keep role coverage
compact:

```elixir
import Hawk.Policy.Assertions

assert_read_matrix(MyApp.Courses.Policy, [
  {Hawk.Authority.system(), :all},
  {Hawk.Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12}),
   %{school_id: 7, teacher_id: 12}},
  {Hawk.Authority.new(:teacher, 12, scopes: %{school_id: 7}), :none}
])
```

### Reader

```elixir
defmodule MyApp.Courses.Reader do
  use Hawk.Reader.Resource,
    repo: MyApp.Repo,
    schema: MyApp.Course,
    default_page_size: 100,
    max_page_size: 100

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  sort(:id)
  sort(:title)

  preload(:teacher)
  preload(:grades)
end
```

Readers can extract cohesive search capabilities into resource-specific filter
sets. A filter set owns its filters, attach rules, constants, and private helpers;
the Reader continues to own policy, sorting, pagination, preloads, and its
resource-wide scope:

```elixir
defmodule MyApp.Courses.StudentFilters do
  use Hawk.Reader.FilterSet, schema: MyApp.Course

  attach :student, when_filter: [:student_name], preserves_roots: true do
    join(query, :left, [root: course], student in assoc(course, :students), as: :student)
  end

  filter :student_name do
    fn {:eq, name} -> dynamic([student: student], student.name == ^name) end
  end
end

defmodule MyApp.Courses.Reader do
  use Hawk.Reader.Resource,
    repo: MyApp.Repo,
    schema: MyApp.Course

  filter(:id)
  import_filters(MyApp.Courses.StudentFilters)
  sort(:id)
end
```

Imported sets contribute to the Reader's normal `filter_keys/0`,
`filter_handlers/0`, `coordinate_filters/0`, and `join_plan/0` metadata, so
JSON:API parsing, OpenAPI, policies, and cross-set boolean filter expressions use
the composed contract. Duplicate filter keys and join aliases are rejected
rather than silently overwritten, and a set can only be imported by a Reader for
the same schema. Imported attach rules run in filter-set import order before
resource-local attach rules. As with local Reader attaches, every rule triggered
by the active filter keys is applied before the boolean filter AST is compiled.

Attachments default to `preserves_roots: false`. Hawk rejects a filter when a
non-preserving attachment is active but some satisfiable `OR` path does not
require it, because applying that transformation first could silently remove a
valid result. Mark an attachment `preserves_roots: true` only when it keeps every
root row available to the query, such as a normal left join with no root-narrowing
predicate:

```elixir
attach :student, when_filter: [:student_name], preserves_roots: true do
  join(query, :left, [root: course], student in assoc(course, :students), as: :student)
end
```

Root preservation concerns inclusion, not uniqueness: a to-many left join may
still duplicate roots. A key declared in `when_filter` must semantically require
its attachment whenever that filter can match; custom handlers must not return
`:all` for such a value. If every satisfiable path requires the same attachment,
including through an enclosing policy or forced `AND` filter, a non-preserving
attachment remains valid. Sort-triggered attachments are Reader-owned, but
sorting does not make an otherwise unsafe filter attachment safe: the same
transformation still runs before the `OR` predicate and may remove roots. See
[Understanding `preserves_roots`](guides/preserves-roots.md) for a
beginner-oriented explanation, SQL examples, edge cases, and a testing
checklist.

Filter sets are composed dynamically from one metadata snapshot per set. In a
Phoenix development server, changing only a filter-set module is therefore
visible to the next Reader call without caching stale declarations in the
Reader. The generated handlers use external module captures so helpers remain
local to the set and normal code reloading can replace their implementation.

For focused tests, apply a set to an existing root query:

```elixir
query =
  MyApp.Course
  |> from(as: :root)
  |> MyApp.Courses.StudentFilters.apply_to(%{student_name: "Ada"})

assert [%MyApp.Course{}] = MyApp.Repo.all(query)
```

`apply_to/2` validates against only that set and applies its attach rules and
filter compiler. It deliberately does not apply Reader policy, pagination,
preloads, default sorting, or resource scope; those remain Reader and transport
integration-test responsibilities. Readers still compose the complete filter
AST before compilation, preserving `AND`/`OR` expressions across sets.

Nested includes such as `include=grades.student` are turned into nested Ecto
preloads where every layer uses that resource's own reader and policy. Include
paths use external JSON:API relationship names; `source:` aliases are translated
to internal preload keys at every path segment, matching the generated OpenAPI
values. Opening `courses` does not accidentally open `grades` or `students`.
Compound documents
de-duplicate included resources and omit any resource already present in primary
`data`, including when an include path cycles back to the root.

Every reader `preload/1` must be a relationship exposed by the resource's
JSON:API adapter — `mix hawk.validate` rejects a preload with no matching
relationship. A reader cannot preload an association it does not expose, so the
reader and the external surface stay a single set of relationships.

Readers apply `default_page_size` when the caller does not request a page size
and reject requests above `max_page_size`. Both default to `100` and can be
overridden per resource. Collection JSON:API responses include `meta.page` with
`size`, `number`, and returned `count`. Hawk accepts `page[size]` / `page[number]`
and the shorthand `page_size` / `page_number` query parameters. Direct
`has_many` related-resource and relationship-linkage endpoints use the related
reader's pagination settings too, so `GET /courses/:id/grades` and
`GET /courses/:id/relationships/grades` do not preload an unbounded child
collection. When a client passes `page[total]=true`, JSON:API controllers also
run the same authorized, unpaginated reader query as a count and include
`meta.page.total_count`.

### Writer

```elixir
defmodule MyApp.Courses.Writer do
  use Hawk.Writer.Resource,
    model: MyApp.Course,
    repo: MyApp.Repo,
    policy: MyApp.Courses.Policy

  create do
    defaults(registration_state: "draft")
    cast([:title, :teacher_id, :registration_state])
    validate_required([:title, :teacher_id])
    validate(&reject_reserved_title/1)
  end

  update do
    cast([:title, :teacher_id])
    validate(&reject_reserved_title/1)
  end

  delete(:default)

  defp reject_reserved_title(context) do
    case Ecto.Changeset.get_change(context.changeset, :title) do
      "Forbidden" -> {:error, :title, "is reserved"}
      _title -> :ok
    end
  end
end
```

`Hawk.Writer.Resource` generates `change_create/2` / `create/2` and
`change_update/3` / `update/3` from the same pipelines. `change_*` functions
return non-persisting changesets with `action: :validate`, which is the boundary
LiveView form helpers use for live validation errors. `create/2` and `update/3`
keep owning persistence through the repository boundary. `delete(:default)`
generates a policy-checked `delete/2` that crosses the same repository boundary.

A read-only resource still keeps a writer sibling and declares `write(:never)`
in its policy — writes are gated by the policy, not by omitting the writer, so a
mutation attempt returns `403` instead of a `404`/`500` from a missing delegate.
The `create`/`update`/`delete` blocks are required for that `403` path; the `cast`
field lists keep the writer ready if the policy is later relaxed. Run
`mix hawk.gen.resource MyApp.Things MyApp.Thing --read-only` to scaffold the
whole set.

Supported create/update DSL steps are `defaults/1`, `cast/1`, `validate_required/1,2`,
`validate/1`, `validate_changeset/1`, and `constraint/2`. Custom `validate/1` functions
can be reused in create and update pipelines when domain validation is not just
standard Ecto changeset validation. Hand-written writers can expose the same form
boundary with `change_create/2` and `change_update/3` when they need custom
pipelines.

`constraint/2` is the one-step way to declare the most common database constraints
without the `validate_changeset(fn cs -> ... end)` indirection. It desugars to the
matching `Ecto.Changeset` constraint validator and renders through the error
pipeline at the external JSON:API pointer:

```elixir
create do
  cast([:email, :user_id])
  validate_required([:email])
  constraint(:unique, :email, name: :email_user_id_unique)
  constraint(:foreign_key, :user_id, name: :enrollments_user_id_fkey)
end
```

`kind` is one of `:unique`, `:foreign_key`, `:assoc`, `:check`, or `:exclusion`;
`opts` are passed straight through to the Ecto constraint function.

### Actions

Optional imperative actions live beside `Reader` and `Writer` in `Actions.ex`.
`Actions` is an orchestration layer above them: it should compose reads and
writes through resource readers and writers, passing the caller's authority
straight through. There is no separate action-level policy.

> [!WARNING]
> Action handlers are trusted application code. Hawk dispatches the handler and
> passes its authority, but cannot enforce how the handler uses them. Authors are
> responsible for routing every protected read and write through the appropriate
> policy-aware Reader or Writer with that authority. Direct Repo calls and other
> side effects are outside Hawk's authorization guarantees.

Actions are exposed under `/-actions/` and keep command-style endpoints
separate from CRUD routes while staying JSON:API-compliant by accepting
parameters in `meta`.

```elixir
defmodule MyApp.Courses.Actions do
  use Hawk.Actions

  alias MyApp.Courses.Writer

  action "open-registration",
    doc: "Open course registration.",
    params: [
      seat_count: [type: :integer, doc: "Seats available immediately.", example: 30],
      waitlist_count: [type: :integer, doc: "Waitlist capacity.", example: 10]
    ]

  def open_registration(course, params, authority) do
    Writer.open_registration(course, params, authority)
  end
end
```

Route action requests to the generated controller `hawk_action/2` function, for
example. The resource facade dispatches through `<Resource>.action/4`; it does
not generate one public function per action.

```elixir
post "/courses/:id/-actions/:action", CourseController, :hawk_action
```

Request shape:

```json
{
  "meta": {
    "seat_count": 30,
    "waitlist_count": 10
  }
}
```

The top-level `meta` object is required, including for actions with no declared
parameters (`{"meta": {}}`). Missing or non-object `meta` returns `400`; the
OpenAPI request schema carries the same requirement.

#### Two-phase actions: `build` for validate-without-commit

An action that composes multiple writers can opt into a validate phase by
declaring `build: true` (or `build: :fn_name`) in `action/2` and writing a
`build_<handler>/3` function that returns a `Hawk.Multi` of facade-call steps.
Hawk then generates `<handler>_change/3` (validate without committing) and
`<handler>_run/3` (commit) as projections of that one `build_<handler>/3`, so
the two phases cannot drift — the same shape that keeps a writer's
`change_create`/`create` in sync, lifted to a batch.

```elixir
defmodule MyApp.Courses.Actions do
  use Hawk.Actions

  alias MyApp.{Courses, Grades}

  action "submit-grade",
    doc: "Create a grade and rename the course in one transaction.",
    build: true,
    params: [
      score: [type: :integer, doc: "Numeric grade.", example: 7],
      student_id: [type: :string, doc: "Student receiving the grade."]
    ]

  def build_submit_grade(course, params, authority) do
    Hawk.Multi.new()
    |> Hawk.Multi.create(:grade, Grades, %{score: params.score, student_id: params.student_id, course_id: course.id, school_id: course.school_id}, authority)
    |> Hawk.Multi.update(:course, Courses, course, %{title: course.title <> " (graded)"}, authority)
  end
end
```

`<handler>_change/3` returns a map of step name to non-persisting changeset
(via `Hawk.Multi.to_changesets/1`); `<handler>_run/3` commits the whole batch
in one transaction (via `Hawk.Multi.execute/2`). A Multi deliberately supports
one Repo only: every resource step must use the Repo passed to `execute/3`, and
Hawk raises before execution if they differ. Application-owned `run/3` callbacks
must honor the same prerequisite because Hawk cannot inspect their side effects.
`Hawk.Actions.dispatch/5` routes a two-phase action's commit to
`<handler>_run/3` automatically.

JSON:API and LiveView share the same action: `POST /-actions/submit-grade`
commits, and `POST /-actions/submit-grade` with `dry-run: true` validates and
returns a JSON:API error document without committing. In a LiveView,
`hawk_validate_action/6` drives live form validation and `hawk_action/6`
commits, returning the full results map (every step's model) to an `on_success`
callback.

A multi containing `:action` or `:run` steps cannot be validated without
committing (their effects depend on execution), so `to_changesets/1` raises for
them. An action built around such steps is **run-only**: keep the hand-written
`<handler>/3` (no `build:`), and the LiveView validates what it can from the
underlying writers' `change_*` directly. The contract accepts that some
actions are run-only and cannot be live-validated.

## Authority

Hawk does not authenticate users itself. Apps can use the small session/assign
convention helpers to carry an already-resolved authority through controllers and
LiveViews:

```elixir
authority = MyAppWeb.Auth.authority_for(conn)
conn = Hawk.Authority.Plug.call(conn, resolver: fn _conn -> authority end)

session_authority = Hawk.Authority.Session.dump(authority)
authority = Hawk.Authority.Session.authority_or_public(session)
```

`Hawk.PhoenixAuth` is the phx.gen.auth-specific bridge. In Plug pipelines it can
read an existing `current_scope` or a URL-safe Base64 Bearer session token,
convert that scope to a Hawk authority, and assign `:hawk_authority` for JSON:API
controllers. In LiveView `on_mount`, use it after the generated `UserAuth` hook
has assigned `current_scope`.

`Hawk.Authority.Plug` / `Hawk.Authority.Session` are lower-level generic helpers
for apps that are not using the phx.gen.auth scope shape. JSON:API controllers
read their `:hawk_authority` assign directly. Missing authority falls back to
readonly public access, not system access.

## Adapters

### JSON:API adapter

New resources should keep JSON:API exposure in a sibling adapter module:

```elixir
defmodule MyApp.Courses.JsonApi do
  use Hawk.JsonApi.Resource

  type("courses")
  doc("A course taught by a teacher.")

  attribute(:title,
    writable: true,
    doc: "Human-readable course title.",
    example: "Math"
  )

  attribute(:slug,
    source: :public_slug,
    creatable: true,
    updatable: false
  )

  relationship(:teacher,
    writable: true,
    doc: "The teacher responsible for the course.",
    example: %{type: "teachers", id: "..."}
  )

  visibility do
    role(:public, hide: [:slug])
  end
end
```

Field visibility rules are subtractive: the adapter declares the full resource
shape once, and each role may only remove declared attributes or relationships
with `hide:`. Hawk applies the same visibility rules when parsing sparse
fieldsets/includes, rendering JSON:API documents, and selecting root query
columns, so hidden schema fields are not read just to be discarded later. Visible
computed attributes should declare their `source:` when they depend on a backing
schema field.

`writable: true` means both creatable and updatable. Use `creatable:` and
`updatable:` when create/update capabilities differ. `source:` maps the external
JSON:API name to the internal model/writer attr for both rendering and request
payloads. Read-only relationships can expose normal Ecto associations, including
`many_to_many` projections over internal join schemas. Writable relationships
must be `belongs_to` associations because Hawk maps them to the owning foreign
key passed into the writer. Mutating `has_many`, `has_one`, or `many_to_many`
relationships should be modeled as explicit writer/action workflows.

### JSON:API controller

When the controller points at a `Hawk.Resource` facade, Hawk infers the model from the resource:

```elixir
defmodule MyAppWeb.CourseController do
  use Hawk.JsonApi.Controller,
    resource: MyApp.Courses,
    public: true
end
```

The backing model is resolved from the facade; the controller does not accept
a `:model` opt.

Responses use the exact JSON:API media type `application/vnd.api+json` without a
`charset` parameter. When a request sends `Content-Type`, it must use that media
type with only the JSON:API `ext`/`profile` parameters; Hawk returns `415` for an
unsupported media type or parameter. When a request sends `Accept`, it must allow
JSON:API directly or through a wildcard; Hawk returns `406` when no acceptable
media range remains.

Generated controller modules implement the Phoenix controller/Plug contract, so
they can be targeted directly by Phoenix routes without a host-application
adapter.

Generated actions follow resource capabilities:

- `index/2`
- `show/2`
- `create/2` (the writer is a required sibling; writes are gated by the policy)
- `update/2` (the writer is a required sibling; writes are gated by the policy)
- `delete/2` (the writer is a required sibling; writes are gated by the policy)
- `relationship/2` for `GET .../:id/relationships/:relationship`
- `related/2` for `GET .../:id/:relationship`
- `hawk_action/2` for `POST .../:id/-actions/:action`

JSON:API update documents must include both `data.type` and `data.id`; the body
ID must match the full UUID in the request path. Hawk rejects missing or
conflicting update identity with `400` rather than silently ignoring it.

`Hawk.JsonApi.Routes.routes/2` returns the same capability-aware route specs for
framework/router integration:

```elixir
Hawk.JsonApi.Routes.routes(MyApp.Courses, path_prefix: "/api/v1")
```

Routers can use the macro adapter to emit ordinary `get/3`, `post/3`, `patch/3`,
and `delete/3` calls from those specs:

```elixir
import Hawk.JsonApi.Router

hawk_json_api MyApp.Courses, MyAppWeb.CourseController,
  path_prefix: "/api/v1"
```

The macro validates that every emitted route points at an exported controller
action, so capability drift fails while the router compiles.

#### Errors

Controller errors use canonical `%Hawk.Error{}` structs internally and render
JSON:API documents at the adapter boundary:

- invalid include/filter/sort/page: `400`
- invalid request document shape, resource type, attributes, or relationships: `400`
- authorization failure: `403`
- missing record, custom action, or relationship endpoint: `404`
- validation failure: `422`
- successful deletion: `204 No Content` with an empty body

Validation error `source.pointer` values map back to the external JSON:API name
a client sent. An attribute declared with `source:` (e.g. `attribute(:name,
source: :title)`) renders a validation error at `/data/attributes/name`, not the
internal `/data/attributes/title`; a `belongs_to` foreign key renders at
`/data/relationships/{external}`. `Hawk.JsonApi.Schema.external_pointer/2` owns
that reverse mapping.

#### Short IDs

`show/2` accepts either a full UUID or a short ID, defined as the first
8 hexadecimal characters of a UUID. Short IDs are a human convenience for simple
read-only member lookups only:

- `GET /courses/:id` accepts full UUIDs and short IDs.
- mutations (`PATCH`, `DELETE`), custom actions, relationship endpoints, and
  request body relationship identifiers require full UUIDs.

Hawk keeps this deliberately prudent because short IDs are prefixes, not stable
identifiers. A short ID lookup resolves through an indexed UUID range, bounded to
2 rows: no match returns `404`, exactly one match returns that resource, and
multiple matches return `400` with an ambiguous-prefix error. Mutating through a
prefix would make ambiguity dangerous, so write paths require full UUIDs.

The OpenAPI contract reflects this split: the `show` `id` parameter documents
that it accepts short IDs, while `PATCH`/`DELETE`/`-actions`/relationship/
related operations declare `id` with `format: "uuid"`, so clients know which
lookups are lenient and which are strict.

The range lookup is designed for PostgreSQL UUID primary keys: Hawk turns the
8-character prefix into a lower/upper UUID bound and queries the `id` field with
`>=` / `<=`, so the normal btree UUID index can be used. Hawk intentionally avoids
`id::text LIKE 'prefix%'`, which is easier to write but can force scans or require
a separate functional index.

#### Query parameters

Hawk rejects unknown query parameter names made only from lowercase ASCII letters
with `400`; JSON:API reserves that namespace for specification parameters. Host
applications can use implementation-specific parameter names containing a
non-letter separator (for example `analytics_mode`) and process them before Hawk;
Hawk ignores those custom parameters.

Collection requests accept JSON:API's ordered, comma-separated sort syntax.
Every field must be declared by the Reader; prefix a field with `-` for descending
order:

```text
/api/v1/courses?sort=title,-id
```

Collection requests support filters explicitly declared by the Reader. Declaring
an integer schema field once keeps the query surface deliberate while enabling
exact and range filtering automatically:

```elixir
defmodule MyApp.Courses.Reader do
  use Hawk.Reader.Resource,
    repo: MyApp.Repo,
    schema: MyApp.Course

  filter(:credit_count)
end
```

Resource callers use bare values for equality and operator tuples for comparisons:

```elixir
MyApp.Courses.all(authority: authority, filter: %{credit_count: 2})
MyApp.Courses.all(authority: authority, filter: %{credit_count: {:gt, 5}})
MyApp.Courses.all(authority: authority, filter: %{credit_count: {:lt, 3}})
```

The equivalent JSON:API query parameters are:

```text
/api/v1/courses?filter[credit_count]=2
/api/v1/courses?filter[credit_count][gt]=5
/api/v1/courses?filter[credit_count][lt]=3
```

`gt`/`lt` are strict comparisons; `gte`/`lte` are inclusive. Integer filters
also support `eq`, `neq`, `in`, and `not_in`. Hawk casts query-string operands
to integers before building the Ecto query, returns `400` for invalid integer
values, and rejects text-only operators such as `like`/`ilike` on integer fields.
Filter names are Reader keys; JSON:API attribute `source:` aliases do not rename
the filter contract. Custom `filter/2` handlers continue to own their operand
semantics. The same nested query shape applies to other declared filters:

```text
/api/v1/courses?filter[school_id]=school-1&filter[active][eq]=true&filter[name][ilike]=%25math%25
```

#### Coordinate near filters

Coordinate filtering is an opt-in read capability over an indexed PostGIS
`geography(Point, 4326)` column. Hawk does not make PostGIS mandatory for
resources that do not declare coordinate filters. Applications using the
capability add Hawk's optional GeoPostGIS dependency directly:

```elixir
{:geo_postgis, "~> 3.7"}
```

Configure the Postgrex extension as described by
[GeoPostGIS](https://geo-postgis.hexdocs.pm/readme.html):

```elixir
Postgrex.Types.define(
  MyApp.PostgresTypes,
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)

config :my_app, MyApp.Repo, types: MyApp.PostgresTypes
```

The host application owns the PostGIS extension, geography column, and GiST
index. Keep the column itself as geography — Hawk deliberately does not cast the
indexed column inside the query:

```elixir
execute "CREATE EXTENSION IF NOT EXISTS postgis"
execute "ALTER TABLE campuses ADD COLUMN location geography(Point, 4326)"
execute "CREATE INDEX campuses_location_gist_index ON campuses USING GIST (location)"
```

Declare the Ecto field and an explicit Reader maximum:

```elixir
# Model. Geo.Point coordinates use {longitude, latitude} order.
field(:location, Geo.PostGIS.Geometry)

# Reader
filter(:location, type: :coordinates, max_radius_meters: 100_000)
```

Resource callers use the `near` operator:

```elixir
MyApp.Campuses.all(
  authority: authority,
  filter: %{
    location:
      {:near, %{lat: 55.6761, lng: 12.5683, radius_meters: 10_000}}
  }
)
```

The equivalent JSON:API request is:

```text
/campuses?filter[location][near][lat]=55.6761&filter[location][near][lng]=12.5683&filter[location][near][radius_meters]=10000
```

Hawk validates latitude (`-90..90`), longitude (`-180..180`), a positive radius,
the declared maximum, required keys, and unknown keys before querying. Invalid
JSON:API input returns `400`; rows with `null` locations do not match. `near`
filters with PostGIS
[`ST_DWithin`](https://postgis.net/docs/en/ST_DWithin.html), whose geography
radius is measured in meters and whose bounding-box check can use the GiST index.
It filters only — it does not implicitly sort by distance or expose distance in
the response.

This slice is intentionally read-only. The host application owns coordinate
writes and JSON:API attribute serialization, including construction of
`%Geo.Point{coordinates: {lng, lat}, srid: 4326}` values.

Sparse fieldsets use standard JSON:API `fields[type]` params on collection,
member, and related-resource responses. Fieldsets apply independently per
resource type, including included resources:

```text
/api/v1/courses?include=teacher&fields[courses]=title,teacher&fields[teachers]=name
```

### LiveView adapter

LiveView exposure belongs in a sibling adapter too. Hawk handles data plumbing;
your templates still own the markup.

```elixir
defmodule MyApp.Courses.LiveView do
  use Hawk.LiveView.Resource

  as(:course)
  plural_as(:courses)

  index do
    filter(:teacher_id)
    search(:title, operator: :ilike)
    sort(:id)
    sort(:title)

    table do
      column(:title, label: "Course")
      column(:registration_state)
      column(:teacher_name, label: "Teacher", source: [:teacher, :name])
    end
  end

  show do
    field(:title)
    field(:registration_state, label: "State")
    field(:teacher_name, label: "Teacher", source: [:teacher, :name])
  end

  create_form do
    field(:title, label: gettext("Course"))
    field(:teacher_id, label: dgettext("courses", "Teacher"))
  end

  update_form do
    field(:title, label: gettext("Course"))
  end
end
```

`use Hawk.LiveView, resource: MyApp.Courses` reads `as` and `plural_as` from
the LiveView adapter when present, then falls back to model-based convention.
The default `"hawk:validate"`, `"hawk:save"`, and `"hawk:delete"` event
handlers are generated from the writer sibling (which is always present); a
read-only resource keeps the writer and refuses writes in its policy, so the
handlers exist but never persist. Show pages can load by natural keys when the
reader declares the filter:

```elixir
socket = CourseLive.assign_show(socket, authority, short_id, lookup: :short_id)
```

LiveView index params are caller-provided narrowing/presentation only;
pass them as `params: %{"filter" => ..., "search" => ..., "sort" => ..., "page" => ...}`
to `assign_index/3`. Hawk accepts only filters/searches/sorts declared in the
LiveView adapter and validated against the Reader. Search declarations can turn a
text field into an `:ilike` filter, so `%{"search" => %{"title" => "histo"}}`
becomes `%{title: {:ilike, "%histo%"}}`. Sort and search changes reset the page
number to `1`; page changes keep the current query state. Policies remain the
security boundary and are shared with JSON:API reads.

#### Preloads are declared by `source:` paths

A `column` or `field` (index and show) accepts a `source:` path to reach a
field through an association: `column(:teacher_name, source: [:teacher, :name])`.
The LiveView adapter declares the shape; the reader owns loading (it must
`preload` the association); `mix hawk.validate` enforces that every association a
`source:` path reaches is a declared reader preload — the same invariant that
holds reader preloads to JSON:API relationships, applied to the LiveView
adapter. `assign_index` and `assign_show` derive the preloads from the adapter,
so there is no runtime `preloads:` option to keep in sync; the caller-supplied
`preloads:` opt is rejected.

A single-element path (`field(:students, source: [:students])`) declares a
whole association to preload and display (typically a collection the template
iterates). After loading, Hawk verifies declared source-path associations are
actually available before rendering. If a policy-aware preload filters out a
`belongs_to` association whose foreign key is set, Hawk raises a targeted
LiveView error that names the field, source path, associated resource, and role
instead of letting the template fail later with `Ecto.Association.NotLoaded` or
`nil`.

A deeper path whose leaf is an association
(`field(:grades, source: [:grades, :student])`) produces a nested preload
(`grades: [:student]`) for a collection whose elements reach their own
associations.

Form fields (`create_form`/`update_form`) do not accept `source:` paths — they
bind to root-model attrs the writer casts, mirroring JSON:API's
writable-`belongs_to`→FK rule. A read-only display beside a form uses a `show`
field, not a form field.

### LiveView helpers

For simple single-resource pages:

```elixir
defmodule MyAppWeb.CourseIndexLive do
  use Hawk.LiveView,
    resource: MyApp.Courses
end
```

When `resource:` is a `Hawk.Resource` facade, Hawk infers the singular/plural assign names from the model (from the LiveView adapter `as`/`plural_as` when declared, else the model name). Pass `as:`/`plural_as:` only to override those inferred names.

This provides helpers such as `assign_index/3`, `assign_show/4`, keyed form
helpers such as `assign_new_form/2`, and default `"hawk:validate"`,
`"hawk:save"`, and `"hawk:delete"` event handlers. The form handlers route live
validation and persistence through the writer boundary and map errors into
LiveView-friendly assigns.

A boring generated form can stay almost empty:

```elixir
defmodule MyAppWeb.CourseLive do
  use MyAppWeb, :live_view

  use Hawk.LiveView,
    resource: MyApp.Courses

  def mount(_params, _session, socket) do
    {:ok, assign_new_form(socket, current_authority(socket))}
  end
end
```

```heex
<.form for={@course_form} phx-change="hawk:validate" phx-submit="hawk:save">
  <.input field={@course_form[:title]} />
  <.button>Save</.button>
</.form>
```

When the app needs custom flow, keep Hawk's helpers and own the events:

```elixir
defmodule MyAppWeb.CourseLive do
  use MyAppWeb, :live_view

  use Hawk.LiveView,
    resource: MyApp.Courses,
    events: false

  def mount(_params, _session, socket) do
    {:ok, assign_new_form(socket, current_authority(socket))}
  end

  def handle_event("hawk:validate", params, socket), do: hawk_validate(params, socket)

  def handle_event("hawk:save", params, socket) do
    hawk_save(params, socket,
      on_success: fn socket, course ->
        push_patch(socket, to: ~p"/courses/#{course.id}")
      end
    )
  end
end
```

For richer workspace pages that coordinate related resources:

```elixir
defmodule MyAppWeb.CourseWorkspaceLive do
  use Hawk.LiveView.Page,
    resources: [
      course: [resource: MyApp.Courses],
      students: [resource: MyApp.Students],
      grades: [resource: MyApp.Grades]
    ],
    sections: [
      basics: [label: "Basics", path: "/courses/:id"],
      students: [label: "Students", path: "/courses/:id/students"],
      grades: [label: "Grades", path: "/courses/:id/grades"]
    ]
end
```

`hawk_page_sections/0` exposes `%{id:, label:, path:}` maps for app-owned
workspace/tab navigation. Hawk owns the metadata; your LiveView owns the markup.

Then load the page with per-resource read specs:

```elixir
CourseWorkspaceLive.assign_page(socket, authority,
  course: {:one, filter: %{id: course_id}, preloads: [:teacher]},
  students: {:all, filter: %{school_id: school_id}},
  grades: {:all, filter: %{course_id: course_id}, preloads: [:student]}
)
```

Each resource still goes through its own reader and policy. The page helper just
composes the reads and shared mutation events; it does not create a new bypass
around Hawk's authorization model.

When the resource writer exposes form changeset helpers, `use Hawk.LiveView`
also generates keyed form helpers:

```elixir
socket = CourseLive.assign_new_form(socket, authority)
socket = CourseLive.assign_edit_form(socket, course, authority)
```

These assign `:course_form` and `:course_form_fields` by default and track form
state under `:hawk_form_states`. `create_form` fields are assigned for new forms;
`update_form` fields are assigned for edit forms. Read-only/admin display forms can use
`assign_read_form(socket, course)`; it assigns the update-form fields when present,
falls back to show fields, and records `mode: :read` without generating save or
validation behavior. Label metadata can use
`gettext("...")` or `dgettext("domain", "...")` descriptors without translating
at compile time. Hawk does not own UI translation; by default `hawk_field_label/1`
returns the descriptor's message id or a humanized field name. Apps that want a
shared resolver can opt in with a small label module:

```elixir
defmodule MyAppWeb.HawkLabels do
  import MyAppWeb.Gettext

  def field_label({:gettext, msgid}), do: gettext(msgid)
  def field_label({:dgettext, domain, msgid}), do: dgettext(domain, msgid)
end

use Hawk.LiveView,
  resource: MyApp.Courses,
  label_resolver: MyAppWeb.HawkLabels
```

```heex
<.input field={@course_form[field.name]} label={hawk_field_label(field)} />
```

For read/show surfaces, `hawk_field_value(model, field)` resolves `:source` and
applies optional formatter functions, so templates can keep display projections
near the LiveView adapter metadata.

Hawk also generates `hawk_validate/2` and `hawk_save/2,3`.
Default `handle_event("hawk:validate", ...)`, `handle_event("hawk:save", ...)`,
and `handle_event("hawk:delete", ...)` clauses call those helpers unless
`events: false` is set. Delete events accept only the resource `id`; authority
is resolved from the server-owned `:hawk_authority` socket assign (falling back
to public authority), never from browser event parameters. `hawk_validate/2`
rebuilds a non-persisting validation changeset through `change_create/2` or
`change_update/3`, then assigns a Phoenix `to_form(changeset, as: :course)` on a
real `Phoenix.LiveView.Socket`. `hawk_save/2` uses the same state to call
`create/2` or `update/3`; validation failures keep the keyed form assigned with
`action: :insert` or `:update`, authorization failures assign `:hawk_error`, and
successful saves assign the saved model under `:course`. Use `hawk_save/3` with
`on_success: fn socket, course -> ... end` when the app needs post-save behavior
such as navigation while still reusing Hawk's save plumbing. Form helpers
build a `Phoenix.HTML.Form` through `to_form/2` on a real
`Phoenix.LiveView.Socket`.

Known server-side values can be forced into a form without trusting hidden client
inputs:

```elixir
socket =
  CourseLive.assign_new_form(socket, authority,
    forced_attrs: %{teacher_id: current_teacher.id},
    hidden: [:teacher_id]
  )
```

`forced_attrs` are merged after client params during validation and save, so the
server value wins even if the browser submits a different `teacher_id`. `hidden`
removes fields from the assigned form-field metadata; the writer remains the
final acceptance boundary.

## Real-time updates

Hawk can push a write from one source (the JSON:API controller, another
LiveView, a background job) into every LiveView screen that shows the same
resource, without a reload. Real-time is **opt-in per writer** and built over
the host application's own `Phoenix.PubSub` — Hawk does not start or supervise a
PubSub, just as it does not own your `Ecto.Repo`.

### Opting in

Declare `:pubsub` on the writer. Every successful `create`/`update`/`delete`
then broadcasts a `Hawk.PubSub.Event`:

```elixir
defmodule MyApp.Grades.Writer do
  use Hawk.Writer.Resource,
    model: MyApp.Grade,
    repo: MyApp.Repo,
    policy: MyApp.Grades.Policy,
    pubsub: MyApp.PubSub          # add this line
  ...
end
```

The optional `:topics` opt selects a topic strategy (defaults to
`Hawk.PubSub.DefaultTopics`). Omit `:pubsub` for no broadcast.

### What is broadcast

A `Hawk.PubSub.Event` — **not** the model. Each subscriber re-queries through
its *own* authority, so the resource `read_filter/1` is never bypassed. The
writer's view of the record is never pushed to readers; a viewer whose role
hides the record re-queries and simply does not see it.

Broadcasts fire **after** the write's transaction commits, so a cross-process
subscriber re-querying immediately sees the committed row. A direct broadcasting
Writer must own the outer transaction; Hawk rejects calling it inside an
application-owned `Repo.transaction/1` because it cannot observe that outer
transaction's commit. Compose transactional Hawk writes with `Hawk.Multi`
instead: it queues its writers' events and flushes them only after the transaction
it owns commits, while failed multis and plan previews discard the queue. This
prevents both premature and silently missing events. A no-op update (empty
changes) and an unauthorized/invalid write do not broadcast.

### LiveView one-liner

Subscribe is **routing**, not authorization: it picks which channel a screen
joins from the socket's `assigns`. Authorization happens later, in `refresh/3`,
which re-queries through the socket's authority. Set the routing context
(e.g. the current school id) in `mount`, subscribe, then match the event in
`handle_info` and call `Hawk.LiveView.refresh/3`:

```elixir
defmodule MyAppWeb.GradesLive do
  use MyAppWeb, :live_view
  use Hawk.LiveView, resource: MyApp.Grades

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_school_id, current_school(socket))
      |> assign(:hawk_authority, current_authority(socket))

    {:ok, Hawk.LiveView.subscribe(socket, MyApp.Grades)}
  end

  def handle_info(%Hawk.PubSub.Event{resource: MyApp.Grades}, socket) do
    {:noreply, Hawk.LiveView.refresh(socket, MyApp.Grades)}
  end
end
```

`subscribe/2` reads `:pubsub` and the topic strategy from the resource, so the
author passes only the resource. `refresh/3` detects the current screen (index
vs show) from existing assigns and re-runs the read through the socket's
authority (from `opts[:authority]`, the `:hawk_authority` assign, or
`Hawk.Authority.public()` as a fallback). Index refreshes preserve both the
interactive filter/page/sort state and caller-supplied base reader options such
as fixed filters or context. A delete degrades gracefully: the
index no longer includes the record, and a show screen re-assigns `:hawk_error`
because the record is gone.

### Topics and tenant isolation

The default topic strategy (`Hawk.PubSub.DefaultTopics`) broadcasts to a shared
resource topic and a per-record instance topic:

- Resource topic — `"hawk:grades"` — every create/update/delete.
- Instance topic — `"hawk:grades:<identity-value>"` — changes to one record.

That shared resource topic reaches every subscriber. For a multi-tenant SaaS,
that means a write at tenant A makes a LiveView at tenant B re-query — no data
leaks (B's `read_filter` scopes its own results), but the write crosses tenants
unnecessarily.

The `:topics` opt is the escape hatch. Implement `Hawk.PubSub.TopicStrategy`
(two callbacks: `broadcast_topics/3` from the model, `subscribe_topics/2` from
the socket assigns) and scope topics by tenant:

```elixir
defmodule MyApp.PubSub.Topics do
  @behaviour Hawk.PubSub.TopicStrategy

  @impl true
  def broadcast_topics(_resource, _operation, model) do
    ["hawk:grades:school:#{model.school_id}"]
  end

  @impl true
  def subscribe_topics(_resource, assigns) do
    ["hawk:grades:school:#{assigns[:current_school_id]}"]
  end
end
```

Then wire it on the writer:

```elixir
use Hawk.Writer.Resource,
  model: MyApp.Grade,
  repo: MyApp.Repo,
  policy: MyApp.Grades.Policy,
  pubsub: MyApp.PubSub,
  topics: MyApp.PubSub.Topics
```

Both sides live in one app-owned module, so the broadcast and subscribe topics
stay in lockstep — there is no two-sided Hawk split to drift. A teacher at
school A subscribes to `hawk:grades:school:<A>` and only receives their own
school's writes: no wasted re-query, no cross-tenant delivery. A cross-tenant
role (e.g. a principal with `:all`) can subscribe to a different topic or the
bare resource topic.

The broadcast side reads the tenant off the **model**; the subscribe side
reads it off the **socket assigns** (the screen's routing context, set in
`mount`). Authorization stays in `refresh/3` through the socket's authority —
subscribe never authorizes.

### Authority and existence visibility

The shared resource topic (the default strategy) lets every subscriber learn
*that* a write occurred and the changed record's identity value, even when the
subscriber's `read_filter/1` would hide that record. The visible **data** never
leaks — a subscriber whose authority hides the record re-queries and does not
see it — but the **event metadata** (a write happened, plus an opaque id) is
observable to everyone on the topic. A tenant-scoped topic strategy removes
this for the multi-tenant case: subscribers only join their own tenant's topic.

### Custom delete helpers

The generated `delete(:default)` and the generated `create`/`update` already
broadcast. If you write a `delete/2` by hand, inherit broadcast by passing the
writer's own options to the boundary:

```elixir
def delete(%MyApp.Grade{} = grade, authority) do
  Hawk.MutationContext.delete(grade, authority)
  |> Hawk.MutationContext.validate_policy(&MyApp.Grades.Policy.delete?/1)
  |> Hawk.RepositoryBoundary.delete(MyApp.Repo, __hawk_writer_opts__())
end
```

## OpenAPI

```elixir
defmodule MyAppWeb.OpenApiController do
  use Hawk.OpenApi.Controller,
    title: "My API",
    version: "1.0.0",
    path_prefix: "/api/v1",
    resources: [MyApp.Courses, MyApp.Grades],
    servers: [%{url: "https://api.example.com"}],
    security: [%{"bearerAuth" => []}],
    security_schemes: %{
      bearerAuth: %{type: "http", scheme: "bearer", bearerFormat: "JWT"}
    }
end
```

The controller serves the spec as `application/json` (an OpenAPI document is
JSON, not a JSON:API resource). It passes `:title`, `:version`, `:path_prefix`,
`:license`, `:servers`, `:security`, and `:security_schemes` straight through to
`Hawk.OpenApi.spec/2`.
`Hawk.OpenApi.spec/2` takes `Hawk.Resource` facades. Facades with `json_api: false`
are omitted because this OpenAPI generator documents the JSON:API surface only.
The controller exposes `spec/0` and `show/2`. The specification is composed from
Hawk resource declarations and the same `Hawk.JsonApi.Routes` route specs used for
capability-aware routing. Response schemas require the JSON:API members Hawk
always emits (`data`, resource `type`/`id`, and error-document `errors`) so
generated clients do not type them as optional. Success documents also describe
optional top-level `links`, compound-document `included`, pagination `meta.page`,
resource links, and relationship links using reusable component schemas. The
spec also includes JSON:API adapter schemas, request bodies, error documents,
`406`/`415` media-type negotiation responses, sort parameters, pagination
parameters, valid include paths, declared
`/-actions/` operations, relationship routes, the optional `path_prefix`, and
optional resource organization metadata.

Custom actions automatically appear in the OpenAPI/Swagger spec as `POST`
operations under paths such as `/api/v1/courses/{id}/-actions/open-registration`.
Their request bodies are documented as JSON:API documents with a `meta` object,
and successful responses use the normal resource schema.

Add `tag/1` and `group/1` inside the JSON:API adapter to make Swagger UI
 easier to navigate:

```elixir
defmodule MyApp.Courses.JsonApi do
  use Hawk.JsonApi.Resource

  type("courses")
  tag("Academics")
  group("Courses")
  doc("A course taught by a teacher at a school.")
end
```

`tag/1` becomes the OpenAPI operation tag and top-level tag entry. `group/1` is
emitted as `x-resource-group`; Hawk also emits `x-resource-type` so downstream
clients and docs can keep related JSON:API resources together without guessing
from path names. Pass `tag/2` with a `:description` to populate the top-level
tag's description (Swagger UI shows it next to the group), which keeps the spec
free of `tag-description` warnings:

```elixir
tag("Academics", description: "Academic resources: courses, grades, and enrollments.")
```

Multiple resources sharing a tag name collapse to one top-level tag entry;
when any of them declares a description, that description wins.

Relationship schemas are typed from the model association: a `belongs_to`/
`has_one` relationship renders as a to-one `data` identifier or `null`, and a
`has_many`/`many_to_many` relationship renders as a `data` array of identifiers.
Request relationship objects require `data`, and each non-null identifier
requires the related JSON:API `type` and an `id`, matching request validation.
The target type is resolved from the association (or the related model's adapter
by convention), so no per-relationship `:resource` opt is needed.

Frontend teams can generate TypeScript from that OpenAPI contract with their
preferred tooling, for example:

```bash
npx openapi-typescript http://localhost:4000/openapi.json -o src/api/types.ts
```

Hawk intentionally stays centered on the backend contract instead of owning a
frontend generator or client runtime.

## Plans

Plans are a human-in-the-loop execution mode over the existing JSON:API/Action
resource surface. An external AI composes a *proposed* batch of resource
operations for a specific problem, and a non-technical human reviews the rendered
effects and approves it before it touches production data — with the whole batch
executed atomically under the reviewer's authority, no AI in the loop at
execution.

The plan language is a sequence of resource-shaped operations (`:create`,
`:update`, `:delete`, `:action`) that the AI composes against the resource
spec (generated by `Hawk.Plans.Spec`, the resource-shaped equivalent of OpenAPI).
The executor (`Hawk.Plans.run/2`) runs the batch in a single `Hawk.Multi`
transaction under the reviewer's authority, all-or-nothing. The dry-run
(`Hawk.Plans.preview/2`) executes in a transaction and rolls back, giving the
human a full-fidelity effects preview.

Hawk owns the plan *struct*, the *spec renderer*, and the *execution invariants*
(`Hawk.Plan`, `Hawk.Plans.Spec`, `Hawk.Plans`, `Hawk.Multi`). The host app owns
plan *storage* (its own `plans` table + migration) and *plan-lifecycle auth*
(who can create/approve a plan — a product decision). This mirrors how Hawk
treats the `Repo`: Hawk does not define the `plans` table; the app provides it.

```bash
mix hawk.plans.spec -o tmp/plans.json   # generate the plan operation manifest
```

## Telemetry

Hawk does not emit its own controller telemetry. Generated JSON:API controllers
run behind standard Phoenix endpoints, so request-level latency and status come
from Phoenix's built-in `[:phoenix, :endpoint, :start/:stop]` and
`[:phoenix, :router_dispatch, :start/:stop]` events. Attach `Telemetry.Metrics`
to those the same way you would for any Phoenix controller.

## Generators and validation

### Resource generator

For a quick skeleton around an existing Ecto schema, use:

```bash
mix hawk.gen.resource MyApp.Courses MyApp.Course \
  --repo MyApp.Repo \
  --attributes title,code \
  --relationships school,teacher \
  --filters school_id,teacher_id \
  --preloads school,teacher
```

This creates the facade, policy, reader, JSON:API adapter, LiveView adapter, and
writer skeleton. Pass `--read-only` to gate writes with `write(:never)` in the
policy; the writer skeleton is still emitted, so the routes and handlers exist
and refuse writes. Pass `--web MyAppWeb` to also generate a Phoenix JSON:API controller,
clickable LiveView index/show modules and templates, and a router snippet file
beside the generated web files. The generated LiveViews use
`Hawk.Authority.Session.authority_or_public/1`, so they work for public demos and
can later pick up a session-backed authority. The generator is intentionally
conservative: it gives you the standard Hawk shape, then you tighten policy,
filters, labels, docs, and writer rules by hand.

### Validation gate

`use Hawk.Resource` validates at compile time, but a *missing* sibling emits a
warning rather than raising, so a facade can compile before its siblings during
incremental edits or code generation. A *present but malformed* sibling still
fails fast — that is real contract drift, not a write-order artifact.

`mix hawk.validate` is the authoritative, order-independent gate. It validates
every discovered Hawk resource in strict mode (missing siblings raise) and runs
the full `Hawk.ResourceContract` cross-checks. The `mix test` alias runs it
first, so `mix test` is the complete local gate — contract validation plus the
suite, same path CI takes:

```bash
mix test                          # mix hawk.validate + the test suite
mix hawk.validate                # discover and validate all Hawk resources
mix hawk.validate MyApp.Courses  # validate explicit resource(s)
```

`mix hawk.openapi` writes an OpenAPI spec from every discovered Hawk facade
(`json_api: false` resources are omitted by `Hawk.OpenApi.spec/2`), so the spec
stays in sync with the resources that actually exist — no hand-maintained list
to drift:

```bash
mix hawk.openapi -o tmp/openapi.json --title "My API" --version 1.0.0 \
  --path-prefix /api/v1
mix hawk.openapi MyApp.Courses -o spec.json --title "My API"   # override discovery
mix hawk.openapi -o spec.json --title "My API" --license "Apache-2.0" \
  --license-url "https://www.apache.org/licenses/LICENSE-2.0"
```

`--title` is required: Hawk is a library and does not name the host app's API.
`info.license` is the host application's choice — Hawk does not pick a license
for you. Pass `--license` (and optionally `--license-url`) to render it; omit
both to leave `info.license` out of the spec.

## Testing

### Resource contract test

```elixir
defmodule MyApp.CoursesContractTest do
  use Hawk.ResourceContractCase,
    resource: MyApp.Courses,
    model: MyApp.Course
end
```

The contract test checks that JSON:API attributes, relationships,
creatable/updatable fields, reader preloads, sorts, filters, and scoped policy
filters agree with the model, reader, and policy declarations. For resources
where every exposed relationship is expected to be include/preloadable, call
`Hawk.ResourceContract.validate!/3` with `require_relationship_preloads: true`.

### JSON:API controller contract test

```elixir
defmodule MyAppWeb.CoursesControllerTest do
  use Hawk.JsonApiControllerCase,
    controller: MyAppWeb.CoursesController,
    resource: MyApp.Courses,
    model: MyApp.Course,
    repo: MyApp.Repo

  authorities do
    school_id = "00000000-0000-0000-0000-000000000007"
    teacher_id = "00000000-0000-0000-0000-000000000012"

    %{
      school_admin: Hawk.Authority.new(:school_admin, "00000000-0000-0000-0000-000000000001", scopes: %{school_id: school_id}),
      teacher: Hawk.Authority.new(:teacher, teacher_id, scopes: %{school_id: school_id, teacher_id: teacher_id})
    }
  end

  pre_sample authorities do
    %{
      school: %MyApp.School{id: authorities.school_admin.scopes.school_id},
      teacher: %MyApp.Teacher{id: authorities.teacher.identity, school_id: authorities.teacher.scopes.school_id}
    }
  end

  sample _authorities, known, index do
    %MyApp.Course{
      id: "00000000-0000-0000-0000-00000000000#{index}",
      title: "Course #{index}",
      school_id: known.school.id,
      teacher_id: known.teacher.id
    }
  end

  test "specific business rule still fits beside the generated matrix" do
    item_1 = generate_sample(1)
    item_2 = generate_sample(2)

    assert item_1.school_id == item_2.school_id
  end
end
```

The generated matrix exercises each configured authority against `index`,
paginated `index`, `show`, `create`, `update`, and `delete`. `:public` is always
included even when not listed in `authorities`, and its expected result comes
from the resource policy. Expected access is derived from the resource reader
and policy, while mutation payloads are built from JSON:API examples unless
`create_params` / `update_params` are supplied.

Controller cases define authorities and samples with small DSL blocks:

- `authorities do ... end` returns a map of named `Hawk.Authority` values. Hawk
  still adds `:public` automatically when omitted.
- `pre_sample(authorities) do ... end` optionally builds shared context once,
  such as parent records. The default returns `%{}`.
- `sample(authorities, known, index) do ... end` builds deterministic resource
  samples from the authorities and known context. This callback is required; if
  it is missing, Hawk raises a clear error explaining which function to add.

The matrix uses the generated samples for collection and pagination coverage,
and `sample_model()` — the first generated sample — for show/update/delete. The
default generated collection size is 3; only pass `sample_count:` when a
resource needs a larger collection.

Specific business-rule tests can call `generate_sample(index)` or
`generate_samples(count)` directly. These helpers reuse the same authorities,
`pre_sample`, and `sample` definitions as the generated matrix. `pre_sample` is
cached per test process, so it also works when it creates real PostgreSQL data
through fixtures or factories and several generated samples need to share those
records.

## Formatting

Applications should import Hawk's formatter settings so the DSL stays tidy:

```elixir
# .formatter.exs
[
  import_deps: [:hawk],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

## Compile-time contracts and runtime lookup

Hawk macros generate stable entrypoints, not snapshots of sibling metadata. The
safe boundary is: bake module references and explicit local options; call
functions to read sibling metadata when the generated code runs.

That means:

- `Hawk.LiveView` generated helpers pass the resource facade and explicit local
  options. Runtime helpers read `resource.__hawk_resource__(:live_view)` and
  `__hawk_live_view__/0` when assigning tables, fields, forms, and default
  assign names.
- `<Resource>.action/4` is the only facade action entrypoint. It resolves the
  current `Actions` module metadata and dispatches by name at runtime; facades
  do not generate one public function per action.
- JSON:API controllers generate a stable `hawk_action/2` function and let
  runtime dispatch decide whether an action exists.

### Rule for Hawk contributors

When a macro-generated function consumes sibling metadata, **bake how to ask,
not the answer**. `Macro.escape/1` is fine for values owned by the macro call
itself, such as literal options or a DSL block compiled into the same module. It
is not fine for metadata owned by another sibling module, such as
`__hawk_live_view__/0`, `__hawk_actions__/0`, or `__hawk_json_api__/0`.
