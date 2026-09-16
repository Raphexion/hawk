defmodule Hawk.Token.Verifier do
  @moduledoc """
  Behaviour for application-owned access-token verification.

  Implementations must return a fully-authorized `Hawk.Authority`; callers must
  not infer authorization from an unverified token payload.
  """

  alias Hawk.Authority

  @callback verify(String.t(), keyword()) :: {:ok, Authority.t()} | {:error, :invalid_token}
end
