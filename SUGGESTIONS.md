# Hawk Improvement Suggestions

Notes from building a resource generator on top of Hawk. Each item is grounded in
something that repeatedly cost time or forced a workaround; each suggests a
concrete, framework-level change. Ordered by impact: the first item caused the
most debugging time, the last is polish.

These are suggestions, not blockers. Hawk's compile-time validation catches
real bugs (subset enforcement, missing siblings, contract drift) — that
validation is valuable. The notes below are about *timing* and *ergonomics*,
not about removing the safety.

## Status

| # | Suggestion | Status |
|---|---|---|
| 1 | Deferred validation / official scaffold mode | **Shipped** (smarter version) |
| 2 | Introspectable resource contract | Open |
| 3 | `unique_constraint` as a top-level writer macro | **Shipped** (bounded `constraint/2`) |
| 4 | Enum / custom type integration | Open |
| 5 | First-class view / projection / ID-less resources | **Shipped** (smarter version) |
| 6 | LiveView ⊆ Reader: help compute the subset | Open |
| 7 | Resolve `relationship` targets automatically for OpenAPI | **Shipped** (smarter version) |
| 8 | Reader: a principled default filter/sort surface | Open |

Shipped items are noted inline below with what actually landed and where the
implementation differs from the original suggestion. Open items remain as
asked.

---

## 1. Deferred validation / official scaffold mode (highest impact)

`use Hawk.Resource` calls `Validation.validate!/1` at compile time, which
checks that the model, reader, writer, policy, json_api, and live_view modules
all exist and compile. This is the right invariant to enforce, but the
*timing* is hostile to code generation and incremental development:

- A generator that writes the facade before its siblings triggers
  `"Hawk resource reader module X is not available"` mid-write.
- Mix recompiles eagerly when new files appear, so a half-written resource
  set fails to compile and poisons subsequent runs.
- The only robust ordering is "write the facade last," which a generator has
  to discover by trial and error.

### Suggested

Add a deferred-validation mode and/or an official generator:

```elixir
use Hawk.Resource, model: MyApp.Course, defer_validation: true
```

With `defer_validation: true`, `__using__` skips the `validate!` call and
instead emits a `@before_compile` hook (or a `Hawk.validate_resource/1` the
app calls explicitly at boot / in a test). This lets a generator write all
files in any order and let the whole app compile, then validate once.

Even better: ship `mix hawk.gen.resource` that owns the write order and the
validation timing, so downstream generators don't reinvent it.

This is the difference between "Hawk is codegen-friendly" and "Hawk is
codegen-hostile until you work around it." It was the single largest source
of debugging time in building a generator.

### Shipped

`Hawk.Resource.Validation.validate!/2` now takes a mode:

- `:compile` (default) — a *missing* sibling emits a warning (`IO.warn`) and
  skips that module's shape checks, so a facade compiles before its siblings
  during incremental edits or code generation. A *present but malformed*
  sibling still raises, because that is real contract drift, not a
  write-order artifact.
- `:strict` — missing siblings raise.

The authoritative gate is `mix hawk.validate`, which discovers Hawk resources by
scanning compiled beams for `__hawk_resource__/1` and runs `:strict` validation
plus the full `Hawk.ResourceContract` cross-checks. The `mix test` alias runs
it first, so `mix test` is the complete local gate — contract validation plus
the suite, the same path CI takes.

Notes on the implementation vs. the original suggestion:

- The proposed `defer_validation: true` + `@before_compile` does not actually
  defer past compile — `@before_compile` runs at *that module's* compile time,
  the same phase as `__using__`. The warn/raise split achieves the goal
  instead: the noisy missing-module failures (write-order artifacts) become
  warnings, while the valuable drift detection among present modules stays a
  hard raise.
- Building the task surfaced and fixed three latent `Hawk.ResourceContract`
  bugs no existing test caught: unnormalized hand-written adapter maps, a
  `Map.keys([])` crash on readers without `filter_handlers/0`, and
  relationship `source:` ignored in the relationship/preload subset checks.
  The gate now protects all discovered resources, not just those with a
  hand-written `ResourceContractCase` test.

---

## 2. Introspectable resource contract

A generator currently has to read Hawk's source to discover: which sibling
modules are required, which macro options exist, what `__using__` registers,
and what `__hawk_*__` functions adapters expose. There is no
`Hawk.Resource.__contract__/0`.

### Suggested

Expose the contract as data:

```elixir
Hawk.Resource.__contract__()
# => %{
#   required_modules: [:model, :reader, :policy, :writer, :json_api, :live_view],
#   optional_modules: [:actions],
#   model_opts: [:source, :primary_key, :view],
#   writer_macros: [:create, :update, :delete],
#   json_api_macros: [:type, :tag, :group, :doc, :attribute, :relationship],
#   live_view_macros: [:as, :plural_as, :index, :show, :create_form, :update_form],
#   reader_macros: [:filter, :sort, :preload, :attach],
#   policy_macros: [:read, :write]
# }
```

Tooling (generators, LSP, docs, validators) can then target the surface
programmatically instead of reverse-engineering it. This turns "a generator
that happens to target Hawk" into "Hawk-supported tooling."

---

## 3. `unique_constraint` as a top-level writer macro

Ecto exposes `unique_constraint/2` as a top-level changeset macro. In Hawk it
must be wrapped in a `validate_changeset(&__MODULE__.foo/1)` callback:

```elixir
create do
  cast([:email, :user_id])
  validate_required([:email])
  validate_changeset(&__MODULE__.validate_business_rules/1)
end

def validate_business_rules(changeset) do
  changeset |> Ecto.Changeset.unique_constraint(:email, name: :email_user_id_unique)
end
```

This is a real ergonomics gap: a user reaches for `unique_constraint` where
Ecto puts it (in the cast block), gets a compile error, and has to learn the
callback indirection by reading existing resources.

### Suggested

Accept `unique_constraint` (and probably `foreign_key_constraint`,
`assoc_constraint`) as top-level writer-step macros that desugar into the
`validate_changeset` callback:

```elixir
create do
  cast([:email, :user_id])
  validate_required([:email])
  unique_constraint(:email, name: :email_user_id_unique)
end
```

### Shipped (bounded as `constraint/2`)

Added a single generic `constraint/2` step rather than enumerating five
separate `*_constraint` macros. `kind` selects the constraint type and the step
desugars to `validate_changeset(fn cs -> Ecto.Changeset.<kind>_constraint(cs, field, opts) end)`:

```elixir
create do
  cast([:email, :user_id])
  validate_required([:email])
  constraint(:unique, :email, name: :email_user_id_unique)
  constraint(:foreign_key, :user_id, name: :enrollments_user_id_fkey)
end
```

`kind` is one of `:unique`, `:foreign_key`, `:assoc`, `:check`, or `:exclusion`.

Notes on the implementation vs. the original suggestion:

- The literal suggestion (a `unique_constraint` macro) doesn't stop there — the
  same argument applies to `foreign_key_constraint`, `assoc_constraint`,
  `check_constraint`, `exclusion_constraint`. Adding one without the others is
  arbitrary; adding all five doubles the writer DSL's step count for pure
  ergonomics. One `constraint/2` step covers all five with a single new entry.
- The inline `validate_changeset(fn cs -> Ecto.Changeset.unique_constraint(cs, :field) end)` form already compiled and worked before this change (verified); the gap
  was verbosity on the most common case, not a missing feature or a correctness
  bug. `constraint/2` is pure ergonomics with no new semantics.
- Constraint violations render through the existing error pipeline at the
  external JSON:API pointer (see the `source.pointer` fix), so `unique_constraint`
  errors already map to `/data/attributes/{external}`.

---

## 4. Enum / custom type integration

`structure.sql` carries enum types (`public.currency`, `public.booking_flow`)
and Rails models declare `attribute :provider, AuthenticationProvider`. In a
Hawk model these all collapse to `:string` because `Hawk.Model` has no enum
story. The cleanup pass has to fill these in by hand, and the JSON:API/OpenAPI
output loses the value set.

### Suggested

Add an `Ecto.Enum`-backed declaration to the model DSL and a JSON:API enum
shape so OpenAPI emits an enum schema:

```elixir
model "bookings" do
  field(:state, :string)
  enum(:currency, values: [:DKK, :EUR, :SEK, :NOK])
  enum(:flow, values: [:platform, :inquiry, :travel_agency])
end
```

A generator can populate `values` by parsing `CREATE TYPE ... AS ENUM (...)`
from `structure.sql` when present (Postgres enums) or from the Rails model's
`attribute :x, EnumType` / `enums do ... end`.

---

## 5. First-class view / projection / ID-less resources

Materialized views, denormalized projections, and reporting tables often have
no `id` column and no `inserted_at`/`updated_at`. Today they require
hand-rolled special-casing across every adapter:

- the model must not emit `field(:id, ...)`,
- the reader must not emit `filter(:id)` / `sort(:id)`,
- the live_view must not reference `:id`,
- and `timestamps/1` must be skipped.

Each of these is a separate failure mode the user discovers at compile time or
runtime. Hawk's own `@primary_key {:id, :binary_id, autogenerate: true}` is
hardcoded.

### Suggested

A `view: true` (or `primary_key: false`, `timestamps: false`) option on
`Hawk.Model` that downstream adapters honor:

```elixir
model "enriched_bookings", view: true do
  field(:booking_id, :binary_id)
  # no :id, no timestamps, no primary key
end
```

Reader/live_view/json_api then auto-skip `:id` and timestamp filters/sorts/
attributes when the model declares `view: true`, instead of every generator
and every hand-written view reinventing the skip.

### Shipped (smarter version: declared identity)

`view: true` under-aims: it bundles three independent skips (no PK, no
timestamps, no `:id` filter/sort) behind one magic flag, and it papers over the
deeper issue — Hawk assumes `:id` everywhere. The JSON:API document does
`Map.get(model, :id)`, readers default `sort(:id)`, the controller `show`
filters by `:id`. JSON:API *requires* an `id` in every resource object, so an
ID-less resource still needs *some* identifier to expose.

What landed makes identity *declared*, not assumed:

```elixir
defmodule MyApp.CourseGradeSummaries do
  use Hawk.Resource,
    model: MyApp.CourseGradeSummary,
    identity: :course_id
end

defmodule MyApp.CourseGradeSummary do
  use Hawk.Model

  model "course_grade_summaries", primary_key: false do
    field(:course_id, :binary_id)
    field(:grade_count, :integer)
  end
end
```

The declared identity drives the JSON:API `id` rendered by `Document`, the
member-lookup filter and short-id UUID range in the controller, and the
LiveView `assign_show`/delete lookup key. `Hawk.Model` accepts
`primary_key: false` to drop the surrogate primary key. Compile-time
`validate_identity!` requires the identity field to exist on the model.

Deferred: composite identity (`identity: [:a, :b]`) and `identity: false` —
scoped to single-field identity, the case that actually unblocks view-backed
projections. `view: true` was not added as sugar; the declared identity is the
real primitive. Uniqueness/non-nullability/indexing of the identity field
remain the resource author's responsibility, the same trust model Hawk uses
for the default `:id`.

---

## 6. LiveView ⊆ Reader: help compute the subset

Hawk enforces that every `filter`/`sort` declared in the LiveView adapter is
also declared by the Reader — good check, catches real drift. But it gives no
help *computing* the subset, so a generator (or a human) that picks
LiveView filters independently will hit `"live_view filter :x must be declared
by reader"` repeatedly. This is an especially easy mistake for ID-less
tables and for sort columns the Reader doesn't declare.

### Suggested

One of:

- `import_filters from: Reader` / `import_sorts from: Reader` in the
  LiveView DSL, so the LiveView inherits the Reader's set and only *overrides*
  what it wants to change; or
- a `Hawk.LiveView.derive_from(reader)` helper that builds a default LiveView
  filter/sort set as a subset of the Reader's, which a generator can call and
  then trim.

Either removes the "pick independently and hope they align" failure mode.

---

## 7. Resolve `relationship` targets automatically for OpenAPI

`relationship(:parent, writable: true)` compiles, but OpenAPI needs the target
resource to render the relationship schema. Today the user must remember
`relationship(:parent, resource: MyApp.Parent, writable: true)` — easy to
forget, and the failure is a worse OpenAPI spec, not a compile error.

### Suggested

When `resource:` is omitted, resolve the target from the model's schema
association (`assoc(:parent).__struct__` or the `belongs_to`/`has_many`
reflection) and derive the resource module by convention. Emit the
`resource:` automatically so OpenAPI works without the user spelling it out.

### Shipped

No new `:resource` DSL opt was added — reading `Hawk.JsonApi.Resource`,
`:resource` is not even in the attribute/relationship opt allowlist, so it
would be silently dropped today, and the OpenAPI composer rendered every
relationship as a generic `type: object`. Instead, `Hawk.OpenApi`'s
relationship schema now resolves the target from the model association
(`model.__schema__(:association, source)`) and emits a *typed* JSON:API
relationship object:

- to-one → `data: {type: object, properties: {type: {enum: [related_type]},
  id: {type: string}}}`
- to-many → `data: {type: array, items: …}`

The target type is resolved through `Hawk.JsonApi.Schema.metadata(related)`,
so it works whether the related resource is a facade or a hand-written
adapter. Falls back to a generic object only when the association is
unresolvable (e.g. a projection over an internal shape). Zero DSL change,
nothing for the user to forget.

---

## 8. Reader: a principled default filter/sort surface

There is tension between two conventions: hand-written readers are *selective*
(~5–10 columns chosen by what the UI actually filters on), while a generator
can only *include everything* or *guess* by type/name. A type-based heuristic
measured against a corpus of hand-written readers over-includes junk and
under-includes columns the team filters on (often date columns) — so the
heuristic was reverted and selection stayed a manual cleanup step.

### Suggested

Give the Reader DSL a way to express "the useful default" without forcing
manual selection of every column, and a way to express exclusion concisely:

```elixir
use Hawk.Reader.Resource, schema: MyApp.Course

# Derive a default filter/sort set from the schema (skip known-junk types),
# then narrow:
auto_filters(except: [:internal_token, :search_blob])
auto_sorts(except: [:search_blob])
```

`auto_filters` would emit filters for scalar columns (string/enum/boolean/
date/integer/uuid), skip json/array/text/decimal, and let the user trim with
`except`. This gives a generator a defensible default and a hand-written reader
a one-line way to say "all the obvious ones, minus these."

---

## What Hawk gets right (so this isn't all criticism)

- Compile-time validation catches real drift: missing siblings, subset
  violations, contract mismatches. The failures are loud, not silent.
- The Reader / Writer / Policy / JsonApi / LiveView split is a clean separation
  that makes a resource tractable as data, not as a pile of Phoenix context
  modules.
- `Hawk.ResourceContractCase` exists at all — contract tests for a resource
  shape are genuinely valuable and rare in this space. (After item 1 shipped,
  the framework's own gate became discovery-based `mix hawk.validate`, which
  covers every resource uniformly; `ResourceContractCase` stays for downstream
  apps that want a per-resource test, but the framework no longer relies on
  hand-written per-resource contract modules — 5 of 13 Videdal resources had
  none, and the renamed-relationship bug in `ExternalCourses` survived because
  of it.)
- The DSL is compact and consistent across adapters; a generator can target it
  with simple string templates, no AST manipulation.
- The adapter discovery convention (sibling `JsonApi`, `LiveView`, `Reader`)
  means a facade stays one line.

The suggestions above are about making the framework a good *target for
tooling*, not about changing what it is.
