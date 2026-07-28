defmodule Videdal.Integration.PlansPreview.Schools.JsonApi do
  @moduledoc false
  use Hawk.JsonApi.Resource

  type("preview-schools")
  attribute(:name, writable: true)
end
