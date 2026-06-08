import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../theme.dart';
import 'stock_detail_screen.dart';

class MarketScreen extends StatefulWidget {
  final String token;

  const MarketScreen({super.key, required this.token});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

enum _SortMode { none, priceAsc, priceDesc, changeAsc, changeDesc, nameAsc }

class _MarketScreenState extends State<MarketScreen> {
  bool isLoading = true;
  List<dynamic> stocks = [];
  List<dynamic> filteredStocks = [];
  List<String> favoriteSymbols = [];
  String? errorMessage;
  final TextEditingController searchController = TextEditingController();
  _SortMode _sortMode = _SortMode.none;

  void _onSearchChanged(String query) {
    final q = query.toLowerCase().trim();
    final filtered = stocks.where((s) {
      final symbol = (s['symbol'] ?? '').toString().toLowerCase();
      final name = (s['name'] ?? '').toString().toLowerCase();
      return symbol.contains(q) || name.contains(q);
    }).toList();
    setState(() {
      filteredStocks = _applySortTo(filtered);
    });
  }

  List<dynamic> _applySortTo(List<dynamic> list) {
    final sorted = [...list];
    switch (_sortMode) {
      case _SortMode.priceAsc:
        sorted.sort((a, b) => ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0));
        break;
      case _SortMode.priceDesc:
        sorted.sort((a, b) => ((b['price'] as num?) ?? 0).compareTo((a['price'] as num?) ?? 0));
        break;
      case _SortMode.changeAsc:
        sorted.sort((a, b) => ((a['change_percent'] as num?) ?? 0).compareTo((b['change_percent'] as num?) ?? 0));
        break;
      case _SortMode.changeDesc:
        sorted.sort((a, b) => ((b['change_percent'] as num?) ?? 0).compareTo((a['change_percent'] as num?) ?? 0));
        break;
      case _SortMode.nameAsc:
        sorted.sort((a, b) => (a['symbol'] ?? '').toString().compareTo((b['symbol'] ?? '').toString()));
        break;
      case _SortMode.none:
        break;
    }
    return sorted;
  }

  void _applySort(_SortMode mode) {
    setState(() {
      _sortMode = mode;
      filteredStocks = _applySortTo(filteredStocks);
    });
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Sıralama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _sortTile(ctx, _SortMode.none,       Icons.sort,              'Varsayılan'),
              _sortTile(ctx, _SortMode.changeDesc,  Icons.trending_up,       'En Çok Yükselenler'),
              _sortTile(ctx, _SortMode.changeAsc,   Icons.trending_down,     'En Çok Düşenler'),
              _sortTile(ctx, _SortMode.priceDesc,   Icons.arrow_upward,      'Fiyat: Yüksekten Düşüğe'),
              _sortTile(ctx, _SortMode.priceAsc,    Icons.arrow_downward,    'Fiyat: Düşükten Yükseğe'),
              _sortTile(ctx, _SortMode.nameAsc,     Icons.sort_by_alpha,     'Alfabetik (A→Z)'),
            ],
          ),
        );
      },
    );
  }

  Widget _sortTile(BuildContext ctx, _SortMode mode, IconData icon, String label) {
    final selected = _sortMode == mode;
    return ListTile(
      leading: Icon(icon, color: selected ? AppColors.primary : null),
      title: Text(label, style: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? AppColors.primary : null,
      )),
      trailing: selected ? const Icon(Icons.check, color: AppColors.primary) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
      onTap: () {
        Navigator.pop(ctx);
        _applySort(mode);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    fetchMarketData();
    fetchFavorites();
  }

  Future<void> fetchMarketData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final url = Uri.parse('$baseUrl/market/bist30');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          setState(() {
            stocks = data;
            filteredStocks = _applySortTo(List.from(data));
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'Piyasa verisi formati beklenenden farkli.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Veri alinamadi';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Bir hata olustu: $e';
        isLoading = false;
      });
    }
  }

  Future<void> fetchFavorites() async {
    try {
      final url = Uri.parse('$baseUrl/favorites/');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          setState(() {
            favoriteSymbols =
                data.map<String>((e) => e['symbol'].toString()).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Favorites error: $e');
    }
  }

  Future<void> toggleFavorite(String symbol) async {
    try {
      final isFavorite = favoriteSymbols.contains(symbol);

      if (isFavorite) {
        final url = Uri.parse('$baseUrl/favorites/$symbol');
        await http.delete(
          url,
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (!mounted) return;
        setState(() {
          favoriteSymbols.remove(symbol);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$symbol favorilerden cikarildi')),
        );
      } else {
        final url = Uri.parse('$baseUrl/favorites/$symbol');
        await http.post(
          url,
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (!mounted) return;
        setState(() {
          favoriteSymbols.add(symbol);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$symbol favorilere eklendi')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return RefreshIndicator(
        onRefresh: () async {
          await fetchMarketData();
          await fetchFavorites();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 220),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await fetchMarketData();
        await fetchFavorites();
      },
      child: stocks.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 220),
                Center(
                  child: Text(
                    'Piyasa verisi su an alinamadi.\nLutfen yenileyin.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Hisse veya şirket ara...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: _sortMode != _SortMode.none
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.sort,
                            color: _sortMode != _SortMode.none ? AppColors.primary : null,
                          ),
                          tooltip: 'Sırala',
                          onPressed: _showSortSheet,
                        ),
                      ),
                    ],
                  ),
                ),
                if (filteredStocks.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('Sonuç bulunamadı.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(8),
                      itemCount: filteredStocks.length,
                      itemBuilder: (context, index) {
                        final stock = filteredStocks[index];
                        return _buildStockCard(stock);
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildStockCard(dynamic stock) {
    final symbol = stock['symbol'] ?? '';
    final name = stock['name'] ?? '';
    final price = (stock['price'] ?? 0.0) as num;
    final change = (stock['change_percent'] ?? 0.0) as num;
    final isPositive = change >= 0;
    final isFavorite = favoriteSymbols.contains(symbol);
    final logoUrl = stock['logo_url'] ?? '';
    final changeColor = isPositive ? AppColors.up : AppColors.down;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StockDetailScreen(
                symbol: symbol,
                token: widget.token,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              _buildLogo(logoUrl, symbol),
              const SizedBox(width: 14),
              // Sembol + isim
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Fiyat + değişim rozeti
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₺${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          color: changeColor,
                          size: 16,
                        ),
                        Text(
                          '${change.abs().toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: changeColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? Colors.amber : Colors.grey,
                  size: 22,
                ),
                onPressed: () => toggleFavorite(symbol),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(String logoUrl, String symbol) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: logoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Image.network(
                  logoUrl,
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _fallbackAvatar(symbol),
                ),
              ),
            )
          : _fallbackAvatar(symbol),
    );
  }

  Widget _fallbackAvatar(String symbol) {
    return Center(
      child: Text(
        symbol.isNotEmpty ? symbol[0] : '?',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: AppColors.primary,
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
