defmodule Videdal.Integration.PlansPreview.Schools do
  @moduledoc false
  use Hawk.Resource,
    model: Videdal.School,
    live_view: false
end
