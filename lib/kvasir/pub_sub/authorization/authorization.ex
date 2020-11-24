defmodule Kvasir.PubSub.Authorization do
  @callback authorize(Kvasir.PubSub.credentials()) ::
              {:ok, Kvasir.PubSub.client()} | {:error, atom}
  @callback allowed?(topic :: String.t(), events :: [String.t()], Kvasir.PubSub.client()) ::
              boolean
end
