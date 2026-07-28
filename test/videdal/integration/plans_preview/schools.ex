defmodule Videdal.Integration.PlansPreview.Schools do
  @moduledoc false
  use Hawk.Resource,
    model: Videdal.School,
    live_view: false

  defmodule Reader do
    @moduledoc false
    use Hawk.Reader.Resource,
      repo: Videdal.SandboxRepo,
      schema: Videdal.School,
      policy: Videdal.Integration.PlansPreview.Schools.Policy

    filter(:id)
    sort(:id)
  end

  defmodule Policy do
    @moduledoc false
    use Hawk.Policy

    read do
      role(:system, :all)
    end

    write(roles: [:system])
  end

  defmodule JsonApi do
    @moduledoc false
    use Hawk.JsonApi.Resource

    type("preview-schools")
    attribute(:name, writable: true)
  end

  defmodule Writer do
    @moduledoc false
    use Hawk.Writer.Resource,
      model: Videdal.School,
      repo: Videdal.SandboxRepo,
      policy: Videdal.Integration.PlansPreview.Schools.Policy

    create do
      cast([:name])
      validate_required([:name])
    end

    update do
      cast([:name])
    end

    delete(:default)
  end
end
