defmodule Videdal.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def up do
    create table(:schools, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
    end

    create table(:students, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :active, :boolean, null: false, default: true
      add :school_id, references(:schools, type: :uuid)
    end

    create table(:teachers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :school_id, references(:schools, type: :uuid)
    end

    create table(:parents, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :school_id, references(:schools, type: :uuid)
    end

    create table(:parent_students, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :school_id, references(:schools, type: :uuid)
      add :parent_id, references(:parents, type: :uuid)
      add :student_id, references(:students, type: :uuid)
    end

    create table(:courses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :text, null: false
      add :registration_state, :text, null: false, default: "draft"
      add :seat_count, :integer, null: false, default: 0
      add :waitlist_count, :integer, null: false, default: 0
      add :school_id, references(:schools, type: :uuid)
      add :teacher_id, references(:teachers, type: :uuid)
    end

    create table(:enrollments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :enrolled_on, :date
      add :registration_status, :text, null: false, default: "pending"
      add :school_id, references(:schools, type: :uuid)
      add :student_id, references(:students, type: :uuid)
      add :course_id, references(:courses, type: :uuid)
    end

    create table(:grades, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :score, :integer, null: false
      add :school_id, references(:schools, type: :uuid)
      add :student_id, references(:students, type: :uuid)
      add :course_id, references(:courses, type: :uuid)
    end

    create table(:course_rosters, primary_key: false) do
      add :course_id, :uuid, primary_key: true
      add :title, :text
      add :enrollment_count, :integer, default: 0
    end

    execute """
    CREATE VIEW course_grade_summaries AS
    SELECT
      course_id AS id,
      school_id,
      course_id,
      count(*)::integer AS grade_count,
      avg(score)::float AS average_score
    FROM grades
    GROUP BY school_id, course_id
    """
  end

  def down do
    execute "DROP VIEW IF EXISTS course_grade_summaries"
    drop table(:course_rosters)
    drop table(:grades)
    drop table(:enrollments)
    drop table(:courses)
    drop table(:parent_students)
    drop table(:parents)
    drop table(:teachers)
    drop table(:students)
    drop table(:schools)
  end
end
