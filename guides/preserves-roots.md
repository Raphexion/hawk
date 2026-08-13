# Understanding `preserves_roots`

`preserves_roots` tells Hawk whether a Reader attachment can remove rows from the resource being read.

Most applications should leave it at its safe default:

```elixir
preserves_roots: false
```

Set it to `true` only when you know that the attachment keeps every root row available to the rest of the query.

This guide explains why that matters, first at a high level and then in terms of SQL and Hawk's filter AST.

## The short version

Imagine that we are reading students:

```elixir
from(student in Student)
```

The students are the **root rows**. A Reader attachment may add schools to the query so that Hawk can filter by `school_name`:

```elixir
attach :school, when_filter: [:school_name] do
  join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
end
```

An inner join removes students who have no school. It therefore does **not** preserve roots.

```elixir
preserves_roots: false
```

A plain left join keeps students even when they have no school:

```elixir
attach :school, when_filter: [:school_name], preserves_roots: true do
  join(query, :left, [root: student], school in assoc(student, :school), as: :school)
end
```

That attachment preserves roots.

The distinction matters for `OR` filters. Consider:

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{student_id: ben.id}}
```

Ben should match the second branch even if he has no school. An inner join removes Ben before SQL evaluates the `OR`. A left join keeps Ben available, allowing the `student_id` branch to match him.

Hawk rejects the unsafe inner-join version rather than silently returning an incomplete result.

## What is a root?

The root is the main resource being read.

For this Reader:

```elixir
defmodule MyApp.Students.Reader do
  use Hawk.Reader.Resource,
    repo: MyApp.Repo,
    schema: MyApp.Student
end
```

`MyApp.Student` is the root schema, and student records are the root rows.

For a course Reader, courses are roots. For a booking Reader, bookings are roots. The association being attached is not the root:

```text
Student Reader
├── Student rows: roots
└── School rows: attached rows
```

`preserves_roots: true` means:

> After this attachment runs, every root row that was available before it is still available to later filters.

It does not mean that every root will be returned in the final result. Later filters may correctly remove rows. It only describes what the attachment itself does.

## A small SQL primer

Suppose we have these tables:

### Students

| id | name | school_id |
| --- | --- | --- |
| 1 | Ada | 10 |
| 2 | Ben | `NULL` |
| 3 | Cora | 20 |

### Schools

| id | name |
| --- | --- |
| 10 | Videdal School |
| 20 | North School |

Ben has no school.

### Inner join

An inner join keeps only students with a matching school:

```sql
SELECT students.*, schools.*
FROM students
INNER JOIN schools ON schools.id = students.school_id;
```

The intermediate result is:

| student | school |
| --- | --- |
| Ada | Videdal School |
| Cora | North School |

Ben has disappeared. The inner join is therefore not root-preserving.

### Left join

A left join keeps every student. School columns are `NULL` when no school exists:

```sql
SELECT students.*, schools.*
FROM students
LEFT JOIN schools ON schools.id = students.school_id;
```

The intermediate result is:

| student | school |
| --- | --- |
| Ada | Videdal School |
| Ben | `NULL` |
| Cora | North School |

Ben remains available to later filters. This plain left join is root-preserving.

## Why `OR` makes this important

SQL conceptually builds the joined rows before applying the `WHERE` predicate.

We want students whose school is Videdal School **or** whose student ID is 2:

```sql
WHERE schools.name = 'Videdal School'
   OR students.id = 2
```

The expected result is Ada and Ben.

### With an inner join

```sql
SELECT students.*
FROM students
INNER JOIN schools ON schools.id = students.school_id
WHERE schools.name = 'Videdal School'
   OR students.id = 2;
```

The join removes Ben first. By the time SQL checks `students.id = 2`, Ben is no longer present.

The incorrect result is only Ada.

### With a left join

```sql
SELECT students.*
FROM students
LEFT JOIN schools ON schools.id = students.school_id
WHERE schools.name = 'Videdal School'
   OR students.id = 2;
```

The left join keeps Ben. The first branch is false for Ben because `schools.name` is `NULL`, but the second branch is true.

The correct result is Ada and Ben.

## How this maps to Hawk

Hawk applies Reader attachments before compiling the filter predicate.

Given:

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{student_id: ben.id}}
```

Hawk performs these broad steps:

1. Notice that `school_name` triggers the `:school` attachment.
2. Apply the attachment to the Ecto query.
3. Compile the whole `OR` filter into a SQL predicate.
4. Run the query.

Step 2 can remove rows before step 3. That is why Hawk needs the `preserves_roots` declaration.

Hawk cannot inspect arbitrary Ecto code and reliably decide what it does. The attachment may contain joins, predicates, fragments, limits, or application helpers. The application therefore declares the invariant explicitly.

## The default is deliberately conservative

The default is:

```elixir
preserves_roots: false
```

This does not claim that every attachment removes roots. It means Hawk has not been given a guarantee that the attachment preserves them.

For example, this left join probably preserves roots:

```elixir
attach :school, when_filter: [:school_name] do
  join(query, :left, [root: student], school in assoc(student, :school), as: :school)
end
```

But without the explicit declaration, Hawk treats it conservatively as potentially non-preserving.

Once verified, annotate it:

```elixir
attach :school, when_filter: [:school_name], preserves_roots: true do
  join(query, :left, [root: student], school in assoc(student, :school), as: :school)
end
```

Do not add `preserves_roots: true` merely to silence an error. It is a correctness promise made by the application.

## Examples that are not root-preserving

### 1. An inner join

```elixir
attach :school, when_filter: [:school_name] do
  join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
end
```

A student without a school is removed.

Keep the default:

```elixir
preserves_roots: false
```

### 2. A left join followed by a predicate on the attached row

A left join alone can preserve roots, but additional code can make the whole attachment non-preserving:

```elixir
attach :school, when_filter: [:school_name] do
  query
  |> join(:left, [root: student], school in assoc(student, :school), as: :school)
  |> where([school: school], school.active == true)
end
```

Students without a school get `NULL` school columns. `school.active == true` is not true for those rows, so they are removed.

This attachment does not preserve roots.

### 3. A predicate on the root itself

```elixir
attach :school, when_filter: [:school_name] do
  query
  |> join(:left, [root: student], school in assoc(student, :school), as: :school)
  |> where([root: student], student.active == true)
end
```

Inactive students are removed by the attachment. The fact that the join is left does not make the complete transformation root-preserving.

### 4. A helper whose behavior is unclear

```elixir
attach :school, when_filter: [:school_name] do
  query
  |> attach_school()
  |> only_visible_records()
end
```

Do not mark this as preserving until you have checked what both helpers do. The option describes the complete attachment block, not merely the join type.

### 5. Limits or other row-reducing transformations

```elixir
attach :school, when_filter: [:school_name] do
  query
  |> join(:left, [root: student], school in assoc(student, :school), as: :school)
  |> limit(100)
end
```

A limit can prevent some roots from reaching the later predicate. Treat row-limiting, grouping, and similar transformations as non-preserving unless their behavior has been carefully proven for this query shape.

## Examples that are usually root-preserving

### 1. A plain optional `belongs_to` left join

```elixir
attach :school, when_filter: [:school_name], preserves_roots: true do
  join(query, :left, [root: student], school in assoc(student, :school), as: :school)
end
```

Students without schools remain in the query.

### 2. A chain of plain left joins

```elixir
attach :municipality, when_filter: [:municipality_name], preserves_roots: true do
  query
  |> join(:left, [root: student], school in assoc(student, :school), as: :school)
  |> join(:left, [school: school], municipality in assoc(school, :municipality), as: :municipality)
end
```

This can preserve students even when either association is missing, provided the attachment adds no predicates or other row-reducing transformations.

Check the generated SQL and test missing associations before making the promise.

### 3. A left join used by one side of an `OR`

```elixir
attach :school, when_filter: [:school_name], preserves_roots: true do
  join(query, :left, [root: student], school in assoc(student, :school), as: :school)
end

filter :school_name do
  fn {:eq, name} ->
    dynamic([school: school], school.name == ^name)
  end
end
```

This supports:

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{student_id: ben.id}}
```

The attachment retains Ben so the root-local `student_id` branch can match.

## A left join is not automatically safe

A common mistake is to see `join(query, :left, ...)` and immediately add `preserves_roots: true`.

Always judge the whole attachment:

```elixir
attach :school, when_filter: [:school_name], preserves_roots: true do
  query
  |> join(:left, [root: student], school in assoc(student, :school), as: :school)
  |> some_other_transformation()
end
```

The declaration is correct only if `some_other_transformation/1` also preserves every root.

Ask:

- Can a root with no associated row survive?
- Can a root with an associated row that fails some condition survive?
- Does the block add any `where`, `having`, `limit`, or row-reducing fragment?
- Do called helpers add such behavior?

If uncertain, leave the default `false`.

## Preserving roots is not the same as preserving uniqueness

A left join to a to-many association can keep every root while producing more than one row per root.

Suppose Ada has two guardians:

| student | guardian |
| --- | --- |
| Ada | Grace |
| Ada | Linus |

This left join preserves Ada, but Ada appears twice in the joined result:

```elixir
attach :guardians, when_filter: [:guardian_name], preserves_roots: true do
  join(query, :left, [root: student], guardian in assoc(student, :guardians), as: :guardian)
end
```

`preserves_roots: true` promises inclusion, not cardinality:

```text
Root preservation: no student disappears
Uniqueness: each student appears only once
```

Those are separate concerns. Depending on the query, a to-many attachment may require `distinct`, aggregation, or a different filtering strategy. Do not read `preserves_roots: true` as “this join cannot duplicate rows.”

## Safe and unsafe boolean filters

Hawk checks each non-preserving attachment against the complete effective filter.

### Unsafe: only one `OR` branch requires the attachment

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{student_id: ben.id}}
```

The first branch needs `:school`; the second does not. A non-preserving school attachment is unsafe.

Hawk raises an error similar to:

```text
unsafe reader attach :school for OR filter keys [[:school_name], [:student_id]];
the attach may remove roots before the OR predicate is evaluated
```

### Safe: both `OR` branches require the attachment

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{school_name: "North School"}}
```

Every matching path requires a school. An inner school join cannot remove a student who would otherwise satisfy either branch, assuming `school_name` really requires the attachment whenever it matches.

A non-preserving attachment is allowed.

### Safe: a normal `AND`

```elixir
{:and,
  %{school_name: "Videdal School"},
  %{active: true}}
```

Every result must satisfy `school_name`, so every result requires the school attachment. An inner join is compatible with this filter.

Map shorthand also represents an `AND`:

```elixir
%{school_name: "Videdal School", active: true}
```

### Safe: an enclosing `AND` requires the attachment

```elixir
{:and,
  %{school_name: "Videdal School"},
  {:or,
    %{active: true},
    %{student_id: ben.id}}}
```

At first glance, the inner `OR` has branches that do not mention school. But the outer `AND` requires `school_name` for every result. Therefore every satisfiable path through the whole filter requires the school attachment.

Hawk analyzes the whole AST rather than rejecting each nested `OR` in isolation.

### Safe: a policy or forced filter requires the attachment

Hawk combines three filter sources:

1. the caller's filter,
2. the policy's read filter,
3. the Reader's forced filter.

They are combined with `AND`. A policy may require `school_name` for every visible row while the caller uses an `OR`:

```elixir
# Policy filter
%{school_name: "Videdal School"}

# Caller filter
{:or, %{active: true}, %{student_id: ben.id}}
```

The effective filter is conceptually:

```elixir
{:and,
  %{school_name: "Videdal School"},
  {:or, %{active: true}, %{student_id: ben.id}}}
```

Every result still requires the school attachment, so a non-preserving attachment is safe for this effective filter.

### Two different attachments across `OR`

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{guardian_name: "Grace"}}
```

Suppose `school_name` triggers `:school` and `guardian_name` triggers `:guardians`.

For the school attachment, the guardian branch does not require school. For the guardians attachment, the school branch does not require guardians. Both non-preserving attachments are unsafe.

Possible fixes include using verified root-preserving attachments for both associations or choosing a query design that keeps each association condition local to its branch.

## The `when_filter` contract

An attachment declares which filter keys trigger it:

```elixir
attach :school, when_filter: [:school_name] do
  # ...
end
```

That declaration also means:

> Whenever `school_name` can match rows, it genuinely requires the `:school` attachment.

This custom filter satisfies that contract:

```elixir
filter :school_name do
  fn {:eq, name} ->
    dynamic([school: school], school.name == ^name)
  end
end
```

This one does not:

```elixir
filter :school_name do
  fn
    {:eq, ""} -> :all
    {:eq, name} -> dynamic([school: school], school.name == ^name)
  end
end
```

For an empty value, the key is present and triggers the attachment, but the handler says every row matches. A non-preserving attachment could then remove rows even though the filter itself requires nothing from the school.

Hawk rejects `:all` from a custom handler whose key triggers an attachment. The handler is evaluated once during normal filter compilation.

`:none` is different:

```elixir
filter :school_name do
  fn
    {:eq, ""} -> :none
    {:eq, name} -> dynamic([school: school], school.name == ^name)
  end
end
```

`:none` cannot match any roots, so an attachment cannot remove a result that the filter would have returned.

## Reader and FilterSet attachments behave the same way

A Reader-local attachment:

```elixir
defmodule MyApp.Students.Reader do
  use Hawk.Reader.Resource, repo: MyApp.Repo, schema: MyApp.Student

  attach :school, when_filter: [:school_name], preserves_roots: true do
    join(query, :left, [root: student], school in assoc(student, :school), as: :school)
  end
end
```

A FilterSet attachment:

```elixir
defmodule MyApp.Students.SchoolFilters do
  use Hawk.Reader.FilterSet, schema: MyApp.Student

  attach :school, when_filter: [:school_name], preserves_roots: true do
    join(query, :left, [root: student], school in assoc(student, :school), as: :school)
  end
end
```

Both produce the same attachment metadata and follow the same OR-safety rules. `FilterSet.apply_to/2` also performs the safety check when a set is tested independently.

## What about sorting?

Reader attachments may also be triggered by sorting:

```elixir
attach :school,
  when_filter: [:school_name],
  when_sort: [:school_name] do
  join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
end
```

A rule triggered only by sorting follows the Reader's existing sorting semantics. The OR guard is specifically about attachments activated by filter branches.

Sorting does not make an unsafe filter safe. If the same non-preserving rule is triggered by both sorting and this filter:

```elixir
{:or,
  %{school_name: "Videdal School"},
  %{student_id: ben.id}}
```

Hawk still rejects it. The attachment runs before the predicate whether it was activated by filtering, sorting, or both, and the inner join can still remove Ben.

## Choosing the right value

Use this checklist.

### Keep `preserves_roots: false` when

- the attachment uses an inner join;
- the attachment adds a predicate that can exclude roots;
- a helper in the attachment may exclude roots;
- it applies a limit or another row-reducing transformation;
- you have not verified its behavior for missing associations;
- you are unsure.

Because `false` is the default, it is normally clearest to omit it:

```elixir
attach :school, when_filter: [:school_name] do
  join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
end
```

### Use `preserves_roots: true` when

- every root remains available after the complete attachment;
- roots with missing associations remain available;
- the block and every helper it calls avoid root-reducing predicates;
- you have a test covering a root with no associated row;
- you understand that duplicate roots are a separate issue.

Typical example:

```elixir
attach :school, when_filter: [:school_name], preserves_roots: true do
  join(query, :left, [root: student], school in assoc(student, :school), as: :school)
end
```

## Testing an attachment

A useful integration test needs at least:

1. a root matching through the attached association;
2. a root with no associated row;
3. an `OR` whose other branch matches that association-less root.

For example:

```elixir
test "school attachment preserves roots across OR" do
  school = insert(:school, name: "Videdal School")
  school_match = insert(:student, school_id: school.id)
  identity_match = insert(:student, school_id: nil)

  filter =
    {:or,
      %{school_name: "Videdal School"},
      %{student_id: identity_match.id}}

  results = Reader.all(authority: Hawk.Authority.system(), filter: filter)

  assert MapSet.new(results, & &1.id) ==
           MapSet.new([school_match.id, identity_match.id])
end
```

This test proves more than inspecting the Ecto query. It demonstrates that the root without an association survives and can match the other branch.

For a non-preserving attachment, test that Hawk raises:

```elixir
assert_raise ArgumentError, ~r/unsafe reader attach :school/, fn ->
  Reader.all(
    authority: Hawk.Authority.system(),
    filter:
      {:or,
        %{school_name: "Videdal School"},
        %{student_id: student.id}}
  )
end
```

Also test the allowed case where every branch requires the same attachment:

```elixir
results =
  Reader.all(
    authority: Hawk.Authority.system(),
    filter:
      {:or,
        %{school_name: "Videdal School"},
        %{school_name: "North School"}}
  )
```

## Responding to Hawk's safety error

When Hawk reports an unsafe attachment, use this order:

### 1. Check whether the attachment is genuinely root-preserving

If it is a plain left join and the complete block cannot remove roots, add:

```elixir
preserves_roots: true
```

Then add a test with a missing association.

### 2. If it is not preserving, do not relabel it

An inner join does not become safe because the option says `true`. The declaration would only hide the guard while leaving the wrong result.

Consider whether a left join correctly represents the intended query.

### 3. Check the filter's meaning

Sometimes the other `OR` branch was unintended, or the business rule actually requires the association for every result. Restructure the filter only when that matches the real requirement.

### 4. Consider a different query design

Some association predicates are better represented by branch-local `EXISTS` subqueries rather than global joins. Hawk does not infer that rewrite from arbitrary attachment code. If a plain left join is unsuitable, a dedicated custom query design may be clearer than weakening the invariant.

## Low-level safety rule

For each non-root-preserving attachment triggered by filter keys, Hawk asks whether every satisfiable path through the effective filter requires that attachment.

The recursive rule is:

```text
requires(:all)  = false
requires(:none) = true
requires(map)   = map keys intersect the attachment's when_filter keys
requires(AND)   = requires(left) OR requires(right)
requires(OR)    = requires(left) AND requires(right)
```

Why these values?

- `:all` matches without using any attachment, so it does not require one.
- `:none` cannot match a root, so it cannot provide a path that an attachment might incorrectly remove.
- An `AND` requires the attachment if either side requires it, because every result must satisfy both sides.
- An `OR` requires the attachment only if both sides require it, because a result may satisfy either side.

If the attachment is active but the complete filter does not require it, Hawk raises before applying the query transformation.

This analysis uses the effective filter after caller, policy, and forced filters have been combined. That is why an enclosing policy or forced `AND` can make a nested caller `OR` safe.

## Final rule of thumb

Use this sentence when reviewing an attachment:

> Could a root that should match some other filter branch disappear merely because this attachment ran first?

If yes—or if you cannot confidently answer—leave `preserves_roots` as `false`.

If every root remains available after the complete attachment, mark it `preserves_roots: true` and prove the important missing-association case with a test.
