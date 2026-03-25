import 'dart:math' show pow;

/// Pricing constants for MVP fare estimation
class PricingConstants {
  /// Fixed base fare in EUR (banderazo)
  static const double baseFareEur = 3.50;

  /// Price per kilometer in EUR
  static const double pricePerKmEur = 1.20;

  /// Price per minute in EUR
  static const double pricePerMinuteEur = 0.30;

  /// Currency symbol for display
  static const String currencySymbol = '€';

  /// Decimal places for fare rounding
  static const int decimalPlaces = 2;

  /// Calculate estimated fare given kilometers and minutes
  ///
  /// Formula: baseFare + (km * pricePerKm) + (minutes * pricePerMinute)
  static double calculateEstimatedFare({
    required double kilometers,
    required double minutes,
  }) {
    final total =
        baseFareEur +
        (kilometers * pricePerKmEur) +
        (minutes * pricePerMinuteEur);
    return _roundToDecimals(total, decimalPlaces);
  }

  /// Round a double value to a specific number of decimal places
  static double _roundToDecimals(double value, int decimals) {
    final factor = pow(10, decimals) as int;
    return (value * factor).round() / factor;
  }
}
