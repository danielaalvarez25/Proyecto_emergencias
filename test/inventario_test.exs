defmodule Emergencias.InventarioTest do
  use ExUnit.Case, async: true

  alias Emergencias.Inventario

  defp con_agua do
    {:ok, _recurso, mapa, _movs} =
      Inventario.registrar(%{}, "R001", "agua", "bebida", 50, "litros", "centro_acopio_1")

    mapa
  end

  defp con_dos_centros do
    {:ok, _r, mapa, _m} =
      Inventario.registrar(%{}, "R001", "agua", "bebida", 20, "litros", "centro_1")

    {:ok, _r, mapa, _m} =
      Inventario.registrar(mapa, "R002", "agua", "bebida", 30, "litros", "centro_2")

    mapa
  end

  describe "registrar/7" do
    test "crea el recurso con su historial inicial" do
      {:ok, recurso, mapa, movs} =
        Inventario.registrar(%{}, "R001", "agua", "bebida", 50, "litros", "centro_acopio_1")

      assert recurso.cantidad == 50
      assert recurso.historial == [{:entrada, 50, "registro inicial"}]
      assert movs == [{"R001", :entrada, 50, "registro inicial"}]
      assert Map.has_key?(mapa, "R001")
    end

    test "rechaza códigos repetidos" do
      assert {:error, :codigo_duplicado} =
               Inventario.registrar(con_agua(), "R001", "arroz", "comida", 5, "kg", "centro")
    end

    test "rechaza cantidades negativas o no enteras" do
      assert {:error, :cantidad_invalida} =
               Inventario.registrar(%{}, "R001", "agua", "bebida", -1, "litros", "centro")

      assert {:error, :cantidad_invalida} =
               Inventario.registrar(%{}, "R001", "agua", "bebida", "10", "litros", "centro")
    end

    test "rechaza datos vacíos" do
      assert {:error, :datos_invalidos} =
               Inventario.registrar(%{}, "", "agua", "bebida", 5, "litros", "centro")
    end
  end

  describe "entrada/4 y salida/4" do
    test "la entrada suma y la salida resta" do
      {:ok, r, mapa, _} = Inventario.entrada(con_agua(), "R001", 10, "donación")
      assert r.cantidad == 60

      {:ok, r, _mapa, movs} = Inventario.salida(mapa, "R001", 15, "reparto")
      assert r.cantidad == 45
      assert movs == [{"R001", :salida, 15, "reparto"}]
    end

    test "no permite dejar el inventario negativo" do
      assert {:error, :stock_insuficiente} = Inventario.salida(con_agua(), "R001", 51)
    end

    test "valida cantidad y existencia" do
      assert {:error, :cantidad_invalida} = Inventario.entrada(con_agua(), "R001", 0)
      assert {:error, :cantidad_invalida} = Inventario.salida(con_agua(), "R001", -5)
      assert {:error, :no_existe} = Inventario.entrada(con_agua(), "R999", 5)
    end
  end

  describe "tomar/4 y repartir/3" do
    test "reparte entre centros en orden de código" do
      {:ok, partes, mapa, movs} = Inventario.tomar(con_dos_centros(), "Agua", 35, "N001")

      assert partes == [{"R001", 20}, {"R002", 15}]
      assert mapa["R001"].cantidad == 0
      assert mapa["R002"].cantidad == 15
      assert movs == [{"R001", :salida, 20, "N001"}, {"R002", :salida, 15, "N001"}]
    end

    test "es todo o nada cuando no alcanza" do
      mapa = con_dos_centros()
      assert {:error, :stock_insuficiente} = Inventario.tomar(mapa, "agua", 51, "N001")
      assert Inventario.disponible(mapa, "agua") == 50
    end

    test "rechaza cantidades inválidas" do
      assert {:error, :cantidad_invalida} = Inventario.tomar(con_agua(), "agua", 0, "N001")
    end

    test "repartir/3 cubre la cantidad recorriendo la lista" do
      mapa = con_dos_centros()
      recursos = Inventario.listar(mapa)

      assert {:ok, [{"R001", 20}, {"R002", 5}]} = Inventario.repartir(recursos, 25, [])
      assert {:ok, []} = Inventario.repartir(recursos, 0, [])
      assert {:error, :stock_insuficiente} = Inventario.repartir(recursos, 51, [])
    end
  end

  describe "consultas" do
    test "disponible/2 suma todos los centros e ignora mayúsculas" do
      assert Inventario.disponible(con_dos_centros(), "AGUA") == 50
      assert Inventario.disponible(con_dos_centros(), "arroz") == 0
    end

    test "listar/2 filtra por ubicación" do
      assert [%{codigo: "R002"}] = Inventario.listar(con_dos_centros(), ubicacion: "centro_2")
    end

    test "criticos/2 devuelve los más escasos primero" do
      assert [%{codigo: "R001"}] = Inventario.criticos(con_dos_centros(), 25)
      assert [%{codigo: "R001"}, %{codigo: "R002"}] = Inventario.criticos(con_dos_centros(), 30)
    end
  end

  describe "transferir/5" do
    test "crea el recurso en el destino y descuenta el origen" do
      {:ok, valor, mapa, movs} =
        Inventario.transferir(con_agua(), "R001", "centro_acopio_1", "albergue_2", 30)

      assert valor.origen.cantidad == 20
      assert valor.destino.codigo == "R001@albergue_2"
      assert valor.destino.cantidad == 30
      assert Map.has_key?(mapa, "R001@albergue_2")
      assert length(movs) == 2
    end

    test "suma al recurso del destino si ya existe" do
      {:ok, _valor, mapa, _} =
        Inventario.transferir(con_agua(), "R001", "centro_acopio_1", "albergue_2", 30)

      {:ok, valor, _mapa, _} =
        Inventario.transferir(mapa, "R001", "centro_acopio_1", "albergue_2", 10)

      assert valor.destino.codigo == "R001@albergue_2"
      assert valor.destino.cantidad == 40
      assert valor.origen.cantidad == 10
    end

    test "valida stock, origen y destino" do
      mapa = con_agua()

      assert {:error, :stock_insuficiente} =
               Inventario.transferir(mapa, "R001", "centro_acopio_1", "albergue_2", 51)

      assert {:error, :origen_incorrecto} =
               Inventario.transferir(mapa, "R001", "otro_centro", "albergue_2", 5)

      assert {:error, :destino_invalido} =
               Inventario.transferir(mapa, "R001", "centro_acopio_1", "centro_acopio_1", 5)

      assert {:error, :no_existe} =
               Inventario.transferir(mapa, "R999", "centro_acopio_1", "albergue_2", 5)
    end
  end

  describe "filas de persistencia" do
    test "a_fila/1 y desde_fila/1 son inversas (sin historial)" do
      recurso = con_agua()["R001"]

      fila = recurso |> Inventario.a_fila() |> Enum.map(&to_string/1)
      assert {:ok, leido} = Inventario.desde_fila(fila)
      assert %{leido | historial: []} == %{recurso | historial: []}
    end

    test "una fila dañada devuelve :error" do
      assert :error = Inventario.desde_fila(["R001", "agua"])
      assert :error = Inventario.desde_fila(["R001", "agua", "bebida", "x", "litros", "centro"])
      assert :error = Inventario.desde_fila_movimiento(["R001", "rara", "5", "detalle"])
    end
  end
end
