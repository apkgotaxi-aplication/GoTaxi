### **Propuesta de Proyecto DAM \- Aplicación para Taxis (GoTaxi)**

*\-**ÍNDICE***

1. ***Funcionalidades clave.***  
2. ***Objetivos del proyecto.***  
3. ***Horas repartidas.***

Nuestro proyecto consiste en desarrollar una aplicación móvil complementaria a la página web GoTaxi, creada por Eduardo Sumariva Salgado (colaborador JuanilloKing) en su segundo año de DAW. El objetivo principal es ofrecer una experiencia de usuario más completa, fluida y adaptada a dispositivos móviles para la gestión de viajes en taxi, ya que como veremos a continuación, tendrá funcionalidades más útiles al estar disponible en un dispositivo móvil.

El enfoque de esta aplicación se centrará en dos tipos de usuarios: los clientes, que necesitan solicitar un servicio de taxi, y los taxistas, que gestionan sus viajes y ganancias. (Aunque también tendremos administradores, pero estos no los consideramos un nuevo tipo de usuario, tan solo una característica que tendrán algunos, ya sean como meros usuarios o taxistas)

1. ### **Funcionalidades Clave de la Aplicación**

Con esta aplicación, planeamos implementar las siguientes funcionalidades principales:

* **Consultar tarifas**: Los usuarios podrán calcular el precio de un viaje entre dos puntos, ver la distancia, el tiempo estimado y el costo total.  
* **Reservar un viaje**: La aplicación permitirá a los clientes reservar un taxi para el momento o programar un viaje para una fecha futura. Se aplicará una distancia mínima para las reservas.  
* **Servicios especiales**: incluiremos un apartado dentro de las reservas para que los usuarios puedan especificar necesidades especiales, como asistencia para personas con discapacidad.  
* **Notificaciones**: Una vez que un cliente realice una reserva, la app notificará al taxista disponible más cercano. Si el taxista la acepta, el cliente recibirá una confirmación con los datos del taxi. Si la rechaza, la notificación pasará al siguiente taxista.  
* **Seguimiento en tiempo real**: Esta es una de las funcionalidades más importantes para la aplicación móvil. Los usuarios podrán ver en un mapa en tiempo real la ubicación de su taxi, el tiempo de llegada estimado y la ruta que sigue.  
* **Pagos integrados**: Queremos que los usuarios puedan vincular su tarjeta de crédito y pagar por el viaje directamente a través de la aplicación, haciendo la experiencia más cómoda y segura (probablemente usaremos Stripe).  
* **Gestión de perfiles**: Habrá perfiles separados para clientes y taxistas. Los usuarios podrán ver su historial de viajes, guardar direcciones frecuentes y gestionar sus métodos de pago, y los taxistas, el registro de los viajes realizados con información del cliente, si actualmente esta disponible, no disponible o ocupado, y si esta no disponible, sus ganancias, ver su viaje actual, hacia donde va el cliente, y el tiempo estimado que tardará en completar dicha tarea.  
* **Notificaciones push**: Utilizaremos notificaciones push para mantener a los usuarios y taxistas informados al instante sobre el estado de un viaje, confirmaciones y cancelaciones.
* **administradores**: Los administradores serán los encargados de crear a los taxistas.


2. ### **Objetivos del Proyecto**

Nuestros objetivos para este proyecto se dividen en tres áreas principales:

* **Gestionar usuarios**: Nos centraremos en el desarrollo de funcionalidades que permitan a los usuarios crear, modificar y eliminar sus perfiles.  
* **Gestionar taxistas**: Para los taxistas, nuestro objetivo es crear un sistema para que puedan gestionar sus perfiles, aceptar y ver sus viajes y llevar un registro de su actividad.  
* **Gestionar reservas**: La meta final es optimizar el sistema de reservas, facilitando el proceso tanto para el cliente, con un sistema de notificaciones y confirmación, como para el taxista, con la gestión de solicitudes.
* **Gestión tarifas**: Las tarifas de cada provincia, podrán ser modificadas, tanto el precio por kilometro, como el precio por hora.

En resumen, nuestro proyecto busca llevar la plataforma web creada por Eduardo Sumariva Salgado, a otro nivel, ofreciendo una aplicación móvil que no solo replique las funcionalidades existentes, sino que las mejore con características nativas de los dispositivos móviles, creando una experiencia más completa y moderna, con una interfaz mucho más intuitiva.

APIS a usar: OpenstreetMap, agendaPro, Stripe
