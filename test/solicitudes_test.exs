defmodule Emergencias.SolicitudesTest do
  use ExUnit.Case, async: true

  alias Emergencias.Solicitudes

  defp con_dos do
    {:ok, _n, mapa} =
      Solicitudes.registrar(%{}, "agua", 30, "media", "centro", "Punto sector 3", "laura")

    {:ok, _n, mapa} =
      Solicitudes.registrar(mapa, "agua", 25, "critica", "norte", "Albergue norte", "andres")

    mapa
  end

  describe "registrar/7" do
    test "genera ids únicos y consecutivos" do
      {:ok, primera, mapa} = Solicitudes.registrar(%{}, "agua", 30, "critica", "centro")
      {:ok, segunda, _mapa} = Solicitudes.registrar(mapa, :alimentos, 10, :alta, "centro")

      assert primera.id == "N001"
      assert segunda.id == "N002"
      assert primera.estado == :pendiente
    end

    test "acepta texto con mayúsculas y tildes" do
      assert {:ok, necesidad, _} =
               Solicitudes.registrar(%{}, "Primeros Auxilios", 3, "Crítica", "centro")

      assert necesidad.tipo == :primeros_auxilios
      assert necesidad.prioridad == :critica
    end

    test "rechaza datos inválidos sin modificar el mapa" do
      assert {:error, :tipo_invalido} = Solicitudes.registrar(%{}, "oro", 3, "alta", "centro")
      assert {:error, :prioridad_invalida} = Solicitudes.registrar(%{}, "agua", 3, "urgente", "centro")
      assert {:error, :cantidad_invalida} = Solicitudes.registrar(%{}, "agua", 0, "alta", "centro")
      assert {:error, :cantidad_invalida} = Solicitudes.registrar(%{}, "agua", -4, "alta", "centro")
      assert {:error, :cantidad_invalida} = Solicitudes.registrar(%{}, "agua", "30", "alta", "centro")
      assert {:error, :zona_invalida} = Solicitudes.registrar(%{}, "agua", 3, "alta", "  ")
    end
  end

  describe "cambiar_estado/3" do
    test "sigue el camino válido hasta atendida" do
      {:ok, _n, mapa} = Solicitudes.registrar(%{}, "agua", 30, "alta", "centro")

      {:ok, n, mapa} = Solicitudes.cambiar_estado(mapa, "N001", :asignada)
      assert n.estado == :asignada
      {:ok, n, mapa} = Solicitudes.cambiar_estado(mapa, "N001", "en atención")
      assert n.estado == :en_atencion
      {:ok, n, _mapa} = Solicitudes.cambiar_estado(mapa, "n001", "atendida")
      assert n.estado == :atendida
    end

    test "rechaza transiciones inválidas" do
      {:ok, _n, mapa} = Solicitudes.registrar(%{}, "agua", 30, "alta", "centro")

      assert {:error, :transicion_invalida} = Solicitudes.cambiar_estado(mapa, "N001", :en_atencion)
      assert {:error, :transicion_invalida} = Solicitudes.cambiar_estado(mapa, "N001", :atendida)
      assert {:error, :estado_invalido} = Solicitudes.cambiar_estado(mapa, "N001", :volando)
      assert {:error, :no_existe} = Solicitudes.cambiar_estado(mapa, "N999", :cancelada)
    end

    test "una necesidad cerrada no se puede cerrar ni reabrir" do
      {:ok, _n, mapa} = Solicitudes.registrar(%{}, "agua", 30, "alta", "centro")
      {:ok, _n, mapa} = Solicitudes.cambiar_estado(mapa, "N001", :cancelada)

      assert {:error, :necesidad_cerrada} = Solicitudes.cambiar_estado(mapa, "N001", :cancelada)
      assert {:error, :necesidad_cerrada} = Solicitudes.cambiar_estado(mapa, "N001", :atendida)
      assert {:error, :necesidad_cerrada} = Solicitudes.cambiar_estado(mapa, "N001", :pendiente)
    end
  end

  describe "asignación" do
    test "una asignación parcial deja la necesidad pendiente" do
      mapa = con_dos()
      assert {:ok, _n} = Solicitudes.puede_asignar(mapa, "N001", 10)

      {:ok, n, mapa} = Solicitudes.aplicar_asignacion(mapa, "N001", [{"R001", 10}])
      assert n.estado == :pendiente
      assert Solicitudes.asignado(n) == 10
      assert Solicitudes.restante(n) == 20

      {:ok, n, _mapa} = Solicitudes.aplicar_asignacion(mapa, "N001", [{"R001", 15}, {"R002", 5}])
      assert n.estado == :asignada
      assert Solicitudes.restante(n) == 0
    end

    test "no permite pasarse de lo que falta" do
      mapa = con_dos()
      assert {:error, :excede_necesidad} = Solicitudes.puede_asignar(mapa, "N001", 31)
      assert {:error, :cantidad_invalida} = Solicitudes.puede_asignar(mapa, "N001", 0)
      assert {:error, :no_existe} = Solicitudes.puede_asignar(mapa, "N999", 5)
    end

    test "una necesidad asignada, atendida o cancelada no consume más recursos" do
      mapa = con_dos()
      {:ok, _n, asignada} = Solicitudes.aplicar_asignacion(mapa, "N001", [{"R001", 30}])
      assert {:error, :ya_asignada} = Solicitudes.puede_asignar(asignada, "N001", 1)

      {:ok, _n, atendida} = Solicitudes.cambiar_estado(asignada, "N001", :atendida)
      assert {:error, :necesidad_cerrada} = Solicitudes.puede_asignar(atendida, "N001", 1)

      {:ok, _n, cancelada} = Solicitudes.cambiar_estado(mapa, "N002", :cancelada)
      assert {:error, :necesidad_cerrada} = Solicitudes.puede_asignar(cancelada, "N002", 1)
    end
  end

  describe "consultas y prioridad" do
    test "consultar/2 ordena por prioridad y desempata por id" do
      {:ok, _n, mapa} = Solicitudes.registrar(%{}, "agua", 5, "baja", "centro")
      {:ok, _n, mapa} = Solicitudes.registrar(mapa, "agua", 5, "critica", "centro")
      {:ok, _n, mapa} = Solicitudes.registrar(mapa, "agua", 5, "media", "centro")
      {:ok, _n, mapa} = Solicitudes.registrar(mapa, "agua", 5, "critica", "centro")

      assert Enum.map(Solicitudes.consultar(mapa), & &1.id) == ["N002", "N004", "N003", "N001"]
    end

    test "filtra por zona, tipo, prioridad y estado" do
      mapa = con_dos()
      {:ok, _n, mapa} = Solicitudes.registrar(mapa, "alimentos", 8, "alta", "Centro")
      {:ok, _n, mapa} = Solicitudes.cambiar_estado(mapa, "N001", :cancelada)

      ids = fn filtros -> mapa |> Solicitudes.consultar(filtros) |> Enum.map(& &1.id) end

      assert ids.(zona: "centro") == ["N003", "N001"]
      assert ids.(tipo: "agua") == ["N002", "N001"]
      assert ids.(prioridad: "critica") == ["N002"]
      assert ids.(estado: :cancelada) == ["N001"]
      assert ids.(zona: "centro", tipo: :agua) == ["N001"]
      assert ids.(zona: "no_existe") == []
      assert ids.(tipo: "inventado") == []
    end

    test "pendientes/1 deja fuera las cerradas" do
      {:ok, _n, mapa} = Solicitudes.cambiar_estado(con_dos(), "N002", :cancelada)
      assert [%{id: "N001"}] = Solicitudes.pendientes(mapa)
    end
  end

  describe "planificar/2" do
    test "atiende por prioridad y salta lo que ya no alcanza" do
      ordenadas = Solicitudes.pendientes(con_dos())

      assert [{"N002", "agua", 25}] = Solicitudes.planificar(ordenadas, %{"agua" => 50})
    end

    test "con inventario suficiente atiende todas, en orden" do
      ordenadas = Solicitudes.pendientes(con_dos())

      assert [{"N002", "agua", 25}, {"N001", "agua", 30}] =
               Solicitudes.planificar(ordenadas, %{"agua" => 55})
    end

    test "sin inventario del tipo no planifica nada" do
      assert [] = Solicitudes.planificar(Solicitudes.pendientes(con_dos()), %{"arroz" => 100})
      assert [] = Solicitudes.planificar([], %{"agua" => 10})
    end
  end

  describe "filas de persistencia" do
    test "a_fila/1 y desde_fila/1 son inversas, incluidas las asignaciones" do
      {:ok, _n, mapa} = Solicitudes.registrar(%{}, "agua", 30, "critica", "centro", "con | barra", "laura")
      {:ok, necesidad, _mapa} = Solicitudes.aplicar_asignacion(mapa, "N001", [{"R001", 10}, {"R002@albergue_2", 5}])

      fila = necesidad |> Solicitudes.a_fila() |> Enum.map(&to_string/1)
      assert {:ok, leida} = Solicitudes.desde_fila(fila)
      assert leida == necesidad
    end

    test "una fila dañada devuelve :error" do
      assert :error = Solicitudes.desde_fila(["N001", "agua"])
      assert :error = Solicitudes.desde_fila(["N001", "oro", "", "5", "centro", "alta", "", "pendiente", ""])
      assert :error = Solicitudes.desde_fila(["N001", "agua", "", "x", "centro", "alta", "", "pendiente", ""])
      assert :error = Solicitudes.desde_fila(["N001", "agua", "", "5", "centro", "alta", "", "pendiente", "R001"])
    end
  end
end
