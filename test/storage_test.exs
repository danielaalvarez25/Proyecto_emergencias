defmodule Emergencias.StorageTest do
  use ExUnit.Case, async: false

  alias Emergencias.Storage

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

    :ok
  end

  test "un archivo que no existe se lee como lista vacía" do
    assert {:ok, []} = Storage.leer("no_existe.txt")
  end

  test "agregar y leer devuelve los mismos campos" do
    :ok = Storage.agregar("recursos.txt", ["R001", "agua", 200, "litros", "centro_acopio_1"])
    :ok = Storage.agregar("recursos.txt", ["R002", "arroz", 50, "kg", "albergue_2"])

    assert {:ok, filas} = Storage.leer("recursos.txt")

    assert filas == [
             ["R001", "agua", "200", "litros", "centro_acopio_1"],
             ["R002", "arroz", "50", "kg", "albergue_2"]
           ]
  end

  test "los campos con |, barra invertida y saltos de línea sobreviven" do
    campos = ["N001", "agua | potable", "ruta\\sur", "línea 1\nlínea 2", ""]
    :ok = Storage.agregar("necesidades.txt", campos)

    assert {:ok, [leido]} = Storage.leer("necesidades.txt")
    assert leido == campos
  end

  test "codificar y decodificar son inversas" do
    campos = ["a", "b|c", "\\", "x\ny", "", "ñandú"]

    assert campos |> Storage.codificar_linea() |> Storage.decodificar_linea() == campos
  end

  test "reescribir reemplaza todo el contenido" do
    :ok = Storage.agregar("albergues.txt", ["A01", "Norte", 150])
    :ok = Storage.agregar("albergues.txt", ["A02", "Sur", 80])

    :ok = Storage.reescribir("albergues.txt", [["A02", "Sur", 90]])

    assert {:ok, [["A02", "Sur", "90"]]} = Storage.leer("albergues.txt")
    refute File.exists?(Storage.ruta("albergues.txt") <> ".tmp")
  end

  test "escrituras concurrentes no pierden ni mezclan registros" do
    total = 200

    1..total
    |> Task.async_stream(
      fn i -> Storage.agregar("concurrente.txt", ["id#{i}", "valor|#{i}"]) end,
      max_concurrency: 50
    )
    |> Enum.each(fn {:ok, resultado} -> assert resultado == :ok end)

    assert {:ok, filas} = Storage.leer("concurrente.txt")
    assert length(filas) == total
    assert Enum.all?(filas, fn [id, valor] -> valor == "valor|" <> String.trim_leading(id, "id") end)
    assert filas |> Enum.map(&hd/1) |> Enum.uniq() |> length() == total
  end
end
