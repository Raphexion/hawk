defmodule Hawk.Reader.Page do
  @moduledoc """
  A bounded Reader page with continuation metadata.

  `entries` never contains the internal look-ahead row. `next_cursor` is an
  opaque forward cursor tied to the page's effective sort.
  """

  @enforce_keys [:entries, :has_more?, :page]
  defstruct [:entries, :has_more?, :next_cursor, :page]

  @type t :: %__MODULE__{
          entries: [struct()],
          has_more?: boolean(),
          next_cursor: String.t() | nil,
          page: map()
        }
end
