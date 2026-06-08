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

class _MarketScreenState extends State<MarketScreen> {
  bool isLoading = true;
  List<dynamic> stocks = [];
  List<dynamic> filteredStocks = [];
  List<String> favoriteSymbols = [];
  String? errorMessage;
  final TextEditingController searchController = TextEditingController();

  void _onSearchChanged(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      filteredStocks = stocks.where((s) {
        final symbol = (s['symbol'] ?? '').toString().toLowerCase();
        final name = (s['name'] ?? '').toString().toLowerCase();
        return symbol.contains(q) || name.contains(q);
      }).toList();
    });
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
            filteredStocks = data;
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
