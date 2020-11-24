defmodule Kvasir.PubSub do
  @moduledoc """
  Documentation for `Kvasir.PubSub`.
  """
  alias Kvasir.PubSub.{Handler, Util}

  @type client :: struct

  @type credentials ::
          :anonymous
          | {:token, token :: String.t()}
          | {:user, user :: String.t()}
          | {:password, user :: String.t(), pass :: String.t()}

  @type server :: Kvasir.PubSub.Server.t()

  @type server_state :: {server, client}

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @protocol_defaults [secure: false, insecure: true]
  @protocol_opts ~w(cacert cert secure insecure)a

  def start_link(opts \\ []) do
    # Setup Server
    authorization = opts[:authorization] || Kvasir.PubSub.Authorization.None

    if authorization == Kvasir.PubSub.Authorization.None do
      require Logger
      Logger.warn("Kvasir PubSub: No Authorization Set")
    end

    source = opts[:source]
    unless source, do: raise("Kvasir PubSub: No PubSub protocols given.")

    server = %Kvasir.PubSub.Server{authorization: authorization, source: source}

    # Start protocols
    protocol_opts = Keyword.merge(@protocol_defaults, Keyword.take(opts, @protocol_opts))
    protocols = Enum.map(opts[:protocols] || [], &Util.protocol_config(&1, protocol_opts))
    children = Enum.map(protocols, fn {p, o} -> Handler.child_spec(p, server, o) end)

    if protocols == [], do: raise("Kvasir PubSub: No PubSub protocols given.")

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
