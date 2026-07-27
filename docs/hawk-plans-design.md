# Hawk Plans Design

Hawk Plans is a human-in-the-loop execution mode over the existing JSON:API/Action
resource surface. It lets an external AI compose a *proposed* batch of resource
operations for a specific problem, and a non-technical human review the rendered
effects and approve it before it touches production data — with the whole batch
executed atomically under the reviewer's authority, no AI in the loop at
execution.

Plans are **not a third per-resource adapter** in the `JsonApi`/`LiveView` sense
(those are per-resource projections of declarations). Plans are a *runtime mode*
over the existing resource surface, plus a spec renderer. The design is
deliberately thin: it closes two gaps that immediate per-call JSON:API
execution lacks, and adds nothing else.

## The two gaps this closes

1. **Cross-call atomicity.** JSON:API executes each request in its own
   transaction. A multi-step fix (remove an enrollment, add another, recompute
   grades) is three requests and three transactions; the second can fail and
   leave the first applied — half-applied production state. Plans run the whole
   batch in a single transaction, all-or-nothing.
2. **A human review gate with rendered effects.** JSON:API has no "propose, get
   a URL, a human reviews the rendered effects, approves, then it runs." A plan
   is a proposed batch a human reviews before anything persists.

Plans explicitly do **not** add: a curated verb DSL, an MCP-style toolbox, a
per-resource `Playbook` adapter module, new per-resource declarations, a
planner/diff engine, saga/compensation machinery, or any AI in the execution
loop. The LLM keeps full compositional freedom against the existing resource
surface; the new machinery is a batch + atomic + review layer over it.

## Why this shape (and not the alternatives)

Three alternatives were considered and rejected during design. Recording them
here so they are not re-litigated:

**Rejected: a curated verb DSL (the "Playbook" adapter).** An earlier draft
proposed a per-resource adapter declaring named, doc'd verbs ("swap-enrollment",
"close-course") that compile to writer/action sequences. This is an MCP-style
toolbox: every domain-specific verb must be pre-authored by a developer, so the
AI can only do what someone imagined. It is *less* flexible than "LLM +
JSON:API/Action surface," where the LLM composes novel sequences from a
documented surface. The value of LLMs on well-documented backends is compositional
novelty; a curated verb vocabulary replaces that with rigidity. The plan
language is therefore just a batch of the *existing* resource operations, not a
new vocabulary.

**Rejected: the diff/desired-state model.** An earlier draft proposed the AI
authors a *desired end state* and a planner computes the steps. This puts the
hard part (is this the right sequence?) into a new planner that must agree with
the writer boundary — the "new thing that agrees with old thing" drift shape.
The program model (AI authors the sequence, runtime executes it) keeps the
existing invariants doing the safety work for free: every plan op calls the
existing writer/action boundary, so `Policy` and `RepositoryBoundary` apply with
no re-implementation.

**Rejected: Hawk-managed plan storage.** Persisting plans in a Hawk-managed
table would force every host app to run a Hawk migration and would make a plan
"a resource needing its own policy" — who can create, who can approve, who can
run. That is a *product* decision (which support teams, which LLM agents), not a
*framework* decision. Hawk owns the plan *struct* and the *execution
invariants*; the host app owns plan *storage* and *plan-lifecycle auth*. This
mirrors how Hawk already treats the `Repo`: Hawk does not define or supervise a
concrete Repo; the app provides it. Same for plans.

## The pipeline

```
  ┌─────────┐   reads    ┌─────────────────┐
  │  LLM    │ ◀──────── │ Hawk.Plans.Spec │  (renderer over Routes + Actions)
  └─────────┘            └─────────────────┘
       │ authors plan (resource-shaped ops + comments)
       ▼
  ┌─────────────────────┐  stores, gets a URL, stays DRAFT
  │ Scratchpad (host)   │  ── host app's table, host app's policy
  └─────────────────────┘
       │ human visits URL
       ▼
  ┌─────────────────────┐  comments (AI) + effects (Hawk) + policy check
  │ Review surface (host)│  ── calls Hawk.Plans.preview/2
  └─────────────────────┘
       │ approve
       ▼
  ┌─────────────────────┐  single transaction, reviewer's authority,
  │ Hawk.Plans.run/3    │  ── no AI in the loop, all-or-nothing
  └─────────────────────┘
```

1. **Spec.** `Hawk.Plans.Spec` renders, per resource (by JSON:API `type`), the
   ops an authority can perform: `:read` (with filters, for finding affected
   records), `:create`/`:update`/`:delete` (with creatable/updatable
   attrs/relationships from the JsonApi adapter), `:action` per declared action
   (name, doc, params in op shape — `meta` already unwrapped). Authority-aware
   via the same capability filtering OpenAPI uses. The LLM reads it to compose
   plans; the executor validates plans against it. **One source of truth, no
   drift between authoring and execution** — the same property `mix hawk.validate`
   has. The spec is a second renderer over `Hawk.JsonApi.Routes` + `Hawk.Actions`,
   not new declarations.
2. **Scratchpad.** A host-app controller/endpoint where the AI POSTs a draft
   plan (`Hawk.Plan` struct serialized to JSON). Stored by the host app, gets a
   URL, stays DRAFT, carries the authoring authority. Hosted in the host app,
   not Hawk — see "Storage and auth split" below.
3. **Review surface.** The human visits the URL and sees the plan rendered:
   comments (AI narrative, visually distinct, executor-ignored) + structural
   effects (Hawk-rendered from the dry-run) + policy check (against the
   reviewer's authority). Approve or reject. Hosted in the host app; calls
   `Hawk.Plans.preview/2` for effects.
4. **Dry-run.** `Hawk.Plans.preview/2` executes the plan's ops in a single real
   transaction, captures effects and any failure, rolls back. Returns
   `{ok, effects}` or `{error, failed_op, prior_effects}`. Full fidelity
   including `constraint/2` repo-level constraints. Labeled "preview;
   execution re-checks under your authority" — a state change between preview
   and approve is caught at execute because execute re-runs the real policy.
5. **Execution.** On approval, `Hawk.Plans.run/3` runs the *same* ops in a
   single `Hawk.Multi` transaction under the **reviewer's** authority. Each op
   resolves the resource facade and calls `resource.delete/2` /
   `resource.action/3` / etc. — the same functions the JSON:API controller
   calls, through the same `Policy` → `RepositoryBoundary` (Write Invariant
   intact, no parallel write path). Any step failure rolls back the whole
   transaction. No AI in the loop.

## The plan op shape (resource-shaped)

A plan is a list of resource-shaped operations, each one a call the AI could
have made directly over JSON:API/Actions:

- `{op: :read, resource: "courses", filter: {...}, page: {...}}` — read-only,
  no effects. Used by the AI to ground its plan; surfaced in the review as "the
  AI looked at these records."
- `{op: :create, resource: "enrollments", attrs: {...}, relationships: {...}}`
- `{op: :update, resource: "courses", id: "crs-math", attrs: {...}}`
- `{op: :delete, resource: "enrollments", id: "enr-ada-math"}`
- `{op: :action, resource: "courses", id: "crs-math", action: "close-registration", params: {...}}`

Plus optional `comment:` fields per op and per plan — the AI's narrative. The
executor never reads them; the review surface renders them as prose, visually
distinct from the structural effects. The trust split is the same as comments
in source code: comments are for humans, the code (ops) is authoritative.

The plan language is **not HTTP-shaped** (`{method, path, body}`). It is
resource-shaped so the executor and dry-run have resource-level effects natively
(the dry-run calls the facade and sees `MutationContext`/changesets, not HTTP
responses), and so the OpenAPI-style reverse-routing is avoided. The LLM reads
the OpenAPI spec (which is resource-structured via `x-resource-type`) and
authors `{op, resource, ...}` — a thin, mechanical translation the
`Hawk.Plans.Spec` exists to make drift-free.

## Storage and auth split

This is the most important contract for host-app authors to understand.

**Hawk owns:**
- `Hawk.Plan` — a typed struct: `%{ops: [...], comments: %{...}, authoring_authority: Authority.t}`.
  Pure data, serializable to JSON. No storage.
- `Hawk.Plans.Spec` — the renderer, `mix hawk.plans.spec` task, and an optional
  controller mountable at `/plans.json`. Curl-able, read-only, authority-aware.
- `Hawk.Plans.preview/2` — `(plan, reviewer_authority) → {ok, effects} | {error, failed_op, prior_effects}`,
  rollback dry-run.
- `Hawk.Plans.run/3` — `(plan, reviewer_authority, repo) → result`, transactional
  execute under the reviewer's authority through the facades.
- `Hawk.Multi` — the transactional composer used by `preview`/`run`, reusable
  beyond plans.

**The host app owns:**
- A `plans` table + schema + migration (the host app's own). Hawk ships no
  migration. The table stores the serialized `Hawk.Plan` plus whatever
  auth/audit columns the app wants.
- A `plans` policy (the host app's own): "only :support_ops can approve," "only
  agent-X can create." This is a *product* decision about *plan lifecycle*, not
  a framework decision. Hawk's `Authority` struct supports any role atom
  (`role: :llm`, `role: :support_ops`), so the app can use role-based,
  API-key-based, or any other auth it already has.
- The scratchpad controller + review UI, calling `Hawk.Plans.preview/2` for the
  rendered effects and `Hawk.Plans.run/3` on approval.

The split mirrors how Hawk already treats the `Repo`: Hawk does not define or
supervise a concrete Repo; the app provides it. Same for plans: Hawk does not
define the `plans` table; the app provides it.

## The trust model

- The **LLM proposes.** Its authority (the `authoring_authority` stored in the
  plan) scopes the *spec* it reads — the spec is generated for that authority,
  so the LLM only sees ops it could legally invoke. The authoring authority is
  *never* used for execution.
- The **human disposes.** At approval, the reviewer's authority (the same
  `Hawk.Authority` the app's session already produces for its controllers) is
  passed to `Hawk.Plans.run/3`. Execution applies the existing per-resource
  `Policy` to each op under the *reviewer's* authority — the real check, against
  the authority that will own the change. A plan authored for reviewer-A's
  authority may be unapprovable by reviewer-B (different scopes); that is
  correct, and the policy check at execute catches it.

The plan document's `comment:` fields are the AI's narrative and are *never*
read by the executor. The ops are authoritative. The review surface shows both,
makes the split visible, and labels the effects as a preview that execution
re-checks.

## Atomicity and failure

A plan runs in a single repo transaction. Any op failure rolls back the whole
batch. This is all-or-nothing (the "Q4(a)" resolution from design): no
compensating/saga machinery, no half-applied state, no best-effort.

Plans are restricted to **transaction-runnable** ops — writer/action pipelines
that are safe inside a single transaction. Actions that open their own
transaction or do external side-effects (sending an email, enqueuing a job) are
*not expressible* as plan ops in v1; they would be surfaced to the reviewer as
"this plan requires manual execution of X" notes, not executed by the plan.
This keeps the all-or-nothing promise honest. A self-transactioning action like
`close-registration` would need to be refactored to be transaction-composable
(take the repo/transaction as an argument) to be plan-eligible, or excluded.

The dry-run (`Hawk.Plans.preview/2`) executes the ops in a real transaction and
rolls back, so it has the *exact* fidelity of execution — including repo-level
constraints declared via the writer DSL's `constraint/2` step, which a no-op-repo
dry-run could not catch. The cost is that the dry-run touches the real database
(acquires locks for its duration, can fail on concurrency between preview and
commit); the review surface labels the result a *preview*, and execution
re-checks under the reviewer's authority.

## `Hawk.Multi`

A small Hawk-native transactional composer, stealing the *shape* of
`Ecto.Multi` (named steps, composable, inspectable, transactional, all-or-nothing
with prior-step results threaded forward) without using `Ecto.Multi` directly.
`Ecto.Multi`'s operations are raw `repo.insert/update/delete` that bypass
`Hawk.RepositoryBoundary` and the `policy_validated?` gate — the Write Invariant.
`Hawk.Multi`'s operations are Hawk-boundary-respecting: `create/3`,
`update/4`, `delete/3`, `action/5`, `run/3` (the escape hatch for computed args
and branching), `to_list/1` (inspect without running), `execute/3` (run in a
single `repo.transaction`, threading results, all-or-nothing).

The hard part — policy validation, changesets, persistence — is already in
`RepositoryBoundary`/`MutationContext`. `Hawk.Multi` just composes boundary
calls; it does not reimplement them. Every operation inside a `Hawk.Multi`
goes through `validate_policy` + `RepositoryBoundary`, the way a controller
does. No parallel write path.

`Hawk.Multi.run/3` (the escape hatch) runs Elixir at execute time under the
transaction, so the dry-run cannot fully predict its effects without executing
it. This matches `Ecto.Multi.run/3`'s semantics and is the one seam where
"deterministic execution" gets a degree of "computed at runtime." Accepted for
v1; the reviewer still sees the real dry-run effects.

## What this is not (the negatives that keep it honest)

- **Not a curated verb DSL.** No `Playbook` adapter module per resource. No
  named, pre-authored verbs. The LLM composes against the existing resource
  surface.
- **Not a planner/diff engine.** The AI authors the sequence; the runtime
  executes it. No desired-state diffing.
- **Not saga/compensation.** All-or-nothing transactional. No undo machinery.
- **Not Hawk-managed storage.** No Hawk migration. Plans are stored by the
  host app. Plan-lifecycle auth is the host app's decision.
- **Not a new authorization model.** Execution uses the existing per-resource
  `Policy` under the reviewer's existing `Hawk.Authority`. No `role: :llm`
  invented by Hawk; if the host app wants that, it is the host app's
  `plans` policy.
- **No AI in the execution loop.** The plan is a closed-form sequence of ops.
  On approval, `Hawk.Plans.run/3` executes deterministically.

## Build scope

Hawk ships (library), in this order, each independently shippable:

1. **`Hawk.Plans.Spec`** — the renderer over `Routes` + `Actions` + `Schema`
   metadata, `mix hawk.plans.spec` task, and an optional controller. The
   resource-shaped, authority-aware op manifest the LLM reads and the executor
   validates against.
2. **`Hawk.Multi`** — the transactional composer with rollback dry-run, reusable
   beyond plans.
3. **`Hawk.Plans.preview/2` and `Hawk.Plans.run/3`** — the dry-run and executor
   over `Hawk.Multi`, calling the facades under the reviewer's authority.

The host app ships (product):

4. A `plans` table + schema + migration.
5. A `plans` policy (create/approve authorization — the app's product decision).
6. The scratchpad controller + review UI, calling `Hawk.Plans.preview/2` and
   `Hawk.Plans.run/3`.

(1)-(3) are the library surface. (4)-(6) are where it becomes a product a host
app mounts, and are out of scope for Hawk itself — but this document is the
contract a host-app author builds against.
