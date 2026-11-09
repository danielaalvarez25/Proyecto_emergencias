# Emergencias

Sistema distribuido de coordinación y gestión de emergencias (terremoto) en Elixir.
Proyecto final de Programación III, Universidad del Quindío.

## Equipo

| Persona | Responsabilidad |
|---|---|
| A | OTP (Supervisor, DynamicSupervisor), recursos, necesidades, albergues, persistencia, concurrencia |
| B | Usuarios, zonas, personas y mensajes, mascotas, CLI y `summary` |

## Contrato común

- Toda función de dominio devuelve `{:ok, valor}` o `{:error, razon}` (`Emergencias.Resultado`).
- Persistencia en texto plano con `Emergencias.Storage`: una línea por registro, `campo|campo|campo`.
- Los `struct` del dominio están en `lib/emergencias/dominio/`.

## Ejecutar

```bash
mix deps.get
mix compile
mix test
```

Los datos se guardan en `data/` (se puede cambiar con `config :emergencias, :data_dir, "ruta"`).

## Ramas

`main` (integración), `persona-a`, `persona-b`.
