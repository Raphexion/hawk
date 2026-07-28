defmodule Videdal.Integration.PlansPreview.Schools.Reader do
  @moduledoc false
  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.School,
    policy: Videdal.Integration.PlansPreview.Schools.Policy

  filter(:id)
  sort(:id)
end
