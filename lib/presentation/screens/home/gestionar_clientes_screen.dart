import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/cliente_service.dart';
import 'package:gotaxi/presentation/screens/home/cliente_detail_screen.dart';

class GestionarClientesScreen extends StatefulWidget {
  const GestionarClientesScreen({super.key});

  @override
  State<GestionarClientesScreen> createState() =>
      _GestionarClientesScreenState();
}

class _GestionarClientesScreenState extends State<GestionarClientesScreen> {
  final _clienteService = ClienteService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _allClientes = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 100;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreClientes();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final clientes = await _clienteService.listClientes(
        limit: _limit,
        offset: 0,
      );

      if (!mounted) return;

      setState(() {
        _allClientes = clientes;
        _offset = clientes.length;
        _hasMore = clientes.length == _limit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar clientes: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreClientes() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final clientes = await _clienteService.listClientes(
        limit: _limit,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        _allClientes.addAll(clientes);
        _offset += clientes.length;
        _hasMore = clientes.length == _limit;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    _offset = 0;
    _hasMore = true;
    await _loadInitialData();
  }

  List<Map<String, dynamic>> get _filteredClientes {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _allClientes;

    return _allClientes.where((cliente) {
      final nombre = (cliente['nombre'] ?? '').toString().toLowerCase();
      final apellidos = (cliente['apellidos'] ?? '').toString().toLowerCase();
      final fullName = '$nombre $apellidos';
      return fullName.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredClientes = _filteredClientes;

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState(colorScheme)
          : _allClientes.isEmpty
          ? _buildEmptyState(colorScheme)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filteredClientes.isEmpty
                      ? _buildNoSearchResultsState(colorScheme)
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount:
                                filteredClientes.length +
                                (_hasMore && _searchController.text.isEmpty
                                    ? 1
                                    : 0),
                            itemBuilder: (context, index) {
                              if (index >= filteredClientes.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return _buildClienteCard(
                                filteredClientes[index],
                                colorScheme,
                              );
                            },
                          ),
                        ),
                ),
              ],
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
              onPressed: _refresh,
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
            Icon(Icons.people_outline, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No hay clientes registrados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
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
              'Prueba con otro nombre.',
              style: TextStyle(color: colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClienteCard(
    Map<String, dynamic> cliente,
    ColorScheme colorScheme,
  ) {
    final nombre = cliente['nombre'] as String? ?? '';
    final apellidos = cliente['apellidos'] as String? ?? '';
    final fullName = '$nombre $apellidos'.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClienteDetailScreen(cliente: cliente),
            ),
          );
        },
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
          fullName.isEmpty ? 'Sin nombre' : fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
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
