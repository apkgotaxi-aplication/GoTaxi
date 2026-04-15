import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/taxista_service.dart';
import 'package:gotaxi/data/services/rating_service.dart';
import 'package:gotaxi/models/rating_model.dart';
import 'package:gotaxi/utils/ratings/rating_utils.dart';

class GestionarTaxistasScreen extends StatefulWidget {
  const GestionarTaxistasScreen({super.key});

  @override
  State<GestionarTaxistasScreen> createState() =>
      _GestionarTaxistasScreenState();
}

class _GestionarTaxistasScreenState extends State<GestionarTaxistasScreen> {
  final _taxistaService = TaxistaService();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _taxistas = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTaxistas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTaxistas() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final isAdmin = await _taxistaService.isUserAdmin();
      if (!isAdmin) {
        if (!mounted) return;
        setState(() {
          _error = 'No tienes permisos de administrador';
          _loading = false;
        });
        return;
      }

      final taxistas = await _taxistaService.listTaxistas();
      if (!mounted) return;
      setState(() {
        _taxistas = taxistas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar taxistas: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openTaxistaDetail(Map<String, dynamic> taxista) async {
    final deletedTaxistaId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _TaxistaDetailScreen(taxista: taxista)),
    );

    if (deletedTaxistaId == null || !mounted) return;

    final usuario = taxista['usuarios'] as Map<String, dynamic>;
    final nombre = usuario['nombre'] as String? ?? '';
    final apellidos = usuario['apellidos'] as String? ?? '';

    setState(() {
      _taxistas.removeWhere((item) => item['id'] == deletedTaxistaId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$nombre $apellidos eliminado correctamente'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredTaxistas {
    if (_searchQuery.isEmpty) return _taxistas;

    return _taxistas.where((taxista) {
      final usuario = taxista['usuarios'] as Map<String, dynamic>;
      final vehiculo = taxista['vehiculos'] as Map<String, dynamic>;

      final searchableFields = [
        usuario['nombre'],
        usuario['apellidos'],
        '${usuario['nombre'] ?? ''} ${usuario['apellidos'] ?? ''}',
        usuario['email'],
        usuario['telefono'],
        vehiculo['matricula'],
        vehiculo['licencia_taxi'],
        vehiculo['marca'],
        vehiculo['modelo'],
        '${vehiculo['marca'] ?? ''} ${vehiculo['modelo'] ?? ''}',
      ];

      return searchableFields.any(
        (field) =>
            (field?.toString().toLowerCase() ?? '').contains(_searchQuery),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredTaxistas = _filteredTaxistas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Taxistas'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState(colorScheme)
          : _taxistas.isEmpty
          ? _buildEmptyState(colorScheme)
          : RefreshIndicator(
              onRefresh: _loadTaxistas,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() => _searchQuery = value.trim().toLowerCase());
                    },
                    decoration: InputDecoration(
                      hintText:
                          'Buscar por nombre, coche, matricula, licencia, email o telefono',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filteredTaxistas.isEmpty)
                    _buildNoSearchResultsState(colorScheme)
                  else
                    ...filteredTaxistas.map(
                      (taxista) => _buildTaxistaCard(taxista, colorScheme),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: colorScheme.error),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadTaxistas,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_taxi_outlined,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay taxistas registrados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crea un nuevo taxista desde el panel de administrador.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 56, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'No hay resultados para tu busqueda',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Prueba con otro nombre, coche, matricula, licencia, email o telefono.',
            style: TextStyle(color: colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTaxistaCard(
    Map<String, dynamic> taxista,
    ColorScheme colorScheme,
  ) {
    final usuario = taxista['usuarios'] as Map<String, dynamic>;
    final nombre = usuario['nombre'] as String? ?? '';
    final apellidos = usuario['apellidos'] as String? ?? '';
    final estado = taxista['estado'] as String? ?? 'no disponible';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openTaxistaDetail(taxista),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: colorScheme.primaryContainer,
          child: Text(
            _buildInitials(nombre, apellidos),
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '$nombre $apellidos'.trim().isEmpty
              ? 'Sin nombre'
              : '$nombre $apellidos'.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _EstadoChip(estado: estado),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  String _buildInitials(String nombre, String apellidos) {
    final firstName = nombre.trim();
    final lastName = apellidos.trim();
    final firstInitial = firstName.isNotEmpty ? firstName[0] : '';
    final lastInitial = lastName.isNotEmpty ? lastName[0] : '';
    final initials = '$firstInitial$lastInitial'.trim();
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }
}

class _TaxistaDetailScreen extends StatefulWidget {
  const _TaxistaDetailScreen({required this.taxista});

  final Map<String, dynamic> taxista;

  @override
  State<_TaxistaDetailScreen> createState() => _TaxistaDetailScreenState();
}

class _TaxistaDetailScreenState extends State<_TaxistaDetailScreen> {
  final _taxistaService = TaxistaService();
  final _ratingService = RatingService();
  final _rideSearchController = TextEditingController();

  late Future<List<Map<String, dynamic>>> _ridesFuture;
  late Future<TaxistaRatingsSummary> _ratingsSummaryFuture;
  bool _deleting = false;
  String _rideSearchQuery = '';

  @override
  void initState() {
    super.initState();
    final taxistaId = widget.taxista['id'] as String;
    _ridesFuture = _taxistaService.getTaxistaRideHistory(taxistaId: taxistaId);
    _ratingsSummaryFuture = _ratingService.getTaxistaRatingsSummary(taxistaId);
  }

  @override
  void dispose() {
    _rideSearchController.dispose();
    super.dispose();
  }

  Future<void> _reloadRides() async {
    final taxistaId = widget.taxista['id'] as String;
    setState(() {
      _ridesFuture = _taxistaService.getTaxistaRideHistory(
        taxistaId: taxistaId,
      );
    });
    await _ridesFuture;
  }

  Future<void> _deleteTaxista() async {
    if (_deleting) return;

    final usuario = widget.taxista['usuarios'] as Map<String, dynamic>;
    final nombre = usuario['nombre'] as String? ?? '';
    final apellidos = usuario['apellidos'] as String? ?? '';
    final taxistaId = widget.taxista['id'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar taxista'),
        content: Text(
          '¿Estás seguro de que deseas eliminar a $nombre $apellidos?\n\n'
          'Esta acción eliminará al taxista, su vehículo y su cuenta de forma permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);

    try {
      await _taxistaService.deleteTaxista(taxistaId: taxistaId);
      if (!mounted) return;
      Navigator.of(context).pop(taxistaId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final usuario = widget.taxista['usuarios'] as Map<String, dynamic>;
    final vehiculo = widget.taxista['vehiculos'] as Map<String, dynamic>;
    final nombre = usuario['nombre'] as String? ?? '';
    final apellidos = usuario['apellidos'] as String? ?? '';
    final email = usuario['email'] as String? ?? '';
    final telefono = usuario['telefono'] as String? ?? '';
    final dni = usuario['dni'] as String? ?? '';
    final estado = widget.taxista['estado'] as String? ?? 'no disponible';
    final isAdmin = widget.taxista['is_admin'] == true;
    final matricula = vehiculo['matricula'] as String? ?? '';
    final marca = vehiculo['marca'] as String? ?? '';
    final modelo = vehiculo['modelo'] as String? ?? '';
    final color = vehiculo['color'] as String? ?? '';
    final licencia = vehiculo['licencia_taxi'] as String? ?? '';
    final capacidad = vehiculo['capacidad']?.toString() ?? 'No disponible';
    final minusvalido = vehiculo['minusvalido'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del taxista')),
      body: RefreshIndicator(
        onRefresh: _reloadRides,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        _buildInitials(nombre, apellidos),
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$nombre $apellidos'.trim().isEmpty
                          ? 'Sin nombre'
                          : '$nombre $apellidos'.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _EstadoChip(estado: estado),
                        if (isAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Administrador',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Informacion personal',
              children: [
                _DetailRow(
                  icon: Icons.badge_outlined,
                  label: 'DNI',
                  value: dni,
                ),
                _DetailRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                ),
                _DetailRow(
                  icon: Icons.phone_outlined,
                  label: 'Telefono',
                  value: telefono,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Vehiculo',
              children: [
                _DetailRow(
                  icon: Icons.directions_car_outlined,
                  label: 'Coche',
                  value: '$marca $modelo - $color',
                ),
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Matricula',
                  value: matricula,
                ),
                _DetailRow(
                  icon: Icons.card_membership_outlined,
                  label: 'Licencia',
                  value: licencia,
                ),
                _DetailRow(
                  icon: Icons.people_outline,
                  label: 'Capacidad',
                  value: capacidad,
                ),
                _DetailRow(
                  icon: Icons.accessible_outlined,
                  label: 'Adaptado',
                  value: minusvalido ? 'Si' : 'No',
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<TaxistaRatingsSummary>(
              future: _ratingsSummaryFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return const SizedBox.shrink();
                }

                final summary = snapshot.data!;
                final incidentPercentageStr =
                    RatingUtils.formatIncidentPercentage(
                      summary.incidentPercentage,
                    );
                final isHighRate = RatingUtils.isHighIncidentRate(
                  summary.incidentPercentage,
                );

                return _DetailSection(
                  title: '📊 Valoraciones',
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isHighRate
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isHighRate
                              ? Colors.red.shade300
                              : Colors.green.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${summary.totalRatings} valoraciones totales',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isHighRate
                                      ? Colors.red.shade200
                                      : Colors.green.shade200,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  incidentPercentageStr,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isHighRate
                                        ? Colors.red.shade700
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      '${summary.positiveCount}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                    Text(
                                      'Positivas ✓',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      '${summary.negativeCount}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade600,
                                      ),
                                    ),
                                    Text(
                                      'Negativas ✗',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (summary.recentIncidents.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              'Últimas incidencias:',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            ...summary.recentIncidents
                                .take(3)
                                .map(
                                  (incident) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.red.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            incident.motivo ?? 'Sin motivo',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (incident.comentario != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              incident.comentario!,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatIncidentDate(
                                              incident.creadoEn,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontStyle: FontStyle.italic,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Viajes realizados',
              children: [
                TextField(
                  controller: _rideSearchController,
                  onChanged: (value) {
                    setState(
                      () => _rideSearchQuery = value.trim().toLowerCase(),
                    );
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar viajes por origen, destino o estado',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _rideSearchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _rideSearchController.clear();
                              setState(() => _rideSearchQuery = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _ridesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colorScheme.error,
                              size: 44,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No se pudieron cargar los viajes',
                              style: TextStyle(color: colorScheme.error),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _reloadRides,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      );
                    }

                    final rides = snapshot.data ?? const [];
                    final filteredRides = rides.where((ride) {
                      if (_rideSearchQuery.isEmpty) return true;

                      final searchableFields = [
                        ride['origen'],
                        ride['destino'],
                        ride['estado'],
                        ride['ciudad_origen'],
                        ride['precio']?.toString(),
                      ];

                      return searchableFields.any(
                        (field) => (field?.toString().toLowerCase() ?? '')
                            .contains(_rideSearchQuery),
                      );
                    }).toList();

                    if (rides.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Este taxista todavia no tiene viajes registrados.',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      );
                    }

                    if (filteredRides.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No hay viajes que coincidan con la busqueda.',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      );
                    }

                    return Column(
                      children: filteredRides
                          .map((ride) => _RideCard(ride: ride))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _deleting ? null : _deleteTaxista,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, color: Colors.red),
              label: Text(
                _deleting ? 'Eliminando...' : 'Eliminar taxista',
                style: const TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  String _formatIncidentDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} minutos';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} horas';
    } else if (difference.inDays < 7) {
      return 'Hace ${difference.inDays} días';
    } else {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day/$month';
    }
  }

  String _buildInitials(String nombre, String apellidos) {
    final firstName = nombre.trim();
    final lastName = apellidos.trim();
    final firstInitial = firstName.isNotEmpty ? firstName[0] : '';
    final lastInitial = lastName.isNotEmpty ? lastName[0] : '';
    final initials = '$firstInitial$lastInitial'.trim();
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value.isEmpty ? 'No disponible' : value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride});

  final Map<String, dynamic> ride;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estado = (ride['estado']?.toString() ?? 'sin estado').toLowerCase();
    final statusColor = switch (estado) {
      'pendiente' => Colors.orange,
      'confirmada' => colorScheme.primary,
      'cancelada' => colorScheme.error,
      'finalizada' => Colors.green,
      'en_curso' => Colors.blue,
      _ => colorScheme.outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${ride['origen'] ?? 'Origen no disponible'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    estado,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Destino: ${ride['destino'] ?? 'No disponible'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text('Precio: ${_formatPrice(ride['precio'])}'),
                Text('Fecha: ${_formatDate(ride['created_at'])}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPrice(dynamic rawValue) {
    if (rawValue == null) return 'No disponible';
    final price = double.tryParse(rawValue.toString());
    if (price == null) return rawValue.toString();
    return '${price.toStringAsFixed(2)} €';
  }

  static String _formatDate(dynamic rawValue) {
    if (rawValue == null) return 'Sin fecha';
    final parsed = DateTime.tryParse(rawValue.toString());
    if (parsed == null) return rawValue.toString();

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (estado) {
      case 'disponible':
        bgColor = Colors.green.withValues(alpha: 0.15);
        textColor = Colors.green.shade700;
        label = 'Disponible';
        break;
      case 'ocupado':
        bgColor = Colors.orange.withValues(alpha: 0.15);
        textColor = Colors.orange.shade700;
        label = 'Ocupado';
        break;
      default:
        bgColor = Colors.grey.withValues(alpha: 0.15);
        textColor = Colors.grey.shade700;
        label = 'No disponible';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}
