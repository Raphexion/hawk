# Hawk

Hawk is an opinionated Phoenix backend foundation for resource-heavy systems
that need the same policy-safe domain surface exposed through internal admin UI
and backend APIs.

It is designed for the shape that appears in many backends: Ecto resources with
role-aware reads and writes, a JSON:API surface for clients and integrations, and
LiveView screens for internal administration. Hawk tries to make that repeated
middle layer boring: resource contracts, policies, readers, writers, adapters,
and tests follow one convention instead of being rebuilt per project.

Hawk depends on Ecto, Ecto SQL, Postgrex, and Phoenix (with Phoenix LiveView
and Phoenix Ecto). It does not define or supervise a concrete `Ecto.Repo`.
Applications provide their own Repo modules, database configuration, migrations,
authentication, and supervision tree.

## Direction

Hawk's current north-star design is captured in [`docs/hawk-resource-direction.md`](docs/hawk-resource-direction.md).
The Plans design (AI-authored, human-reviewed batches) is in [`docs/hawk-plans-design.md`](docs/hawk-plans-design.md).

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
    writer: false,
    json_api: false,
    live_view: false
end
```

The facade generates public reader/writer/action delegations and exposes resource
introspection through `__hawk_resource__/1`. JSON:API rendering discovers
sibling adapter metadata from related models' resource facades, so each resource
has a single source of JSON:API truth. JSON:API controllers generated from
a facade only expose actions supported by the resource capabilities: read actions
are always available, create/update/delete require `writer`, and `/-actions/`
requires `actions`. It also validates adapter contracts
at compile time; JSON:API adapter `source:` entries must point at real model
fields or associations, writable fields must be declared, and LiveView fields /
filters must reference real model fields and declared reader filters.

A Hawk resource has four small modules plus Phoenix-facing helpers:

- `Model` declares the Ecto schema and association resource metadata.
- `Policy` declares who can read/write.
- `Reader` owns filtering, sorting, pagination, and policy-aware preloads.
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

Nested includes such as `include=grades.student` are turned into nested Ecto
preloads where every layer uses that resource's own reader and policy. Opening
`courses` does not accidentally open `grades` or `students`.

Readers apply `default_page_size` when the caller does not request a page size
and reject requests above `max_page_size`. Both default to `100` and can be
overridden per resource. Collection JSON:API responses include `meta.page` with
`size`, `number`, and returned `count`. Hawk accepts `page[size]` / `page[number]`
and the shorthand `page_size` / `page_number` query parameters.

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
They are exposed under `/-actions/` and keep command-style endpoints separate
from CRUD routes while staying JSON:API-compliant by accepting parameters in
`meta`.

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

Route action requests to the generated controller `action/2` function, for
example:

```elixir
post "/courses/:id/-actions/:action", CourseController, :action
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
convert that scope to a Hawk authority, and assign both `:hawk_authority` and
`:authority` for JSON:API controllers. In LiveView `on_mount`, use it after the
generated `UserAuth` hook has assigned `current_scope`.

`Hawk.Authority.Plug` / `Hawk.Authority.Session` are lower-level generic helpers
for apps that are not using the phx.gen.auth scope shape. Missing authority falls
back to readonly public access, not system access.

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
end
```

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

Controllers can still pass `model:` explicitly when integrating with older hand-written facades.

Generated actions follow resource capabilities:

- `index/2`
- `show/2`
- `create/2` when `writer` is enabled
- `update/2` when `writer` is enabled
- `delete/2` when `writer` is enabled
- `relationship/2` for `GET .../:id/relationships/:relationship`
- `related/2` for `GET .../:id/:relationship`
- `action/2` for `POST .../:id/-actions/:action` when `actions` is enabled

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
- missing record: `404`
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

Some requests support declared reader filters through JSON:API-style query params.
Bare values become equality filters, and supported operators use one nested key:

```text
/api/v1/courses?filter[school_id]=school-1&filter[active][eq]=true&filter[name][ilike]=%25math%25
```

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
    end
  end

  show do
    field(:title)
    field(:registration_state, label: "State")
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
Generated LiveView event handlers follow resource capabilities; for example,
read-only resources with `writer: false` do not get the default `"hawk:delete"`
handler. Show pages can load by natural keys when the reader declares the filter:

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

### LiveView helpers

For simple single-resource pages:

```elixir
defmodule MyAppWeb.CourseIndexLive do
  use Hawk.LiveView,
    resource: MyApp.Courses
end
```

When `resource:` is a `Hawk.Resource` facade, Hawk infers the singular/plural assign names from the model. Older hand-written facades can still pass `as:` explicitly.

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
Default `handle_event("hawk:validate", ...)` and `handle_event("hawk:save", ...)`
clauses call those helpers unless `events: false` is set. `hawk_validate/2`
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

## OpenAPI

```elixir
defmodule MyAppWeb.OpenApiController do
  use Hawk.OpenApi.Controller,
    title: "My API",
    version: "1.0.0",
    path_prefix: "/api/v1",
    resources: [MyApp.Courses, MyApp.Grades]
end
```

Pass resource facades when available; model modules remain supported for older
code. Facades with `json_api: false` are omitted because this OpenAPI generator
documents the JSON:API surface only. This exposes `spec/0` and `show/2`. The specification is composed from Hawk
resource declarations and the same `Hawk.JsonApi.Routes` route specs used for
capability-aware routing: JSON:API adapter schemas, request bodies, error
documents, sort parameters, pagination parameters, valid include paths, declared
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
`has_one` relationship renders as a to-one `data` object whose `type` enum is
the related resource's JSON:API type, and a `has_many`/`many_to_many`
relationship renders as a `data` array of the same identifier shape. The target
type is resolved from the association (or the related model's adapter by
convention), so no per-relationship `:resource` opt is needed.

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
The executor (`Hawk.Plans.run/3`) runs the batch in a single `Hawk.Multi`
transaction under the reviewer's authority, all-or-nothing. The dry-run
(`Hawk.Plans.preview/2`) executes in a transaction and rolls back, giving the
human a full-fidelity effects preview.

Hawk owns the plan *struct*, the *spec renderer*, and the *execution invariants*
(`Hawk.Plan`, `Hawk.Plans.Spec`, `Hawk.Plans`, `Hawk.Multi`). The host app owns
plan *storage* (its own `plans` table + migration) and *plan-lifecycle auth*
(who can create/approve a plan — a product decision). This mirrors how Hawk
treats the `Repo`: Hawk does not define the `plans` table; the app provides it.

See [`docs/hawk-plans-design.md`](docs/hawk-plans-design.md) for the full design.

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
writer skeleton. Pass `--read-only` to generate `writer: false` and omit the
writer. Pass `--web MyAppWeb` to also generate a Phoenix JSON:API controller,
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
mix hawk.openapi MyApp.Courses -o spec.json   # override discovery
```

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
