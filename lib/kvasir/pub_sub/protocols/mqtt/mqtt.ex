defmodule Kvasir.PubSub.Protocols.MQTT do
  alias __MODULE__.V5
  @behaviour Kvasir.PubSub.Protocol

  @impl Kvasir.PubSub.Protocol
  def port, do: 1883

  @impl Kvasir.PubSub.Protocol
  def secure_port, do: 8883

  @impl Kvasir.PubSub.Protocol
  def handshake(transport, socket) do
    case __MODULE__.read(transport, socket) do
      {:ok, {:mqtt, :connect, {version, flags, opts}}} ->
        u = opts[:username]
        p = opts[:password]

        auth =
          cond do
            is_nil(u) -> :anonymous
            is_nil(p) -> {:user, u}
            :auth -> {:password, u, p}
          end

        {:ok, auth, %{flags: flags, version: version, opts: opts}}

      _ ->
        {:error, :no_mqtt_connect}
    end
  end

  @impl Kvasir.PubSub.Protocol
  @spec run(
          transport :: term,
          socket :: term,
          state :: term,
          server_state :: Kvasir.PubSub.server_state()
        ) :: :ok
  def run(transport, socket, state = %{opts: opts}, server_state) do
    state =
      if opts[:client_id] == :requested do
        client_id = Base.encode16(:crypto.strong_rand_bytes(8), padding: false, case: :lower)
        %{state | opts: Keyword.put(opts, :client_id, client_id)}
      else
        state
      end

    write(transport, socket, {:mqtt, :connack, client_id: state.opts[:client_id]})
    do_run(transport, socket, state, server_state)
  end

  defp do_run(transport, socket, state, server_state) do
    timeout = (Keyword.get(state.opts, :keep_alive, 60) + 5) * 1_000

    with {:ok, mqtt} <- __MODULE__.read(transport, socket, timeout) do
      case mqtt do
        {:mqtt, :subscribe, payload} ->
          id = payload[:id]
          subs = payload[:subscriptions]
          {:ok, groups} = subscribe(subs, server_state)

          write(
            transport,
            socket,
            {:mqtt, :suback,
             id: id,
             subscriptions:
               Enum.map(groups, fn %{group: g} ->
                 if(g, do: :granted_qos_1, else: :granted_qos_0)
               end)}
          )

          start_listen(transport, socket, id, groups, server_state)

        {:mqtt, :pingreq} ->
          write(transport, socket, {:mqtt, :pingresp})

        {:ok, x} ->
          IO.inspect(x, label: "Unknown")
      end

      do_run(transport, socket, state, server_state)
    else
      err ->
        IO.inspect(err, label: "Error")
        :ok
    end
  end

  defp start_listen(transport, socket, id, groups, server_state)

  defp start_listen(transport, socket, id, groups, _server_state = {%{source: source}, _client}) do
    groups
    |> Enum.reject(& &1.group)
    |> Enum.each(fn group ->
      source.listen(
        group.topic,
        fn event ->
          write(
            transport,
            socket,
            {:mqtt, :publish,
             id: id,
             content_type: "application/json",
             topic: group.topic,
             qos: 0,
             payload: Jason.encode!(event)}
          )

          :ok
        end,
        only: group.events,
        events: group.events
      )
    end)
  end

  defp subscribe(subscriptions, _server_state = {%{source: source}, _client}) do
    with {:ok, parsed} <-
           EnumX.reduce_while(subscriptions, %{}, fn {subscription, _opts}, acc ->
             with {:ok, sub} <- parse_subscription(subscription, source) do
               {:ok,
                Map.update(
                  acc,
                  {sub.topic, sub.group},
                  sub,
                  &%{&1 | events: Enum.uniq(&1.events ++ sub.events)}
                )}
             end
           end),
         groups <- Map.values(parsed) do
      {:ok, groups}
    end
  end

  defp parse_subscription(subscription, source)

  defp parse_subscription("$shared/" <> subscription, source) do
    with [group, topic | selector] <- String.split(subscription, "/"),
         t when t != nil <- source.__topics__()[topic],
         e when e != [] <- find_events(t.events, selector) do
      {:ok, %{group: group, topic: topic, events: e}}
    else
      _ -> {:error, :invalid_subscription}
    end
  end

  defp parse_subscription(subscription, source) do
    with [topic | selector] <- String.split(subscription, "/"),
         t when t != nil <- source.__topics__()[topic],
         e when e != [] <- find_events(t.events, selector) do
      {:ok, %{group: false, topic: topic, events: e}}
    else
      _ -> {:error, :invalid_subscription}
    end
  end

  defp find_events(events, selector)
  defp find_events(events, []), do: events

  defp find_events(events, selector) do
    matcher =
      selector
      |> clean_selector()
      |> merge_matcher()
      |> Regex.compile!()

    Enum.filter(events, &(&1.__event__(:type) =~ matcher))
  end

  defp clean_selector(selector, acc \\ [])
  defp clean_selector([], acc), do: :lists.reverse(acc)
  defp clean_selector(["*", "*" | rest], acc), do: clean_selector(["*" | rest], acc)
  defp clean_selector(["*", "+" | rest], acc), do: clean_selector(["*" | rest], acc)
  defp clean_selector([h | rest], acc), do: clean_selector(rest, [h | acc])

  defp merge_matcher(selector, acc \\ "^")
  defp merge_matcher([], acc), do: acc <> "$"
  defp merge_matcher(["*"], acc), do: acc
  defp merge_matcher(["*" | rest], acc), do: merge_matcher(rest, join_matcher(acc, "[a-z\_\.]*"))
  defp merge_matcher(["+" | rest], acc), do: merge_matcher(rest, join_matcher(acc, "[a-z\_]+"))
  defp merge_matcher([a | rest], acc), do: merge_matcher(rest, join_matcher(acc, a))

  defp join_matcher(a, b)
  defp join_matcher("^", b), do: "^" <> b
  defp join_matcher(a, b), do: a <> "." <> b

  ### Actual Logic => MOVE IT ###
  @type control_type ::
          :connect
          | :connack
          | :publish
          | :puback
          | :pubrec
          | :pubrel
          | :pubcomp
          | :subscribe
          | :suback
          | :unsubscribe
          | :unsuback
          | :pingreq
          | :pingresp
          | :disconnect

  @type packet ::
          {:mqtt, type :: control_type} | {:mqtt, type :: control_type, payload :: Keyword.t()}

  @spec read(atom, port, timeout :: pos_integer) :: {:ok, MQTT.packet()} | {:error, atom}
  def read(transport, socket, timeout \\ 15_000) do
    with {:ok, <<header::binary-1, l::binary>>} <- transport.recv(socket, 2, timeout),
         length = decode_length(transport, socket, l),
         {:ok, payload} <-
           if(length == 0, do: {:ok, <<>>}, else: transport.recv(socket, length, 5_000)) do
      V5.decode(header, payload)
    end
  end

  def write(transport, socket, package) do
    {:ok, data} = V5.encode(package)
    transport.send(socket, data)
  end

  def pong(transport, socket) do
    transport.send(socket, <<13::4, 0::4, 0>>)
  end

  def publish(transport, socket, data) do
    dup = 0
    qos = 0
    retain = 0
    topic = "TEST/TIME"
    topic_length = byte_size(topic)
    payload = <<topic_length::unsigned-integer-16, topic::binary, 0, data::binary>>
    length = encode_length(byte_size(payload))

    transport.send(
      socket,
      <<3::4, dup::1, qos::2, retain::1, length::binary, payload::binary>>
    )
  end

  defp decode_length(transport, socket, length, position \\ 0, acc \\ 0)
  defp decode_length(_, _, <<0::1, l::7>>, position, acc), do: acc + :erlang.bsl(l, position)

  defp decode_length(transport, socket, <<1::1, l::7>>, position, acc) do
    {:ok, n} = transport.receive(socket, 1, 5_000)

    decode_length(transport, socket, n, position + 7, acc + :erlang.bsl(l, position))
  end

  defp encode_length(length) when length < 128, do: <<length>>

  defp encode_length(length) do
    <<1::1, :erlang.band(length, 127)::7, encode_length(:erlang.bsr(length, 7))::binary>>
  end
end
