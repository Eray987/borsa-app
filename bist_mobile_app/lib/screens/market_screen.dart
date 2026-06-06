import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
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
                      fillColor: Colors.grey[200],
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
                final symbol = stock['symbol'] ?? '';
                final price = (stock['price'] ?? 0.0) as num;
                final change = (stock['change_percent'] ?? 0.0) as num;
                final isPositive = change >= 0;
                final isFavorite = favoriteSymbols.contains(symbol);
                final logoUrl = stock['logo_url'] ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: ListTile(
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
                    leading: _buildLogo(logoUrl, symbol),
                    title: Text(
                      symbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      stock['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'TL${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: isPositive ? Colors.green : Colors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                          onPressed: () => toggleFavorite(symbol),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
                  ),
              ],
            ),
    );
  }

  Widget _buildLogo(String logoUrl, String symbol) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: logoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                logoUrl,
                width: 42,
                height: 42,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _fallbackAvatar(symbol),
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
          color: Colors.green,
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
