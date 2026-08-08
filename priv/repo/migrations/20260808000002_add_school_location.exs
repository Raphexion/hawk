defmodule Videdal.Repo.Migrations.AddSchoolLocation do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS postgis"
    execute "ALTER TABLE schools ADD COLUMN location geography(Point, 4326)"
    execute "CREATE INDEX schools_location_gist_index ON schools USING GIST (location)"
  end

  def down do
    execute "DROP INDEX IF EXISTS schools_location_gist_index"
    execute "ALTER TABLE schools DROP COLUMN IF EXISTS location"
  end
end
