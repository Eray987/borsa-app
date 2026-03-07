import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  List<String> favoriteSymbols = [];
  String? errorMessage;

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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          stocks = data;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Veri alınamadı';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Bir hata oluştu: $e';
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          favoriteSymbols = data
              .map<String>((e) => e['symbol'].toString())
              .toList();
        });
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
        setState(() {
          favoriteSymbols.remove(symbol);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$symbol favorilerden çıkarıldı')),
          );
        }
      } else {
        final url = Uri.parse('$baseUrl/favorites/$symbol');
        await http.post(
          url,
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        setState(() {
          favoriteSymbols.add(symbol);
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$symbol favorilere eklendi')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BIST30 Piyasa'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              fetchMarketData();
              fetchFavorites();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await fetchMarketData();
                await fetchFavorites();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: stocks.length,
                itemBuilder: (context, index) {
                  final stock = stocks[index];
                  final symbol = stock['symbol'] ?? '';
                  final price = stock['price'] ?? 0.0;
                  final change = stock['change_percent'] ?? 0.0;
                  final isPositive = change >= 0;
                  final isFavorite = favoriteSymbols.contains(symbol);

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
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
                                '₺${price.toStringAsFixed(2)}',
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
    );
  }
}
