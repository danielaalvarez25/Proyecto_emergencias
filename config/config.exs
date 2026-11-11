import Config

# En las pruebas los procesos se inician desde cada test (con su propio
# directorio de datos), no al arrancar la aplicación.
config :emergencias, iniciar_procesos: config_env() != :test
