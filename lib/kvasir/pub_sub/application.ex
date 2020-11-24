defmodule Kvasir.PubSub.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # {Kvasir.PubSub, protocols: [:mqtt]}
    ]

    opts = [strategy: :one_for_one, name: Kvasir.PubSub.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
