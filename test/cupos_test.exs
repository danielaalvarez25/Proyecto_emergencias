defmodule Emergencias.CuposTest do
  use ExUnit.Case, async: true

  alias Emergencias.Cupos

  defp con_albergue(capacidad \\ 2) do
    {:ok, _a, mapa} = Cupos.registrar(%{}, "a01", "Albergue Norte", "zona_norte", capacidad)
    mapa
  end

  describe "registrar/6" do
    test "guarda el código en mayúsculas y deja la ocupación inicial" do
      {:ok, albergue, mapa} = Cupos.registrar(%{}, "a01", " Albergue Norte ", "zona_norte", 150, 20)

      assert albergue.codigo == "A01"
      assert albergue.nombre == "Albergue Norte"
      assert albergue.ocupacion == 20
      assert Cupos.cupos(albergue) == 130
      assert {:ok, _} = Cupos.obtener(mapa, "A01")
      assert {:ok, _} = Cupos.obtener(mapa, "a01")
    end

    test "rechaza códigos repetidos, ignorando mayúsculas" do
      assert {:error, :codigo_duplicado} =
               Cupos.registrar(con_albergue(), "A01", "Otro", "zona_sur", 10)
    end

    test "rechaza capacidades y ocupaciones inválidas" do
      assert {:error, :capacidad_invalida} = Cupos.registrar(%{}, "A01", "N", "z", -1)
      assert {:error, :capacidad_invalida} = Cupos.registrar(%{}, "A01", "N", "z", "150")
      assert {:error, :ocupacion_invalida} = Cupos.registrar(%{}, "A01", "N", "z", 10, -1)
      assert {:error, :ocupacion_invalida} = Cupos.registrar(%{}, "A01", "N", "z", 10, 11)
    end

    test "rechaza datos vacíos" do
      assert {:error, :datos_invalidos} = Cupos.registrar(%{}, "", "N", "z", 10)
      assert {:error, :datos_invalidos} = Cupos.registrar(%{}, "A01", "  ", "z", 10)
      assert {:error, :datos_invalidos} = Cupos.registrar(%{}, "A01", "N", "", 10)
    end
  end

  describe "ingresar/3 y salir/3" do
    test "el ingreso suma la ocupación y la salida la resta" do
      {:ok, albergue, mapa} = Cupos.ingresar(con_albergue(), "A01", "1001")
      assert albergue.ocupacion == 1
      assert Cupos.cupos(albergue) == 1

      {:ok, albergue, _mapa} = Cupos.salir(mapa, "A01", "1001")
      assert albergue.ocupacion == 0
      assert Cupos.cupos(albergue) == 2
    end

    test "no permite superar la capacidad máxima" do
      {:ok, _a, mapa} = Cupos.ingresar(con_albergue(), "A01", "1001")
      {:ok, _a, mapa} = Cupos.ingresar(mapa, "A01", "1002")

      assert {:error, :albergue_lleno} = Cupos.ingresar(mapa, "A01", "1003")
    end

    test "cuenta la ocupación inicial al validar la capacidad" do
      {:ok, _a, mapa} = Cupos.registrar(%{}, "A01", "Norte", "z", 5, 5)
      assert {:error, :albergue_lleno} = Cupos.ingresar(mapa, "A01", "1001")
    end

    test "una persona no puede ingresar dos veces ni estar en dos albergues" do
      {:ok, _a, mapa} = Cupos.registrar(con_albergue(), "A02", "Sur", "zona_sur", 5)
      {:ok, _a, mapa} = Cupos.ingresar(mapa, "A01", "1001")

      assert {:error, :persona_ya_registrada} = Cupos.ingresar(mapa, "A01", "1001")
      assert {:error, :persona_en_otro_albergue} = Cupos.ingresar(mapa, "A02", "1001")
    end

    test "tras salir, la persona puede ingresar a otro albergue" do
      {:ok, _a, mapa} = Cupos.registrar(con_albergue(), "A02", "Sur", "zona_sur", 5)
      {:ok, _a, mapa} = Cupos.ingresar(mapa, "A01", "1001")
      {:ok, _a, mapa} = Cupos.salir(mapa, "A01", "1001")

      assert {:ok, %{ocupacion: 1}, _mapa} = Cupos.ingresar(mapa, "A02", "1001")
    end

    test "valida albergue, documento y salida de quien no está" do
      mapa = con_albergue()

      assert {:error, :no_existe} = Cupos.ingresar(mapa, "A99", "1001")
      assert {:error, :documento_invalido} = Cupos.ingresar(mapa, "A01", "  ")
      assert {:error, :documento_invalido} = Cupos.ingresar(mapa, "A01", "10;01")
      assert {:error, :persona_no_registrada} = Cupos.salir(mapa, "A01", "1001")
    end

    test "donde_esta/2 encuentra el albergue de una persona" do
      {:ok, _a, mapa} = Cupos.registrar(con_albergue(), "A02", "Sur", "zona_sur", 5)
      {:ok, _a, mapa} = Cupos.ingresar(mapa, "A02", "1001")

      assert {:ok, "A02"} = Cupos.donde_esta(mapa, "1001")
      assert :ninguno = Cupos.donde_esta(mapa, "9999")
      assert :ninguno = Cupos.donde_esta(%{}, "1001")
    end
  end

  describe "consultas y reporte" do
    defp con_tres do
      {:ok, _a, mapa} = Cupos.registrar(%{}, "A01", "Norte", "zona_norte", 10, 5)
      {:ok, _a, mapa} = Cupos.registrar(mapa, "A02", "Sur", "zona_sur", 4, 4)
      {:ok, _a, mapa} = Cupos.registrar(mapa, "A03", "Centro", "zona_norte", 100, 10)
      mapa
    end

    test "porcentaje/1 y resumen/1" do
      {:ok, albergue} = Cupos.obtener(con_tres(), "A01")
      assert Cupos.porcentaje(albergue) == 50.0

      assert %{cupos: 5, porcentaje: 50.0, capacidad: 10, ocupacion: 5} = Cupos.resumen(albergue)

      {:ok, _a, mapa} = Cupos.registrar(%{}, "A09", "Sin cupo", "z", 0)
      {:ok, sin_capacidad} = Cupos.obtener(mapa, "A09")
      assert Cupos.porcentaje(sin_capacidad) == 0.0
    end

    test "mayor_ocupacion/2 ordena por porcentaje y respeta el límite" do
      assert ["A02", "A01", "A03"] = con_tres() |> Cupos.mayor_ocupacion() |> Enum.map(& &1.codigo)
      assert ["A02", "A01"] = con_tres() |> Cupos.mayor_ocupacion(2) |> Enum.map(& &1.codigo)
    end

    test "listar/2 filtra por zona" do
      codigos = fn filtros -> con_tres() |> Cupos.listar(filtros) |> Enum.map(& &1.codigo) end

      assert codigos.([]) == ["A01", "A02", "A03"]
      assert codigos.(zona: "Zona_Norte") == ["A01", "A03"]
      assert codigos.(zona: "otra") == []
    end
  end

  describe "asociaciones" do
    test "asocia recursos y necesidades sin repetirlos" do
      {:ok, a, mapa} = Cupos.asociar_recurso(con_albergue(), "A01", "R001")
      assert a.recursos == ["R001"]
      assert {:error, :ya_asociado} = Cupos.asociar_recurso(mapa, "A01", "R001")

      {:ok, a, mapa} = Cupos.asociar_necesidad(mapa, "A01", "N001")
      assert a.necesidades == ["N001"]
      assert {:error, :ya_asociado} = Cupos.asociar_necesidad(mapa, "A01", "N001")
    end

    test "valida albergue y dato" do
      assert {:error, :no_existe} = Cupos.asociar_recurso(con_albergue(), "A99", "R001")
      assert {:error, :datos_invalidos} = Cupos.asociar_recurso(con_albergue(), "A01", "")
    end
  end

  describe "filas de persistencia" do
    test "a_fila/1 y desde_fila/1 son inversas" do
      {:ok, _a, mapa} = Cupos.registrar(%{}, "A01", "Albergue Norte", "zona_norte", 150, 20)
      {:ok, _a, mapa} = Cupos.ingresar(mapa, "A01", "1001")
      {:ok, _a, mapa} = Cupos.ingresar(mapa, "A01", "1002")
      {:ok, _a, mapa} = Cupos.asociar_recurso(mapa, "A01", "R001")
      {:ok, _a, mapa} = Cupos.asociar_necesidad(mapa, "A01", "N001")
      {:ok, albergue} = Cupos.obtener(mapa, "A01")

      fila = albergue |> Cupos.a_fila() |> Enum.map(&to_string/1)
      assert {:ok, leido} = Cupos.desde_fila(fila)
      assert leido == albergue
    end

    test "una fila dañada devuelve :error" do
      assert :error = Cupos.desde_fila(["A01", "Norte"])
      assert :error = Cupos.desde_fila(["A01", "Norte", "z", "x", "0", "", "", ""])
      assert :error = Cupos.desde_fila(["A01", "Norte", "z", "10", "11", "", "", ""])
      assert :error = Cupos.desde_fila(["A01", "Norte", "z", "10", "1", "1001;1002", "", ""])
    end
  end
end
