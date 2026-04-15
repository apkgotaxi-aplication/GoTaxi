import 'package:gotaxi/models/rating_model.dart';

/// Constants and helper functions for the ratings system
class RatingConstants {
  // Predefined reasons/motives for negative ratings
  static const List<RatingMotive> negativeMotives = [
    RatingMotive.imprudente,
    RatingMotive.sucio,
    RatingMotive.ruta_incorrecta,
  ];

  // Display strings for motives
  static const Map<RatingMotive, String> motiveDisplayNames = {
    RatingMotive.imprudente: 'Conductor imprudente',
    RatingMotive.sucio: 'Vehículo sucio',
    RatingMotive.ruta_incorrecta: 'Ruta incorrecta',
  };

  // Icons/colors for rating types
  static const String positiveIcon = '👍';
  static const String negativeIcon = '👎';
}

/// Utility functions for rating formatting and display
class RatingUtils {
  /// Format incident percentage to display with 2 decimal places
  /// If percentage is 0-1%, display as "< 1%", otherwise show exact %
  static String formatIncidentPercentage(double percentage) {
    if (percentage == 0) {
      return '0%';
    } else if (percentage < 1) {
      return '< 1%';
    } else {
      return '${percentage.toStringAsFixed(1)}%';
    }
  }

  /// Get color based on incident percentage
  /// Red if > 20%, yellow if 5-20%, green if < 5%
  static String getIncidentColorCategory(double percentage) {
    if (percentage > 20) {
      return 'red';
    } else if (percentage >= 5) {
      return 'yellow';
    } else {
      return 'green';
    }
  }

  /// Get a friendly summary of a taxista's ratings
  /// Example: "5,234 ratings | 98% ✓ | 2% ✗"
  static String getSummaryText(TaxistaRatingsSummary summary) {
    if (summary.totalRatings == 0) {
      return 'Sin valoraciones aún';
    }

    final totalStr = _formatNumber(summary.totalRatings);
    final positivePercentage =
        ((summary.positiveCount / summary.totalRatings) * 100).toStringAsFixed(
          0,
        );
    final incidentStr = formatIncidentPercentage(summary.incidentPercentage);

    return '$totalStr valoraciones | $positivePercentage% ✓ | $incidentStr ✗';
  }

  /// Format a number with thousand separators
  /// Example: 1234 -> "1.234", 1000000 -> "1.000.000"
  static String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (Match match) => '.',
    );
  }

  /// Get incident description for a rating
  static String getIncidentDescription(RatingIncident incident) {
    final motiveStr = incident.motivo != null
        ? RatingConstants.motiveDisplayNames[RatingMotiveExtension.fromString(
            incident.motivo!,
          )]
        : 'Incidencia indeterminada';

    final commentStr = incident.comentario != null
        ? '\n${incident.comentario}'
        : '';

    return '$motiveStr$commentStr';
  }

  /// Check if a percentage of incidents is considered high
  /// Returns true if percentage > 20%
  static bool isHighIncidentRate(double percentage) {
    return percentage > 20;
  }
}
