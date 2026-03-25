import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const List<({String question, String answer})> _faqItems = [
    (
      question: '¿Cómo solicito un taxi?',
      answer:
          'Abre la pestaña de mapa, indica tu ubicación de recogida y confirma el destino para pedir un taxi en segundos.',
    ),
    (
      question: '¿Puedo cancelar un viaje?',
      answer:
          'Sí, puedes cancelar el viaje antes de que comience desde el detalle del viaje. En algunos casos puede aplicarse una tarifa de cancelación.',
    ),
    (
      question: '¿Qué métodos de pago están disponibles?',
      answer:
          'Puedes pagar con tarjeta, efectivo o métodos digitales compatibles según tu zona y la disponibilidad del conductor.',
    ),
    (
      question: '¿Cómo contacto con soporte?',
      answer:
          'Desde la sección Ayuda puedes abrir el chat, enviar un correo o llamar al equipo de soporte para resolver cualquier incidencia.',
    ),
    (
      question: '¿Dónde veo mis viajes anteriores?',
      answer:
          'En la sección de perfil, entra en Mis viajes para consultar el historial y los detalles de tus trayectos recientes.',
    ),
    (
      question: '¿Cómo actualizo mis datos personales?',
      answer:
          'Ve a Perfil > Mis datos, edita la información que necesites y pulsa Guardar cambios para actualizar tu cuenta.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Preguntas frecuentes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Encuentra respuestas rapidas a las dudas mas comunes.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ..._faqItems.map(
            (item) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  item.question,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [Text(item.answer)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
