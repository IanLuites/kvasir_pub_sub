defmodule Kvasir.PubSub.Protocols.MQTT.V5 do
  alias Kvasir.PubSub.Protocols.MQTT

  @spec decode(header :: binary, payload :: binary) :: {:ok, MQTT.packet()} | {:error, atom}
  def decode(header, payload)

  # 1: CONNECT [Client -> Server] Connection request
  # Flags: Reserved 0000
  def decode(<<1::4, 0::1, 0::1, 0::1, 0::1>>, payload) do
    case payload do
      <<
        # Protocol Name (1-6)
        0,
        4,
        ?M,
        ?Q,
        ?T,
        ?T,
        # Protocol Version (7)
        version::unsigned-integer-8,
        # Connect Flags (8)
        username::1,
        password::1,
        will_retain::1,
        will_qos::2,
        will_flag::1,
        clean_start::1,
        0::1,
        # Keep Alive (9-10)
        keep_alive::unsigned-integer-16,
        rest::binary
      >> ->
        flags = []
        flags = if username == 1, do: [:username | flags], else: flags
        flags = if password == 1, do: [:password | flags], else: flags
        flags = if will_retain == 1, do: [:will_retain | flags], else: flags
        flags = if will_flag == 1, do: [:will_flag | flags], else: flags
        flags = if clean_start == 1, do: [:clean_start | flags], else: flags

        {_props, <<0, rest::binary>>} = read_variable(rest)

        {client_id, rest} =
          case read_string(rest) do
            {"", r} -> {:requested, r}
            {v, r} -> {v, r}
          end

        opts = [client_id: client_id, keep_alive: keep_alive, will_qos: will_qos]

        # Username
        {opts, rest} =
          if :username in flags do
            {username, rest} = read_string(rest)
            {Keyword.put(opts, :username, username), rest}
          else
            {opts, rest}
          end

        # Password
        {opts, _rest} =
          if :password in flags do
            {password, rest} = read_string(rest)
            {Keyword.put(opts, :password, password), rest}
          else
            {opts, rest}
          end

        connect = {version, flags, opts}
        {:ok, {:mqtt, :connect, connect}}

      _ ->
        {:error, :malformed_packet}
    end
  end

  # 3: PUBLISH [Client -> Server] Publish message
  # Flags: Reserved 0010
  def decode(<<3::4, _dup::1, qos::2, _retain::1>>, payload) do
    case payload do
      <<length::unsigned-integer-16, data::binary>> when qos == 0 ->
        {topic, <<0, p::binary>>} = :erlang.split_binary(data, length)
        {:ok, {:mqtt, :publish, {topic, p}}}

      <<length::unsigned-integer-16, data::binary>> ->
        {topic, <<_identifier::unsigned-integer-16, 0, p::binary>>} =
          :erlang.split_binary(data, length)

        {:ok, {:mqtt, :publish, {topic, p}}}

      _ ->
        {:error, :malformed_packet}
    end
  end

  # 8: SUBSCRIBE [Client -> Server] Subscribe request
  # Flags: Reserved 0010
  def decode(<<8::4, 0::1, 0::1, 1::1, 0::1>>, payload) do
    case payload do
      <<identifier::unsigned-integer-16, length::unsigned-integer-8, data::binary>> ->
        {_properties, topics} = :erlang.split_binary(data, length)

        {:ok, {:mqtt, :subscribe, id: identifier, subscriptions: decode_topic_filter(topics)}}

      _ ->
        {:error, :malformed_packet}
    end
  end

  # 3: PINGREQ [Client -> Server] PING request
  # Flags: Reserved 0000
  def decode(<<12::4, 0::4>>, <<>>), do: {:ok, {:mqtt, :pingreq}}

  ### Server Messages, Not Needed ###

  # 2: CONNACK [Server -> Client] Connect acknowledgment
  # Flags: Reserved 0000
  def decode(<<2::4, 0::4>>, _payload), do: {:error, :server_message}

  defp decode_topic_filter(data, topics \\ [])

  defp decode_topic_filter(<<length::unsigned-integer-16, data::binary>>, topics) do
    {topic, <<0::2, retain::2, rap::1, nl::1, qos::2, rest::binary>>} =
      :erlang.split_binary(data, length)

    settings = %{
      retain: retain,
      retain_as_published: rap == 1,
      no_local: nl == 1,
      qos: qos
    }

    decode_topic_filter(rest, [{topic, settings} | topics])
  end

  defp decode_topic_filter(_, topics), do: topics

  ### Helpers ###

  defp read_string(<<length, rest::binary>>) do
    case :erlang.split_binary(rest, length) do
      {str, <<0, left::binary>>} -> {str, left}
      left -> left
    end
  end

  defp read_variable(binary, position \\ 0, acc \\ 0)

  defp read_variable(<<0::1, l::7, rest::binary>>, position, acc),
    do: :erlang.split_binary(rest, acc + :erlang.bsl(l, position))

  defp read_variable(<<1::1, l::7, rest::binary>>, position, acc),
    do: read_variable(rest, position + 7, acc + :erlang.bsl(l, position))

  defp encode_variable(data)

  defp encode_variable(data) when is_list(data),
    do: encode_variable(:erlang.iolist_to_binary(data))

  defp encode_variable(data) do
    [encode_variable_length(byte_size(data)), data]
  end

  @spec encode_variable_length(non_neg_integer(), [byte()]) :: [byte()]
  defp encode_variable_length(length, acc \\ [])

  defp encode_variable_length(length, acc) when length > 0 do
    byte = rem(length, 128)
    l = div(length, 128)

    if l > 0,
      do: encode_variable_length(l, [:erlang.bor(byte, 128) | acc]),
      else: encode_variable_length(0, [byte | acc])
  end

  defp encode_variable_length(_, acc), do: :lists.reverse(acc)

  @spec encode(package :: MQTT.packet()) :: {:ok, payload :: iodata()} | {:error, atom}
  def encode(package)

  def encode(p) do
    dencode(p)
  end

  def dencode({:mqtt, :connack, opts}) do
    client_id = opts[:client_id]
    properties = encode_variable([0x12, <<byte_size(client_id)::unsigned-integer-16>>, client_id])

    data = [
      # Connect Acknowledge Flags: No Session (0)
      <<0>>,
      # Connect Reason Code: Success (0x00)
      <<0>>,
      properties
    ]

    {:ok,
     [
       <<
         # Control packet Type 2
         0::1,
         0::1,
         1::1,
         0::1,
         0::1,
         0::1,
         0::1,
         0::1
       >>
       | encode_variable(data)
     ]}
  end

  def dencode({:mqtt, :publish, opts}) do
    id = opts[:id] || 1
    topic = opts[:topic] || ""
    dup = 0
    qos = opts[:qos] || 0
    retain = 0
    payload = opts[:payload] || <<>>

    properties = encode_variable([0x0B, encode_variable_length(id)])

    data = [
      <<byte_size(topic)::unsigned-integer-16>>,
      topic,
      properties,
      payload
    ]

    {:ok,
     [
       <<
         # Control packet Type 4
         0::1,
         0::1,
         1::1,
         1::1,
         dup::1,
         qos::2,
         retain::1
       >>
       | encode_variable(data)
     ]}
  end

  def dencode({:mqtt, :suback, payload}) do
    id = payload[:id]

    data =
      :erlang.iolist_to_binary([
        <<id::unsigned-integer-16, 0>>
        | Enum.map(payload[:subscriptions], fn
            :granted_qos_0 -> 0x00
            :granted_qos_1 -> 0x01
          end)
      ])

    {:ok,
     [
       <<
         # Control packet Type 9
         1::1,
         0::1,
         0::1,
         1::1,
         0::1,
         0::1,
         0::1,
         0::1
       >>
       | encode_variable(data)
     ]}
  end

  def dencode({:mqtt, :pingresp}) do
    {:ok,
     <<
       # Control packet Type 2
       1::1,
       1::1,
       0::1,
       1::1,
       0::1,
       0::1,
       0::1,
       0::1,
       # Length
       0
     >>}
  end

  def dencode(_), do: {:error, :invalid_mqtt_package}
end
