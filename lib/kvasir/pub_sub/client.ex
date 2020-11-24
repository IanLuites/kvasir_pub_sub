defprotocol Kvasir.PubSub.Client do
  @spec id(t) :: String.t()
  def id(value)
end
