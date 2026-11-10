defmodule Emergencias.AlberguesTest do
  use ExUnit.Case, async: false

  alias Emergencias.{Albergues, Cupos, Necesidades, Recursos}

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
    start_supervised!(Albergues)
    :ok
  end

  test "registra y consulta un albergue" do
    assert {:ok, _} = Albergues.registrar("A01", "Albergue Norte", "zona_norte", 150)

    assert {:ok, albergue} = Albergues.consultar("a01")
    assert %{capacidad: 150, ocupacion: 0, cupos: 150} = Cupos.resumen(albergue)

    assert {:error, :no_existe} = Albergues.consultar("A99")
    assert {:error, :codigo_duplicado} = Albergues.registrar("A01", "Otro", "zona_sur", 10)
    assert {:error, :capacidad_invalida} = Albergues.registrar("A02", "Otro", "zona_sur", -5)
  end

  test "ingreso y salida actualizan la ocupación y los cupos" do
    {:ok, _} = Albergues.registrar("A01", "Albergue Norte", "zona_norte", 2)

    assert {:ok, %{ocupacion: 1}} = Albergues.ingresar("A01", "1001")
    assert {:ok, "A01"} = Albergues.donde_esta("1001")
    assert {:error, :persona_ya_registrada} = Albergues.ingresar("A01", "1001")

    assert {:ok, %{ocupacion: 0}} = Albergues.salir("A01", "1001")
    assert {:error, :no_alojada} = Albergues.donde_esta("1001")
    assert {:error, :persona_no_registrada} = Albergues.salir("A01", "1001")
  end

  test "CONCURRENCIA: 200 ingresos simultáneos sobre capacidad 150, nunca se supera" do
    {:ok, _} = Albergues.registrar("A01", "Albergue Norte", "zona_norte", 150)

    resultados =
      1..200
      |> Task.async_stream(fn i -> Albergues.ingresar("A01", "D#{i}") end, max_concurrency: 200)
      |> Enum.map(fn {:ok, resultado} -> resultado end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 150
    assert Enum.count(resultados, &(&1 == {:error, :albergue_lleno})) == 50
    assert {:ok, %{ocupacion: 150}} = Albergues.consultar("A01")
  end

  test "reporte de mayor ocupación" do
    {:ok, _} = Albergues.registrar("A01", "Norte", "zona_norte", 10, 5)
    {:ok, _} = Albergues.registrar("A02", "Sur", "zona_sur", 4, 4)
    {:ok, _} = Albergues.registrar("A03", "Centro", "zona_norte", 100, 10)

    assert {:ok, [%{codigo: "A02"}, %{codigo: "A01"}]} = Albergues.reporte_ocupacion(2)
    assert {:ok, [%{codigo: "A01"}, %{codigo: "A03"}]} = Albergues.listar(zona: "zona_norte")
  end

  test "asocia recursos y necesidades solo si existen" do
    {:ok, _} = Albergues.registrar("A01", "Albergue Norte", "zona_norte", 150)
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "A01")
    {:ok, _} = Necesidades.registrar("agua", 30, "critica", "zona_norte")

    assert {:ok, %{recursos: ["R001"]}} = Albergues.asociar_recurso("A01", "R001")
    assert {:ok, %{necesidades: ["N001"]}} = Albergues.asociar_necesidad("A01", "n001")

    assert {:error, :ya_asociado} = Albergues.asociar_recurso("A01", "R001")
    assert {:error, :recurso_no_existe} = Albergues.asociar_recurso("A01", "R999")
    assert {:error, :necesidad_no_existe} = Albergues.asociar_necesidad("A01", "N999")
    assert {:error, :no_existe} = Albergues.asociar_recurso("A99", "R001")
  end

  test "los albergues, las personas y las asociaciones sobreviven a un reinicio" do
    {:ok, _} = Recursos.registrar("R001", "agua", "bebida", 50, "litros", "A01")
    {:ok, _} = Albergues.registrar("A01", "Albergue Norte", "zona_norte", 150, 20)
    {:ok, _} = Albergues.ingresar("A01", "1001")
    {:ok, _} = Albergues.asociar_recurso("A01", "R001")

    :ok = stop_supervised(Albergues)
    start_supervised!(Albergues)

    assert {:ok, albergue} = Albergues.consultar("A01")
    assert albergue.ocupacion == 21
    assert albergue.recursos == ["R001"]
    assert {:ok, "A01"} = Albergues.donde_esta("1001")
    assert {:error, :persona_ya_registrada} = Albergues.ingresar("A01", "1001")
  end
end
