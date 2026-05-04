import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gotaxi/models/rating_model.dart';

class RatingService {
  RatingService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> _sendPushNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _supabase.functions.invoke(
        'send-notification',
        body: {'user_id': userId, 'title': title, 'body': body, 'data': data},
      );
    } catch (_) {}
  }

  /// Submit a rating for a completed ride
  /// Returns SubmitRatingResult with success status and rating ID if successful
  Future<SubmitRatingResult> submitRating({
    required String viajeId,
    required String taxistaId,
    required RatingType tipo,
    RatingMotive? motivo,
    String? comentario,
  }) async {
    try {
      // Only negative ratings require a motive
      if (tipo == RatingType.negativa && motivo == null) {
        return const SubmitRatingResult(
          success: false,
          message: 'El motivo es obligatorio para valoraciones negativas',
        );
      }

      if (tipo == RatingType.negativa && motivo == RatingMotive.otra) {
        if (comentario == null || comentario.trim().isEmpty) {
          return const SubmitRatingResult(
            success: false,
            message: 'Debes escribir el motivo cuando selecciones "Otra"',
          );
        }
      }

      // Call the RPC function from Supabase
      final response = await _supabase.rpc(
        'submit_ride_rating',
        params: {
          'p_viaje_id': viajeId,
          'p_taxista_id': taxistaId,
          'p_tipo_valoracion': tipo.toStringValue(),
          'p_motivo': motivo?.toStringValue(),
          'p_comentario': comentario,
        },
      );

      if (response == null) {
        return const SubmitRatingResult(
          success: false,
          message: 'Error al conectar con el servidor',
        );
      }

      // response should be a list with one element [{ success, message, rating_id }]
      if (response is List && response.isNotEmpty) {
        final result = response[0] as Map<String, dynamic>;
        final submitResult = SubmitRatingResult.fromMap(result);

        // Send notification to taxista about the rating
        if (submitResult.success) {
          final ratingTypeText = tipo == RatingType.positiva ? 'positiva' : 'negativa';
          await _sendPushNotification(
            userId: taxistaId,
            title: 'Nueva valoración recibida',
            body: 'Has recibido una valoración $ratingTypeText en tu viaje',
            data: {'viaje_id': viajeId, 'tipo': 'valoracion_recibida'},
          );
        }

        return submitResult;
      }

      return const SubmitRatingResult(
        success: false,
        message: 'Formato de respuesta inesperado del servidor',
      );
    } on AuthException catch (e) {
      return SubmitRatingResult(
        success: false,
        message: 'Error de autenticación: ${e.message}',
      );
    } catch (e) {
      return SubmitRatingResult(
        success: false,
        message: 'Error al enviar valoración: $e',
      );
    }
  }

  /// Check if a ride has already been rated
  /// Returns RideRatingCheckResult with isRated and ratingType if available
  Future<RideRatingCheckResult> checkIfRideRated(String viajeId) async {
    try {
      final response = await _supabase.rpc(
        'check_ride_rated',
        params: {'p_ride_id': viajeId},
      );

      if (response == null) {
        return const RideRatingCheckResult(isRated: false);
      }

      // response should be a list with one element [{ is_rated, rating_type }]
      if (response is List && response.isNotEmpty) {
        final result = response[0] as Map<String, dynamic>;
        return RideRatingCheckResult.fromMap(result);
      }

      return const RideRatingCheckResult(isRated: false);
    } on AuthException catch (e) {
      print('Auth error checking ride rating: ${e.message}');
      return const RideRatingCheckResult(isRated: false);
    } catch (e) {
      print('Error checking ride rating: $e');
      return const RideRatingCheckResult(isRated: false);
    }
  }

  /// Get the ratings summary for a taxista (for admin dashboard)
  /// Returns TaxistaRatingsSummary with total, positive, negative counts and recent incidents
  Future<TaxistaRatingsSummary> getTaxistaRatingsSummary(
    String taxistaId,
  ) async {
    try {
      final response = await _supabase.rpc(
        'get_taxista_ratings_summary',
        params: {'p_taxista_id': taxistaId},
      );

      if (response == null) {
        return const TaxistaRatingsSummary(
          totalRatings: 0,
          positiveCount: 0,
          negativeCount: 0,
          incidentPercentage: 0.0,
          recentIncidents: [],
        );
      }

      // response should be a list with one element [{ total_ratings, positive_count, ... }]
      if (response is List && response.isNotEmpty) {
        final result = response[0] as Map<String, dynamic>;
        return TaxistaRatingsSummary.fromMap(result);
      }

      return const TaxistaRatingsSummary(
        totalRatings: 0,
        positiveCount: 0,
        negativeCount: 0,
        incidentPercentage: 0.0,
        recentIncidents: [],
      );
    } on AuthException catch (e) {
      print('Auth error getting ratings summary: ${e.message}');
      return const TaxistaRatingsSummary(
        totalRatings: 0,
        positiveCount: 0,
        negativeCount: 0,
        incidentPercentage: 0.0,
        recentIncidents: [],
      );
    } catch (e) {
      print('Error getting ratings summary: $e');
      return const TaxistaRatingsSummary(
        totalRatings: 0,
        positiveCount: 0,
        negativeCount: 0,
        incidentPercentage: 0.0,
        recentIncidents: [],
      );
    }
  }
}
