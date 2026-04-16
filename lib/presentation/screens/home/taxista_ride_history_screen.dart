import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/taxista_service.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

enum RideHistorySortOption {
  dateDesc,
  dateAsc,
  durationDesc,
  durationAsc,
  priceDesc,
  priceAsc,
}

class TaxistaRideHistoryScreen extends StatefulWidget {
  const TaxistaRideHistoryScreen({
    super.key,
    required this.taxistaId,
    required this.taxistaName,
  });

  final String taxistaId;
  final String taxistaName;

  @override
  State<TaxistaRideHistoryScreen> createState() =>
      _TaxistaRideHistoryScreenState();
}

class _TaxistaRideHistoryScreenState extends State<TaxistaRideHistoryScreen> {
  static const int _pageSize = 10;

  final TaxistaService _taxistaService = TaxistaService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<Map<String, dynamic>>> _ridesFuture;

  String _searchQuery = '';
  RideHistorySortOption _sortOption = RideHistorySortOption.dateDesc;
  DateTimeRange? _dateRange;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _ridesFuture = _taxistaService.getTaxistaRideHistory(
      taxistaId: widget.taxistaId,
      limit: 1000,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _ridesFuture = _taxistaService.getTaxistaRideHistory(
        taxistaId: widget.taxistaId,
        limit: 1000,
      );
    });
    await _ridesFuture;
  }

  void _resetPage() {
    if (_currentPage != 0) {
      setState(() {
        _currentPage = 0;
      });
    }
  }

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value.trim().toLowerCase();
    });
    _resetPage();
  }

  void _setSortOption(RideHistorySortOption option) {
    setState(() {
      _sortOption = option;
    });
    _resetPage();
  }

  Future<void> _pickDateRange() async {
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );

    if (!mounted || selectedRange == null) return;

    setState(() {
      _dateRange = selectedRange;
      _currentPage = 0;
    });
  }

  void _clearDateRange() {
    setState(() {
      _dateRange = null;
      _currentPage = 0;
    });
  }

  List<Map<String, dynamic>> _filterAndSortRides(
    List<Map<String, dynamic>> rides,
  ) {
    final filtered = rides.where((ride) {
      if (_searchQuery.isNotEmpty) {
        final fields = [
          ride['origen'],
          ride['destino'],
          ride['estado'],
          ride['ciudad_origen'],
        ];

        final matchesSearch = fields.any(
          (field) =>
              (field?.toString().toLowerCase() ?? '').contains(_searchQuery),
        );
        if (!matchesSearch) return false;
      }

      if (_dateRange != null) {
        final rideDate = DateTime.tryParse(
          ride['created_at']?.toString() ?? '',
        );
        if (rideDate == null) return false;

        final localDate = rideDate.toLocal();
        final from = DateTime(
          _dateRange!.start.year,
          _dateRange!.start.month,
          _dateRange!.start.day,
        );
        final to = DateTime(
          _dateRange!.end.year,
          _dateRange!.end.month,
          _dateRange!.end.day,
          23,
          59,
          59,
          999,
        );

        if (localDate.isBefore(from) || localDate.isAfter(to)) {
          return false;
        }
      }

      return true;
    }).toList();

    filtered.sort(_compareRides);
    return filtered;
  }

  int _compareRides(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (_sortOption) {
      case RideHistorySortOption.dateDesc:
        return _rideDate(b).compareTo(_rideDate(a));
      case RideHistorySortOption.dateAsc:
        return _rideDate(a).compareTo(_rideDate(b));
      case RideHistorySortOption.durationDesc:
        return _rideDuration(b).compareTo(_rideDuration(a));
      case RideHistorySortOption.durationAsc:
        return _rideDuration(a).compareTo(_rideDuration(b));
      case RideHistorySortOption.priceDesc:
        return _ridePrice(b).compareTo(_ridePrice(a));
      case RideHistorySortOption.priceAsc:
        return _ridePrice(a).compareTo(_ridePrice(b));
    }
  }

  DateTime _rideDate(Map<String, dynamic> ride) {
    return DateTime.tryParse(ride['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _rideDuration(Map<String, dynamic> ride) {
    return int.tryParse(ride['duracion']?.toString() ?? '') ?? 0;
  }

  double _ridePrice(Map<String, dynamic> ride) {
    return double.tryParse(ride['precio']?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Viajes de ${widget.taxistaName}')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ridesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 52,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No se pudo cargar el historial completo.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          final rides = snapshot.data ?? const [];
          final filtered = _filterAndSortRides(rides);
          final totalPages = filtered.isEmpty
              ? 1
              : ((filtered.length + _pageSize - 1) ~/ _pageSize);
          final safePage = _currentPage.clamp(0, totalPages - 1).toInt();
          final startIndex = safePage * _pageSize;
          final endIndex = (startIndex + _pageSize).clamp(0, filtered.length);
          final pageRides = filtered.isEmpty
              ? const <Map<String, dynamic>>[]
              : filtered.sublist(startIndex, endIndex);

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: _setSearchQuery,
                  decoration: InputDecoration(
                    hintText: 'Buscar por origen, destino o estado',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _setSearchQuery('');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_dateRange != null)
                      TextButton(
                        onPressed: _clearDateRange,
                        child: const Text('Limpiar fecha'),
                      ),
                    PopupMenuButton<RideHistorySortOption>(
                      onSelected: _setSortOption,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: RideHistorySortOption.dateDesc,
                          child: Text('Fecha: más recientes primero'),
                        ),
                        PopupMenuItem(
                          value: RideHistorySortOption.dateAsc,
                          child: Text('Fecha: más antiguos primero'),
                        ),
                        PopupMenuItem(
                          value: RideHistorySortOption.durationDesc,
                          child: Text('Duración: mayor a menor'),
                        ),
                        PopupMenuItem(
                          value: RideHistorySortOption.durationAsc,
                          child: Text('Duración: menor a mayor'),
                        ),
                        PopupMenuItem(
                          value: RideHistorySortOption.priceDesc,
                          child: Text('Precio: mayor a menor'),
                        ),
                        PopupMenuItem(
                          value: RideHistorySortOption.priceAsc,
                          child: Text('Precio: menor a mayor'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, size: 18),
                            const SizedBox(width: 8),
                            Text(switch (_sortOption) {
                              RideHistorySortOption.dateDesc =>
                                'Orden: fecha ↓',
                              RideHistorySortOption.dateAsc => 'Orden: fecha ↑',
                              RideHistorySortOption.durationDesc =>
                                'Orden: duración ↓',
                              RideHistorySortOption.durationAsc =>
                                'Orden: duración ↑',
                              RideHistorySortOption.priceDesc =>
                                'Orden: precio ↓',
                              RideHistorySortOption.priceAsc =>
                                'Orden: precio ↑',
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rides.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.directions_car_outlined,
                          size: 64,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Este taxista todavia no tiene viajes registrados.',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No hay viajes que coincidan con los filtros.',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ...pageRides.map((ride) => _RideHistoryCard(ride: ride)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: safePage > 0
                              ? () {
                                  setState(() {
                                    _currentPage = safePage - 1;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Anterior'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Página ${safePage + 1} de $totalPages',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: safePage < totalPages - 1
                              ? () {
                                  setState(() {
                                    _currentPage = safePage + 1;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Siguiente'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  const _RideHistoryCard({required this.ride});

  final Map<String, dynamic> ride;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estado = normalizeRideState(ride['estado']);
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
                    estado.isEmpty ? 'sin estado' : estado,
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
                Text('Duración: ${_formatDuration(ride['duracion'])}'),
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

  static String _formatDuration(dynamic rawValue) {
    if (rawValue == null) return 'No disponible';
    final minutes = int.tryParse(rawValue.toString());
    if (minutes == null) return rawValue.toString();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '$hours h';
    }

    return '$hours h $remainingMinutes min';
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
