import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

/// Uygulamanın açılış "Özet" ekranı — portföy hero kartı, endeks şeridi,
/// yükselenler/düşenler ve favoriler önizlemesi.
class DashboardScreen extends StatefulWidget {
  final String token;
  final String firstName;
  final VoidCallback? onSeeAllFavorites;

  const DashboardScreen({
    super.key,
    required this.token,
    this.firstName = '',
    this.onSeeAllFavorites,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  /// Dışarıdan (örn. sekme değişiminde) çağrılabilir yenileme.
  void reload() => _loadAll();

  bool loading = true;
  List<dynamic> stocks = [];
  List<dynamic> indices = [];
  List<dynamic> favorites = [];
  Map<String, dynamic> priceBySymbol = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    await Future.wait([_fetchStocks(), _fetchIndices(), _fetchFavorites()]);
    if (mounted) setState(() => loading = false);
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer ${widget.token}'};

  Future<void> _fetchStocks() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/market/bist30'), headers: _headers);
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        if (data is List) {
          stocks = data;
          priceBySymbol = {for (final s in data) s['symbol']: s};
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchIndices() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/market/indices'), headers: _headers);
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        if (data is List) indices = data;
      }
    } catch (_) {}
  }

  Future<void> _fetchFavorites() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/favorites/'), headers: _headers);
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        if (data is List) favorites = data;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildIndicesStrip(),
          const SizedBox(height: 24),
          _buildMovers(),
          const SizedBox(height: 24),
          _buildFavoritesPreview(),
        ],
      ),
    );
  }

  // ── Endeks / Kur Şeridi ──────────────────────────────────────────
  Widget _buildIndicesStrip() {
    if (indices.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: indices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final idx = indices[i];
          final ch = (idx['change_percent'] as num?)?.toDouble() ?? 0;
          final isPos = ch >= 0;
          final color = isPos ? AppColors.up : AppColors.down;
          final price = (idx['price'] as num?)?.toDouble() ?? 0;
          final suffix = idx['suffix'] ?? '';
          return Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(idx['label'] ?? '',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  '$suffix${price.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isPos ? '▲' : '▼'} ${ch.abs().toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Yükselenler / Düşenler (kayan ticker şeritleri) ──────────────
  Widget _buildMovers() {
    if (stocks.isEmpty) return const SizedBox.shrink();
    final sorted = [...stocks]
      ..sort((a, b) => ((b['change_percent'] ?? 0) as num).compareTo((a['change_percent'] ?? 0) as num));
    final gainers = sorted.where((s) => ((s['change_percent'] ?? 0) as num) >= 0).take(8).toList();
    final losers = sorted.where((s) => ((s['change_percent'] ?? 0) as num) < 0).toList().reversed.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('📈  Yükselenler', AppColors.up),
        const SizedBox(height: 10),
        _MovingStrip(items: gainers, token: widget.token),
        const SizedBox(height: 18),
        _sectionTitle('📉  Düşenler', AppColors.down),
        const SizedBox(height: 10),
        _MovingStrip(items: losers, token: widget.token, reverse: true),
      ],
    );
  }

  // ── Favoriler Önizleme ───────────────────────────────────────────
  Widget _buildFavoritesPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('⭐  Favorilerim', Colors.amber),
            if (widget.onSeeAllFavorites != null)
              TextButton(
                onPressed: widget.onSeeAllFavorites,
                child: const Text('Tümü'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (favorites.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.star_border, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Henüz favori eklemediniz.')),
                ],
              ),
            ),
          )
        else
          ...favorites.take(4).map((fav) {
            final sym = fav['symbol']?.toString() ?? '';
            final s = priceBySymbol[sym];
            final price = (s?['price'] as num?)?.toDouble();
            final ch = (s?['change_percent'] as num?)?.toDouble() ?? 0;
            final isPos = ch >= 0;
            final color = isPos ? AppColors.up : AppColors.down;
            final logo = s?['logo_url']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockDetailScreen(symbol: sym, token: widget.token),
                  ),
                ),
                leading: _miniLogo(logo, sym),
                title: Text(sym, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(s?['name']?.toString() ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(price != null ? '₺${price.toStringAsFixed(2)}' : '—',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('${isPos ? '+' : ''}${ch.toStringAsFixed(2)}%',
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _miniLogo(String logo, String sym) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: logo.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.network(logo, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _letter(sym)),
              ),
            )
          : _letter(sym),
    );
  }

  Widget _letter(String sym) => Center(
        child: Text(sym.isNotEmpty ? sym[0] : '?',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
      );

  Widget _sectionTitle(String text, Color accent) {
    return Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold));
  }
}

/// Sürekli kayan ticker şeridi (CNBC tarzı). Otomatik scroll, sonsuz döngü.
class _MovingStrip extends StatefulWidget {
  final List<dynamic> items;
  final String token;
  final bool reverse;

  const _MovingStrip({
    required this.items,
    required this.token,
    this.reverse = false,
  });

  @override
  State<_MovingStrip> createState() => _MovingStripState();
}

class _MovingStripState extends State<_MovingStrip> {
  final ScrollController _ctrl = ScrollController();
  Timer? _timer;
  static const double _speed = 0.6; // piksel / kare

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (widget.items.isEmpty) return;
    // ~60fps
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_ctrl.hasClients || !_ctrl.position.haveDimensions) return;
      final vp = _ctrl.position.viewportDimension;
      final setW = (_ctrl.position.maxScrollExtent + vp) / 2; // tek set genişliği
      if (setW <= 0) return;
      var next = _ctrl.offset + _speed;
      if (next >= setW) next -= setW; // sonsuz döngü için sıçramasız geri sar
      _ctrl.jumpTo(next.clamp(0, _ctrl.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sonsuz akış için liste iki kez tekrarlanır
    final doubled = [...widget.items, ...widget.items];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        reverse: widget.reverse,
        itemCount: doubled.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _chip(doubled[i]),
      ),
    );
  }

  Widget _chip(dynamic s) {
    final ch = (s['change_percent'] as num?)?.toDouble() ?? 0;
    final isPos = ch >= 0;
    final color = isPos ? AppColors.up : AppColors.down;
    final price = (s['price'] as num?)?.toDouble() ?? 0;
    final logo = s['logo_url']?.toString() ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockDetailScreen(symbol: s['symbol'], token: widget.token),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(logo, width: 22, height: 22, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 22, height: 22)),
              ),
              const SizedBox(width: 8),
            ],
            Text(s['symbol'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Text('₺${price.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            Icon(isPos ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: color, size: 18),
            Text('${ch.abs().toStringAsFixed(2)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
