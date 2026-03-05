#!/bin/bash

create_issue() {
  title="$1"
  body="$2"
  labels="$3"

  echo "Creando issue: $title..."
  gh issue create --title "$title" --body "$body" --label "$labels"
}

echo "🚀 Iniciando carga de trabajo ordenada para: $PROJECT_NAME..."


create_issue "RF20 - Tabla Municipios" "Creación y poblado de la tabla municipios (Catálogo)." "Database"
create_issue "RF21 - Tabla Provincia" "Creación y poblado de la tabla provincia (Catálogo)." "Database"
create_issue "RF22 - Tabla Tarifas" "Creación de la tabla tarifas para cálculo de precios base." "Database"


create_issue "RF01 - Registro de Cliente" "Un cliente podrá crearse una cuenta (correo, contraseña, nombre, apellidos, edad, dni...)." "FrontEnd,BackEnd,Database"
create_issue "RF26 - Recuperar Contraseña" "Sistema para restablecer contraseña (email con token/link)." "BackEnd,FrontEnd,Database"
create_issue "RF27 - Cerrar Sesión" "Lógica de Logout: invalidar tokens y limpiar almacenamiento local." "FrontEnd,BackEnd"
create_issue "RF03 - Cliente: Modificar Perfil" "Los clientes podrán modificar datos: email, contraseña, nombre, apellidos." "FrontEnd,BackEnd,Database"
create_issue "RF06 - Admin: Eliminar Cliente" "Eliminar cliente si y solo si no tiene viajes activos o pendientes." "BackEnd,Database"


create_issue "RF02 - Admin: Crear Taxista" "Un administrador podrá crear un taxista (datos de cliente + placa, localidad, vehículo, etc.)." "FrontEnd,BackEnd,Database"
create_issue "RF28 - Admin Dashboard" "Panel principal del administrador para ver métricas clave y acceso rápido a gestión de usuarios." "FrontEnd,BackEnd"
create_issue "RF04 - Taxista: Modificar Perfil" "Los taxistas podrán modificar datos: vehículo usado, teléfono." "FrontEnd,BackEnd,Database"
create_issue "RF05 - Admin: Baja de Taxista" "Dar de baja a un taxista del sistema." "BackEnd,Database"


create_issue "RF16 - Geolocalización Taxista" "Obtener geolocalización en tiempo real del taxista y mostrar en mapa." "FrontEnd,BackEnd"
create_issue "RF09 - Reservar Viaje (Cálculo)" "Proporcionar ubicación origen/destino. Calcular distancia, tiempo y precio aproximado." "FrontEnd,BackEnd"
create_issue "RF11 - Notificación a Taxista" "Notificar al taxista de un viaje entrante (Push/Socket)." "BackEnd,FrontEnd"
create_issue "RF12 - Notificación a Cliente" "Notificar al cliente sobre la aceptación/estado de su reserva." "BackEnd,FrontEnd"
create_issue "RF17 - Cálculo ETA Real" "Calcular distancia y tiempo aproximado de llegada del taxista a donde está el cliente." "BackEnd,FrontEnd"
create_issue "RF23 - Verificación por Código" "Cliente da código de 4 dígitos al taxista para iniciar viaje (Seguridad)." "FrontEnd,BackEnd"
create_issue "RF10 - Cancelar Viaje" "Lógica para cancelar un viaje actual (con penalización o sin ella)." "FrontEnd,BackEnd,Database"


create_issue "RF13 - Sistema de Pago" "Integración de pasarela de pago (Stripe/PayPal/API Banco)." "BackEnd,FrontEnd"
create_issue "RF19 - Devolución de Dinero" "Devolución del pago si el viaje no está en curso." "BackEnd,Database"
create_issue "RF30 - Mostrar Mapa" "Introduccion en la aplicacion del mapa mediante API de Google Maps." "BackEnd,Database"
create_issue "RF07 - Taxista: Historial de Viajes" "Consultar historial de viajes realizados con ganancias." "FrontEnd,BackEnd,Database"
create_issue "RF08 - Cliente: Historial de Viajes" "Consultar historial de viajes realizados con detalles." "FrontEnd,BackEnd,Database"


create_issue "RF18 - Sistema de Valoración" "Clientes valoran taxistas. Solo visible para administradores." "FrontEnd,BackEnd,Database"
create_issue "RF24 - Programación de Viajes" "Permitir reservar taxi para fecha y hora futura (Cron jobs)." "FrontEnd,BackEnd,Database"
create_issue "RF25 - Favoritos" "Guardar direcciones frecuentes (Casa, Trabajo) para agilizar reservas." "FrontEnd,BackEnd,Database"


create_issue "RF14 - Información Empresas" "Creación apartado información para empresas." "FrontEnd"
create_issue "RF15 - Sobre Nosotros" "Creación apartado sobre nosotros y contacto." "FrontEnd"
create_issue "RF29 - FAQ" "Creación apartado de preguntas frecuentes para clientes y taxistas." "FrontEnd"
create_issue "RF30 - Crear navegacion entre pantalllas" "Se implementará la navegación entre pantallas como el mapa, o el perfil, mediante barra de navegación inferior." "FrontEnd"



echo "--------------------------------------------------------"
echo "Isues creadas y asignadas al proyecto"