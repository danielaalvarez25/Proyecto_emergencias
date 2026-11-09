defmodule Emergencias.RecursosTest do
  use ExUnit.Case, async: false

  alias Emergencias.Recursos

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
    :ok
  end

  test "registra y consulta un recurso" do
    assert {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro_acopio_1")
    assert {:ok, recurso} = Recursos.consultar("R001")
    assert recurso.cantidad == 50
    assert {:error, :no_existe} = Recursos.consultar("R999")
  end

  test "rechaza códigos repetidos y cantidades negativas" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro")

    assert {:error, :codigo_duplicado} =
             Recursos.registrar("R001", "arroz", "comida", 5, "kg", "centro")

    assert {:error, :cantidad_invalida} =
             Recursos.registrar("R002", "arroz", "comida", -5, "kg", "centro")

    assert {:error, :stock_insuficiente} = Recursos.salida("R001", 51)
    assert {:ok, %{cantidad: 50}} = Recursos.consultar("R001")
  end

  test "CONFLICTO: 30 L y 25 L sobre 50 L, solo una asignación se confirma" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro_acopio_1")

    resultados =
      [
        Task.async(fn -> Recursos.tomar("agua", 30, "N001") end),
        Task.async(fn -> Recursos.tomar("agua", 25, "N002") end)
      ]
      |> Task.await_many()

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert {:error, :stock_insuficiente} in resultados

    {:ok, recurso} = Recursos.consultar("R001")
    assert recurso.cantidad in [20, 25]
    assert recurso.cantidad >= 0
  end

  test "100 solicitudes simultáneas de 1 unidad sobre 50: exactamente 50 se confirman" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro_acopio_1")

    resultados =
      1..100
      |> Task.async_stream(fn i -> Recursos.tomar("agua", 1, "N#{i}") end,
        max_concurrency: 100
      )
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 50
    assert Enum.count(resultados, &(&1 == {:error, :stock_insuficiente})) == 50
    assert {:ok, %{cantidad: 0}} = Recursos.consultar("R001")
  end

  test "transfiere entre centros y lista por ubicación" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro_acopio_1")

    assert {:ok, %{origen: origen, destino: destino}} =
             Recursos.transferir("R001", "centro_acopio_1", "albergue_2", 30)

    assert origen.cantidad == 20
    assert destino.cantidad == 30
    assert {:ok, 50} = Recursos.disponible("agua")
    assert {:ok, [%{codigo: "R001@albergue_2"}]} = Recursos.listar(ubicacion: "albergue_2")
  end

  test "critical_resources: lista los recursos por debajo del umbral" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 5, "litros", "centro")
    {:ok, _} = Recursos.registrar("R002", "arroz", "comida", 500, "kg", "centro")

    assert {:ok, [%{codigo: "R001"}]} = Recursos.criticos(20)
  end

  test "el inventario y el historial sobreviven a un reinicio" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "centro_acopio_1")
    {:ok, _} = Recursos.entrada("R001", 10, "donación")
    {:ok, _} = Recursos.tomar("agua", 20, "N001")

    :ok = stop_supervised(Recursos)
    start_supervised!(Recursos)

    assert {:ok, %{cantidad: 40}} = Recursos.consultar("R001")

    assert {:ok,
            [
              {:entrada, 50, "registro inicial"},
              {:entrada, 10, "donación"},
              {:salida, 20, "N001"}
            ]} = Recursos.historial("R001")
  end
end
