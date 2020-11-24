defmodule Kvasir.PubSub.Protocol do
  @callback port :: pos_integer
  @callback secure_port :: pos_integer

  @callback handshake(transport :: term, socket :: term) ::
              {:ok, auth :: Kvasir.PubSub.credentials(), state :: term} | {:error, atom}

  @callback run(
              transport :: term,
              socket :: term,
              state :: term,
              server_state :: Kvasir.PubSub.server_state()
            ) :: :ok
end
