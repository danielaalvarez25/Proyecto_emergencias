defmodule Emergencias.DespachoTest do
  use ExUnit.Case, async: false

  alias Emergencias.{Despacho, Necesidades, Recursos}

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    anterior = Application.get_env(:emergencias, :data_dir)
    Application.put_env(:emergencias, :data_dir, dir)

    on_exit(fn ->
      if anterior do
        Application.put_env(:emergencias, :data_dir, anterior)
      else
        Application.delete_env(:emergencias, :data_dir)
      end
    end)

    start_supervised!(Recursos)
    start_supervised!(Necesidades)
    start_supervised!(Despacho)
    :ok
  end

  defp agua(cantidad) do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", cantidad, "litros", "centro_acopio_1")
  end

  defp cuantos_ok(resultados), do: Enum.count(resultados, fn {_id, r} -> match?({:ok, _}, r) end)

  test "asignar/3 ejecuta la asignación en un proceso supervisado y devuelve el resultado" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")

    assert {:ok, %{estado: :asignada}} = Despacho.asignar("N001", "agua", 30)
    assert {:ok, %{cantidad: 20}} = Recursos.consultar("R001")
  end

  test "asignar_async/3 + esperar/2 devuelve los errores de dominio" do
    agua(10)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")

    {:ok, manejador} = Despacho.asignar_async("N001", "agua", 30)
    assert {:error, :stock_insuficiente} = Despacho.esperar(manejador)
    assert {:error, :no_existe} = Despacho.asignar("N999", "agua", 5)
  end

  test "DEMO DEL CONFLICTO: 30 L y 25 L sobre 50 L, solo una se confirma" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")
    {:ok, _} = Necesidades.registrar("agua", 25, "alta", "centro")

    resultados = Despacho.asignar_varias([{"N001", "agua", 30}, {"N002", "agua", 25}])

    assert [{"N001", _}, {"N002", _}] = resultados
    assert cuantos_ok(resultados) == 1
    assert Enum.any?(resultados, fn {_id, r} -> r == {:error, :stock_insuficiente} end)

    {:ok, recurso} = Recursos.consultar("R001")
    assert recurso.cantidad in [20, 25]
  end

  test "20 asignaciones simultáneas de 10 L sobre 50 L: se confirman exactamente 5" do
    agua(50)

    pedidos =
      for _ <- 1..20 do
        {:ok, n} = Necesidades.registrar("agua", 10, "media", "centro")
        {n.id, "agua", 10}
      end

    resultados = Despacho.asignar_varias(pedidos)

    assert length(resultados) == 20
    assert cuantos_ok(resultados) == 5
    assert {:ok, %{cantidad: 0}} = Recursos.consultar("R001")

    {:ok, asignadas} = Necesidades.listar(estado: :asignada)
    assert length(asignadas) == 5
  end

  test "un proceso que muere no se reinicia ni afecta al supervisor ni a los demás" do
    {:ok, pid} = DynamicSupervisor.start_child(Despacho, {Task, fn -> Process.sleep(:infinity) end})
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}

    assert Process.alive?(Process.whereis(Despacho))

    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")
    assert {:ok, %{estado: :asignada}} = Despacho.asignar("N001", "agua", 30)
  end

  test "esperar/2 avisa si el proceso cae antes de responder" do
    {:ok, pid} = DynamicSupervisor.start_child(Despacho, {Task, fn -> Process.sleep(:infinity) end})
    manejador = %{ref: make_ref(), monitor: Process.monitor(pid), pid: pid}

    Process.exit(pid, :kill)
    assert {:error, {:proceso_caido, :killed}} = Despacho.esperar(manejador, 1_000)
  end
end
