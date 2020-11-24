defmodule Kvasir.PubSub.Authorization.None do
  @behaviour Kvasir.PubSub.Authorization

  @impl Kvasir.PubSub.Authorization
  def authorize(_), do: {:ok, nil}

  @impl Kvasir.PubSub.Authorization
  def allowed?(_topic, _events, nil), do: true
end
