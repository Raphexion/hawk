defmodule Videdal.Repo.Migrations.AddDeletedAtToStudents do
  use Ecto.Migration

  def change do
    alter table(:students) do
      add :deleted_at, :utc_datetime
    end

    create index(:students, [:deleted_at])
  end
end
