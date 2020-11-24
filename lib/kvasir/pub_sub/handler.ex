defmodule Kvasir.PubSub.Handler do
  require Logger
  import Kvasir.PubSub.Util

  @spec child_spec(module, Kvasir.PubSub.server(), Keyword.t()) :: Supervisor.child_spec()
  def child_spec(protocol, server, opts \\ []) do
    %{
      id: protocol,
      type: :supervisor,
      start: {__MODULE__, :start_handler_link, [protocol, server, opts]}
    }
  end

  def start_handler_link(protocol, server, opts) do
    children =
      if Keyword.get(opts, :insecure, false),
        do: [
          :ranch.child_spec(
            :insecure,
            :ranch_tcp,
            recommended_listener_config(protocol, opts),
            __MODULE__,
            {protocol, server}
          )
        ],
        else: []

    children =
      if Keyword.get(opts, :secure, false),
        do: [
          :ranch.child_spec(
            :secure,
            :ranch_ssl,
            recommended_secure_listener_config(protocol, opts),
            __MODULE__,
            {protocol, server}
          )
          | children
        ],
        else: children

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @behaviour :ranch_protocol

  @impl :ranch_protocol
  def start_link(ref, transport, opts) do
    {:ok, spawn_link(__MODULE__, :init, [ref, transport, opts])}
  end

  def init(ref, transport, opts) do
    {:ok, socket} = :ranch.handshake(ref)

    {protocol, server} = opts

    with {:ok, auth, state} <- protocol.handshake(transport, socket),
         {:ok, client} <- server.authorization.authorize(auth) do
      _ = client
      _ = state
      run(protocol, transport, socket, state, {server, client})
    else
      err ->
        transport.close(socket)

        msg = "Kvasir PubSub: Failed to initialize connection: #{inspect(err)}"

        Logger.error(msg)
        raise msg
    end
  end

  def run(protocol, transport, socket, state, server_state) do
    protocol.run(transport, socket, state, server_state)
  after
    transport.close(socket)
  end

  def listen(server_state, topic, events, callback)

  def listen(
        {%Kvasir.PubSub.Server{authorization: auth, source: source}, client},
        topic,
        events,
        callback
      ) do
    case source.__topics__()[topic] do
      %{events: es} ->
        if Enum.all?(events, &(&1 in es)) do
          if auth.allowed?(topic, events, client) do
            source.listen(topic, callback, only: events)
          else
            {:error, :not_authorized}
          end
        else
          {:error, :invalid_events}
        end

      _ ->
        {:error, :invalid_topic}
    end
  end
end
