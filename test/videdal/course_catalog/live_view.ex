defmodule Videdal.CourseCatalog.LiveView do
  @moduledoc false

  use Hawk.LiveView.Resource

  as(:course)
  plural_as(:courses)
end
