defmodule Hawk.JsonApi.PresentationBehaviour do
  @moduledoc "Contract implemented by every JSON:API presentation module."

  @callback __hawk_json_api__() :: map()
end
