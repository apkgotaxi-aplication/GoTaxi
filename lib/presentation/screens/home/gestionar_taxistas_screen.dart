import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/taxista_service.dart';

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
  String? _deletingId;
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
        if (mounted) {
          setState(() {
            _error = 'No tienes permisos de administrador';
            _loading = false;
          });
        }
        return;
      }

      final taxistas = await _taxistaService.listTaxistas();
      if (mounted) {
        setState(() {
          _taxistas = taxistas;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar taxistas: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteTaxista(
    String taxistaId,
    String nombre,
    String apellidos,
  ) async {
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

    setState(() => _deletingId = taxistaId);

    try {
      await _taxistaService.deleteTaxista(taxistaId: taxistaId);
      if (mounted) {
        setState(() {
          _taxistas.removeWhere((t) => t['id'] == taxistaId);
          _deletingId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$nombre $apellidos eliminado correctamente'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deletingId = null);
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
    final vehiculo = taxista['vehiculos'] as Map<String, dynamic>;
    final nombre = usuario['nombre'] as String? ?? '';
    final apellidos = usuario['apellidos'] as String? ?? '';
    final email = usuario['email'] as String? ?? '';
    final telefono = usuario['telefono'] as String? ?? '';
    final dni = usuario['dni'] as String? ?? '';
    final isAdmin = taxista['is_admin'] == true;
    final estado = taxista['estado'] as String? ?? 'no disponible';
    final matricula = vehiculo['matricula'] as String? ?? '';
    final marca = vehiculo['marca'] as String? ?? '';
    final modelo = vehiculo['modelo'] as String? ?? '';
    final color = vehiculo['color'] as String? ?? '';
    final licencia = vehiculo['licencia_taxi'] as String? ?? '';
    final taxistaId = taxista['id'] as String;
    final isDeleting = _deletingId == taxistaId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    '${nombre.isNotEmpty ? nombre[0] : ''}${apellidos.isNotEmpty ? apellidos[0] : ''}',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$nombre $apellidos',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dni,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildEstadoChip(estado, colorScheme),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildInfoRow(Icons.email_outlined, email),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.phone_outlined, telefono),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    Icons.directions_car,
                    '$marca $modelo - $color',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    Icons.confirmation_number,
                    'Matrícula: $matricula',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.card_travel, 'Licencia: $licencia'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isDeleting
                    ? null
                    : () => _deleteTaxista(taxistaId, nombre, apellidos),
                icon: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(
                  isDeleting ? 'Eliminando...' : 'Eliminar Taxista',
                  style: const TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoChip(String estado, ColorScheme colorScheme) {
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
