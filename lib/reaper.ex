# SPDX-License-Identifier: Apache-2.0
defmodule TestcontainersElixir.Reaper do
  use GenServer

  alias DockerEngineAPI.Api
  alias DockerEngineAPI.Model

  @ryuk_image "testcontainers/ryuk:0.5.1"
  @ryuk_port 8080

  def start_link(connection) do
    GenServer.start_link(__MODULE__, connection, name: __MODULE__)
  end

  def register(filter) do
    GenServer.call(__MODULE__, {:register, filter})
  end

  @impl true
  def init(connection) do
    with {:ok, _} <- Api.Image.image_create(connection, fromImage: @ryuk_image),
         {:ok, container} <- create_ryuk_container(connection),
         container_id = container."Id",
         {:ok, _} <- Api.Container.container_start(connection, container_id),
         {:ok, socket} <- create_ryuk_socket(connection, container_id) do
      {:ok, socket}
    end
  end

  @impl true
  def handle_call({:register, filter}, _from, socket) do
    {:reply, register_filter(socket, filter), socket}
  end

  defp register_filter(socket, {filter_key, filter_value}) do
    :gen_tcp.send(
      socket,
      "#{:uri_string.quote(filter_key)}=#{:uri_string.quote(filter_value)}" <> "\n"
    )

    {:ok, "ACK\n"} = :gen_tcp.recv(socket, 0, 1_000)

    :ok
  end

  defp create_ryuk_container(connection) do
    Api.Container.container_create(connection, %Model.ContainerCreateRequest{
      Image: @ryuk_image,
      ExposedPorts: %{"#{@ryuk_port}" => %{}},
      HostConfig: %{
        PortBindings: %{"#{@ryuk_port}" => [%{"HostPort" => ""}]},
        Privileged: true,
        # FIXME this will surely not work for all use cases
        Binds: ["/var/run/docker.sock:/var/run/docker.sock:rw"]
      },
      Env: ["RYUK_PORT=#{@ryuk_port}"]
    })
  end

  defp create_ryuk_socket(
         connection,
         container_id
       )
       when is_binary(container_id) do
    port_str = "#{@ryuk_port}/tcp"

    {:ok,
     %Model.ContainerInspectResponse{
       NetworkSettings: %{Ports: %{^port_str => [%{"HostPort" => host_port} | _tail]}}
     }} = connection |> Api.Container.container_inspect(container_id)

    :gen_tcp.connect(~c"localhost", String.to_integer(host_port), [
      :binary,
      active: false,
      packet: :line
    ])
  end
end