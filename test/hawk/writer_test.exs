defmodule Hawk.WriterTest.DslProbe.Repo do
  @moduledoc false
  alias Ecto.Changeset

  def insert(%Changeset{} = cs, _opts) do
    case Process.get({__MODULE__, :unique_violation}) do
      true ->
        {:error,
         Changeset.add_error(cs, :email, "has already been taken",
           constraint: :unique,
           name: :dsl_probe_email_idx
         )}

      _ ->
        {:ok, Changeset.apply_changes(cs)}
    end
  end

  def transaction(fun), do: {:ok, fun.()}
end

defmodule Hawk.WriterTest.DslProbe.Policy do
  @moduledoc false
  use Hawk.Policy

  read do
    role(:system, :all)
  end

  write(roles: [:system])
end

defmodule Hawk.WriterTest.DslProbe.Model do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dsl_probe" do
    field(:email, :string)
  end
end

defmodule Hawk.WriterTest.DslProbe.Writer do
  @moduledoc false
  use Hawk.Writer.Resource,
    model: Hawk.WriterTest.DslProbe.Model,
    repo: Hawk.WriterTest.DslProbe.Repo,
    policy: Hawk.WriterTest.DslProbe.Policy

  create do
    cast([:email])
    validate_required([:email])
    constraint(:unique, :email, name: :dsl_probe_email_idx, message: "already exists")
  end

  update do
    cast([:email])
  end

  delete(:default)
end

defmodule Hawk.WriterTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Hawk.{Authority, Errors, MutationContext, Writer}
  alias Videdal.Student

  @school_id Videdal.school_id()

  describe "changeset/2" do
    test "extracts a validation changeset without persisting" do
      changeset =
        %Student{}
        |> context(%{name: ""})
        |> Writer.cast([:name])
        |> Writer.validate_required([:name])
        |> Writer.changeset()

      assert %Changeset{action: :validate, valid?: false} = changeset
      assert changeset.errors[:name] == {"can't be blank", [validation: :required]}
    end
  end

  describe "defaults/2" do
    test "puts defaults only when attrs are missing" do
      context =
        %Student{}
        |> context(%{name: "Ada", active: false})
        |> Writer.defaults(active: true, school_id: @school_id)

      assert context.attrs == %{name: "Ada", active: false, school_id: @school_id}
    end

    test "evaluates zero-arity function defaults only when used" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.defaults(school_id: fn -> @school_id end)

      assert context.attrs.school_id == @school_id
    end

    test "is guarded" do
      context =
        %Student{}
        |> context(%{})
        |> MutationContext.add_error(:name, "can't be blank")

      assert Writer.defaults(context, name: "Ada") == context
    end
  end

  describe "cast/2" do
    test "casts permitted attrs into the changeset" do
      context =
        %Student{}
        |> context(%{name: "Ada", active: "false", school_id: @school_id, ignored: "value"})
        |> Writer.cast([:name, :active, :school_id])

      assert context.error == :none
      assert Changeset.get_change(context.changeset, :name) == "Ada"
      assert Changeset.get_change(context.changeset, :active) == false
      assert Changeset.get_change(context.changeset, :school_id) == @school_id
      refute Changeset.get_change(context.changeset, :ignored)
    end

    test "marks the context invalid when casting fails" do
      context =
        %Student{}
        |> context(%{active: "not-a-boolean"})
        |> Writer.cast([:active])

      assert context.error == :invalid
      assert {"is invalid", _opts} = context.changeset.errors[:active]
    end
  end

  describe "validate_required/2" do
    test "keeps the context valid when required fields are present" do
      context =
        %Student{}
        |> context(%{name: "Ada", school_id: @school_id})
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_required([:name, :school_id])

      assert context.error == :none
    end

    test "marks the context invalid when required fields are missing" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_required([:name, :school_id])

      assert context.error == :invalid
      assert {"can't be blank", _opts} = context.changeset.errors[:school_id]
    end

    test "accepts Ecto validate_required options" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_required([:school_id], message: "School is required")

      assert context.error == :invalid
      assert {"School is required", _opts} = context.changeset.errors[:school_id]
    end
  end

  describe "validate_changeset/2" do
    test "runs native Ecto changeset validators and keeps valid contexts valid" do
      context =
        %Student{}
        |> context(%{name: "Ada", school_id: @school_id})
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_changeset(&Changeset.validate_required(&1, [:name, :school_id]))

      assert context.error == :none
    end

    test "marks the context invalid when the changeset validator fails" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_changeset(&Changeset.validate_required(&1, [:name, :school_id]))

      assert context.error == :invalid
      assert {"can't be blank", _opts} = context.changeset.errors[:school_id]
    end

    test "does not run later changeset validators after a previous context error" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_required([:school_id])
        |> Writer.validate_changeset(fn _changeset -> flunk("validator should not run") end)

      assert context.error == :invalid
      assert {"can't be blank", _opts} = context.changeset.errors[:school_id]
    end

    test "marks a previously invalid changeset as invalid without replacing the first error" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Map.update!(:changeset, &Changeset.add_error(&1, :name, "first error"))
        |> Writer.validate_changeset(fn _changeset -> flunk("validator should not run") end)

      assert context.error == :invalid
      assert {"first error", _opts} = context.changeset.errors[:name]
    end
  end

  describe "normalize/2" do
    test "trims changed string fields and converts blank strings to nil" do
      context =
        %Student{}
        |> context(%{name: "  Ada  "})
        |> Writer.cast([:name])
        |> Writer.normalize([:name])

      assert Changeset.get_change(context.changeset, :name) == "Ada"

      blank_context =
        %Student{}
        |> context(%{name: "   "})
        |> Writer.cast([:name])
        |> Writer.normalize([:name])

      assert Changeset.get_change(blank_context.changeset, :name) == nil
    end

    test "does not normalize fields that were not cast" do
      context =
        %Student{}
        |> context(%{name: "  Ada  "})
        |> Writer.cast([])
        |> Writer.normalize([:name])

      refute Changeset.get_change(context.changeset, :name)
    end

    test "accepts a custom normalization function" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.cast([:name])
        |> Writer.normalize([:name], &String.upcase/1)

      assert Changeset.get_change(context.changeset, :name) == "ADA"
    end
  end

  describe "validate/2" do
    test "accepts ok validators" do
      context =
        %Student{}
        |> context(%{})
        |> Writer.validate(fn _context -> :ok end)

      assert context.error == :none
    end

    test "accepts a single field error" do
      context =
        %Student{}
        |> context(%{})
        |> Writer.validate(fn _context -> {:error, :name, "is reserved"} end)

      assert context.error == :invalid
      assert context.changeset.errors[:name] == {"is reserved", []}
    end

    test "accepts a list of field errors" do
      context =
        %Student{}
        |> context(%{})
        |> Writer.validate(fn _context ->
          [
            {:error, :name, "is reserved"},
            {:error, :school_id, "is unavailable"}
          ]
        end)

      assert context.error == :invalid
      assert context.changeset.errors[:name] == {"is reserved", []}
      assert context.changeset.errors[:school_id] == {"is unavailable", []}
    end

    test "raises when custom validators return an unsupported shape" do
      context = context(%Student{}, %{})

      assert_raise ArgumentError, ~r/unsupported validator result/, fn ->
        Writer.validate(context, fn _context -> :bad end)
      end
    end

    test "is guarded" do
      context =
        %Student{}
        |> context(%{})
        |> MutationContext.add_error(:name, "can't be blank")

      assert Writer.validate(context, fn _context -> flunk("validator should not run") end) ==
               context
    end
  end

  describe "constraint/4" do
    test "attaches a unique constraint to the context changeset" do
      context =
        %Student{}
        |> context(%{name: "Ada"})
        |> Writer.cast([:name])
        |> Writer.constraint(:unique, :name, name: :students_name_index, message: "already exists")

      assert context.error == :none

      assert context.changeset.constraints == [
               %{
                 match: :exact,
                 type: :unique,
                 constraint: "students_name_index",
                 error_type: :unique,
                 field: :name,
                 error_message: "already exists"
               }
             ]
    end

    test "attaches a foreign_key constraint" do
      context =
        %Student{}
        |> context(%{school_id: @school_id})
        |> Writer.cast([:school_id])
        |> Writer.constraint(:foreign_key, :school_id, name: :students_school_id_fkey)

      assert context.error == :none

      assert context.changeset.constraints == [
               %{
                 match: :exact,
                 type: :foreign_key,
                 constraint: "students_school_id_fkey",
                 error_type: :foreign,
                 field: :school_id,
                 error_message: "does not exist"
               }
             ]
    end

    test "is guarded by an earlier error" do
      context =
        %Student{}
        |> context(%{})
        |> MutationContext.add_error(:name, "can't be blank")

      assert Writer.constraint(context, :unique, :name, name: :idx) == context
    end

    test "rejects an unknown constraint kind" do
      context = %Student{} |> context(%{name: "Ada"}) |> Writer.cast([:name])

      assert_raise KeyError, fn -> Writer.constraint(context, :bogus, :name, []) end
    end
  end

  describe "constraint/2 DSL step" do
    alias Hawk.WriterTest.DslProbe.{Repo, Writer}

    test "a unique violation renders through the error pipeline at the external pointer" do
      # The DSL step desugars to validate_changeset(fn cs -> unique_constraint(cs, :email) end).
      # The probe repo reflects a unique violation back into the changeset, proving
      # the whole pipeline: DSL -> constraint attachment -> repo error -> Errors.to_json_api.
      Process.put({Repo, :unique_violation}, true)

      result = Writer.create(%{email: "dup@example.com"}, Authority.system())

      assert {:invalid, _context} = result

      assert %{errors: [error]} = Errors.to_json_api(result)
      assert error.code == "invalid"
      assert error.source == %{pointer: "/data/attributes/email"}
      # The repo violation's error message ("has already been taken") overrides the
      # constraint's declared message ("already exists"); that's standard Ecto behavior.
      assert error.detail =~ "already been taken"
    end
  end

  defp context(model, attrs) do
    MutationContext.create(model, attrs, Authority.system())
  end
end
