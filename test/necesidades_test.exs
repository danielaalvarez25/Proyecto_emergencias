defmodule Emergencias.NecesidadesTest do
  use ExUnit.Case, async: false

  alias Emergencias.{Necesidades, Recursos}

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
    :ok
  end

  defp agua(cantidad) do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", cantidad, "litros", "centro_acopio_1")
  end

  test "registra y consulta una necesidad" do
    assert {:ok, necesidad} =
             Necesidades.registrar("agua", 30, "critica", "centro", "Punto de atención sector 3", "laura")

    assert necesidad.id == "N001"
    assert {:ok, %{cantidad: 30, estado: :pendiente}} = Necesidades.consultar("N001")
    assert {:error, :no_existe} = Necesidades.consultar("N999")
    assert {:error, :tipo_invalido} = Necesidades.registrar("oro", 30, "critica", "centro")
  end

  test "asignar descuenta el inventario y marca la necesidad como asignada" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")

    assert {:ok, %{estado: :asignada, asignaciones: [{"R001", 30}]}} =
             Necesidades.asignar("N001", "agua", 30)

    assert {:ok, %{cantidad: 20}} = Recursos.consultar("R001")
  end

  test "FLUJO DEL ENUNCIADO: 30 L y 25 L sobre 50 L, la segunda se rechaza" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")
    {:ok, _} = Necesidades.registrar("agua", 25, "alta", "centro")

    assert {:ok, %{estado: :asignada}} = Necesidades.asignar("N001", "agua", 30)
    assert {:error, :stock_insuficiente} = Necesidades.asignar("N002", "agua", 25)

    assert {:ok, %{estado: :pendiente, asignaciones: []}} = Necesidades.consultar("N002")
    assert {:ok, %{cantidad: 20}} = Recursos.consultar("R001")
  end

  test "CONFLICTO: dos asignaciones simultáneas, solo una se confirma" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")
    {:ok, _} = Necesidades.registrar("agua", 25, "alta", "centro")

    resultados =
      [
        Task.async(fn -> Necesidades.asignar("N001", "agua", 30) end),
        Task.async(fn -> Necesidades.asignar("N002", "agua", 25) end)
      ]
      |> Task.await_many()

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :stock_insuficiente} in resultados

    {:ok, recurso} = Recursos.consultar("R001")
    assert recurso.cantidad in [20, 25]

    {:ok, asignadas} = Necesidades.listar(estado: :asignada)
    assert length(asignadas) == 1
  end

  test "no asigna de más ni dos veces la misma necesidad, y no toca el inventario" do
    agua(100)
    {:ok, _} = Necesidades.registrar("agua", 30, "alta", "centro")

    assert {:error, :excede_necesidad} = Necesidades.asignar("N001", "agua", 40)
    assert {:ok, %{cantidad: 100}} = Recursos.consultar("R001")

    assert {:ok, %{estado: :asignada}} = Necesidades.asignar("N001", "agua", 30)
    assert {:error, :ya_asignada} = Necesidades.asignar("N001", "agua", 1)
    assert {:ok, %{cantidad: 70}} = Recursos.consultar("R001")
  end

  test "una necesidad atendida o cancelada no vuelve a consumir recursos" do
    agua(100)
    {:ok, _} = Necesidades.registrar("agua", 30, "alta", "centro")
    {:ok, _} = Necesidades.registrar("agua", 10, "alta", "centro")

    {:ok, _} = Necesidades.asignar("N001", "agua", 30)
    {:ok, _} = Necesidades.cambiar_estado("N001", "atendida")
    {:ok, _} = Necesidades.cambiar_estado("N002", "cancelada")

    assert {:error, :necesidad_cerrada} = Necesidades.asignar("N001", "agua", 1)
    assert {:error, :necesidad_cerrada} = Necesidades.asignar("N002", "agua", 1)
    assert {:error, :necesidad_cerrada} = Necesidades.cambiar_estado("N001", "atendida")
    assert {:ok, %{cantidad: 70}} = Recursos.consultar("R001")
  end

  test "valida las transiciones de estado" do
    {:ok, _} = Necesidades.registrar("agua", 30, "alta", "centro")

    assert {:error, :transicion_invalida} = Necesidades.cambiar_estado("N001", "atendida")
    assert {:ok, %{estado: :cancelada}} = Necesidades.cambiar_estado("N001", "cancelada")
  end

  test "asigna con un recurso repartido entre varios centros" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 20, "litros", "centro_1")
    {:ok, _} = Recursos.registrar("R002", "agua", "bebida", 30, "litros", "centro_2")
    {:ok, _} = Necesidades.registrar("agua", 35, "critica", "centro")

    assert {:ok, %{asignaciones: [{"R001", 20}, {"R002", 15}]}} =
             Necesidades.asignar("N001", "agua", 35)
  end

  test "atender_por_prioridad sirve primero a la más urgente" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "media", "centro")
    {:ok, _} = Necesidades.registrar("agua", 25, "critica", "centro")

    assert {:ok, [{"N002", "agua", 25}]} = Necesidades.atender_por_prioridad()

    assert {:ok, %{estado: :asignada}} = Necesidades.consultar("N002")
    assert {:ok, %{estado: :pendiente}} = Necesidades.consultar("N001")
    assert {:ok, %{cantidad: 25}} = Recursos.consultar("R001")
    assert {:ok, [%{id: "N001"}]} = Necesidades.pendientes()
  end

  test "listar filtra por zona, tipo, prioridad y estado" do
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro")
    {:ok, _} = Necesidades.registrar("alimentos", 10, "baja", "norte")

    assert {:ok, [%{id: "N001"}]} = Necesidades.listar(zona: "centro", prioridad: "critica")
    assert {:ok, [%{id: "N002"}]} = Necesidades.listar(tipo: "alimentos")
    assert {:ok, [%{id: "N001"}, %{id: "N002"}]} = Necesidades.listar()
  end

  test "las necesidades y sus asignaciones sobreviven a un reinicio" do
    agua(50)
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "centro", "Punto sector 3", "laura")
    {:ok, _} = Necesidades.asignar("N001", "agua", 30)

    :ok = stop_supervised(Necesidades)
    start_supervised!(Necesidades)

    assert {:ok, %{estado: :asignada, asignaciones: [{"R001", 30}], responsable: "laura"}} =
             Necesidades.consultar("N001")

    assert {:ok, %{id: "N002"}} = Necesidades.registrar("agua", 5, "baja", "centro")
  end
end
