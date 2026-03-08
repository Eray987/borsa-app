import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';
import '../main.dart';
import 'stock_detail_screen.dart';
import 'market_screen.dart';

class PortfolioScreen extends StatefulWidget {
  final String token;

  const PortfolioScreen({super.key, required this.token});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool isLoading = true;
  Map<String, dynamic>? summaryData;
  String? errorMessage;
  int _currentIndex = 0;
  List<dynamic> favorites = [];
  bool favoritesLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPortfolioSummary();
    fetchFavorites();
  }

  Future<void> fetchFavorites() async {
    setState(() {
      favoritesLoading = true;
    });

    try {
      final url = Uri.parse('$baseUrl/favorites/');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          favorites = data;
          favoritesLoading = false;
        });
      } else {
        setState(() {
          favoritesLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        favoritesLoading = false;
      });
    }
  }

  Future<void> removeFavorite(String symbol) async {
    try {
      final url = Uri.parse('$baseUrl/favorites/$symbol');

      final response = await http.delete(
        url,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        setState(() {
          favorites.removeWhere((f) => f['symbol'] == symbol);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$symbol favorilerden çıkarıldı')),
          );
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

  Future<void> fetchPortfolioSummary() async {
    setState(() {
      isLoading = true;
    });

    try {
      final url = Uri.parse('$baseUrl/portfolio/summary');

      final response = await http.get(
        url,
        headers: {
          if (widget.token.isNotEmpty)
            'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          summaryData = data;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage =
              'Portföy verisi alınamadı. Kod: ${response.statusCode}';
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

  String formatValue(dynamic value) {
    if (value == null) return '0.00';
    if (value is num) return value.toStringAsFixed(2);
    return value.toString();
  }

  List<dynamic> extractPositions(Map<String, dynamic> data) {
    if (data['positions'] is List) return data['positions'];
    if (data['holdings'] is List) return data['holdings'];
    if (data['portfolio'] is List) return data['portfolio'];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Portföyüm';
    if (_currentIndex == 1)
      title = 'BIST30 Piyasa';
    else if (_currentIndex == 2)
      title = 'İşlemler';
    else if (_currentIndex == 3)
      title = 'Profil';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [
          if (_currentIndex == 3)
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings),
              onSelected: (value) {
                if (value == 'logout') {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Çıkış Yap'),
                      content: const Text(
                        'Çıkış yapmak istediğinize emin misiniz?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('İptal'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const BistMobileApp(),
                              ),
                            );
                          },
                          child: const Text('Çıkış Yap'),
                        ),
                      ],
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            )
          else
            IconButton(
              onPressed: () {
                if (_currentIndex == 0) {
                  fetchFavorites();
                } else {
                  fetchPortfolioSummary();
                }
              },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.star_border),
            selectedIcon: Icon(Icons.star),
            label: 'Favoriler',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Piyasa',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'İşlem',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 0) {
      return _buildFavoritesBody();
    } else if (_currentIndex == 1) {
      return MarketScreen(token: widget.token);
    } else if (_currentIndex == 2) {
      return const Center(child: Text('İşlem ekranı yakında!'));
    } else if (_currentIndex == 3) {
      return _buildProfileBody();
    }
    return const SizedBox();
  }

  Widget _buildFavoritesBody() {
    if (favoritesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'Henüz favori hissen yok',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Piyasa sekmesinden hisse ekleyebilirsin',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await fetchFavorites();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: favorites.length,
        itemBuilder: (context, index) {
          final fav = favorites[index];
          final symbol = fav['symbol'] ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                symbol,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Eklendi: ${fav['added_at']?.toString().substring(0, 10) ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => removeFavorite(symbol),
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        StockDetailScreen(symbol: symbol, token: widget.token),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileBody() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            SizedBox(height: 24),
            Text(
              'Kullanıcı Profili',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortfolioBody() {
    final positions = summaryData != null
        ? extractPositions(summaryData!)
        : <dynamic>[];

    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMessage != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          )
        : summaryData == null
        ? const Center(child: Text('Portföy verisi bulunamadı.'))
        : RefreshIndicator(
            onRefresh: fetchPortfolioSummary,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoCard(
                  'Toplam Portföy Değeri',
                  formatValue(
                    summaryData!['total_value'] ??
                        summaryData!['portfolio_value'] ??
                        summaryData!['totalPortfolioValue'],
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  'Nakit',
                  formatValue(
                    summaryData!['cash'] ??
                        summaryData!['cash_balance'] ??
                        summaryData!['available_cash'],
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  'Kar / Zarar',
                  formatValue(
                    summaryData!['profit_loss'] ??
                        summaryData!['pnl'] ??
                        summaryData!['total_profit_loss'],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pozisyonlar',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (positions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Henüz pozisyon bulunmuyor.'),
                    ),
                  )
                else
                  ...positions.map((position) {
                    final symbol =
                        position['symbol'] ??
                        position['stock_code'] ??
                        position['ticker'] ??
                        'Bilinmiyor';

                    final quantity =
                        position['quantity'] ??
                        position['lot'] ??
                        position['units'] ??
                        0;

                    final avgPrice =
                        position['avg_price'] ??
                        position['average_price'] ??
                        position['buy_price'] ??
                        0;

                    final currentPrice =
                        position['current_price'] ??
                        position['price'] ??
                        position['last_price'] ??
                        0;

                    final pnl =
                        position['profit_loss'] ??
                        position['pnl'] ??
                        position['gain_loss'] ??
                        0;

                    return _buildPositionCard(
                      symbol: symbol.toString(),
                      quantity: quantity,
                      avgPrice: avgPrice,
                      currentPrice: currentPrice,
                      pnl: pnl,
                    );
                  }),
              ],
            ),
          );
  }

  Widget _buildPositionCard({
    required String symbol,
    required dynamic quantity,
    required dynamic avgPrice,
    required dynamic currentPrice,
    required dynamic pnl,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  StockDetailScreen(symbol: symbol, token: widget.token),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                symbol,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Adet: $quantity'),
              Text('Ortalama Fiyat: ${formatValue(avgPrice)}'),
              Text('Güncel Fiyat: ${formatValue(currentPrice)}'),
              Text('Kar / Zarar: ${formatValue(pnl)}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
