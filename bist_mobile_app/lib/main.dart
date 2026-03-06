import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const BistMobileApp());
}

const String baseUrl = 'http://10.0.2.2:8000';

class BistMobileApp extends StatelessWidget {
  const BistMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BIST Mobile App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController =
      TextEditingController(text: 'user@example.com');
  final TextEditingController passwordController =
      TextEditingController(text: '123456');

  bool isLoading = false;

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen e-posta ve şifre girin.'),
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final url = Uri.parse('$baseUrl/auth/login');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'username': email,
          'password': password,
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'] ?? '';

        debugPrint('TOKEN: $token');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giriş başarılı'),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PortfolioScreen(token: token),
          ),
        );
      } else {
        debugPrint('Login failed: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giriş başarısız. Bilgileri kontrol et.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Login error: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giriş Yap'),
        centerTitle: true,
      ),
      body: Center(
        child: SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.show_chart, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'BIST Mobile App',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : login,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Giriş Yap'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {},
                  child: const Text('Hesabın yok mu? Kayıt ol'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    fetchPortfolioSummary();
  }

  Future<void> fetchPortfolioSummary() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
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

      debugPrint('Portfolio status: ${response.statusCode}');
      debugPrint('Portfolio body: ${response.body}');

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
    final positions =
        summaryData != null ? extractPositions(summaryData!) : <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portföyüm'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: fetchPortfolioSummary,
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
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
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
                              final symbol = position['symbol'] ??
                                  position['stock_code'] ??
                                  position['ticker'] ??
                                  'Bilinmiyor';

                              final quantity = position['quantity'] ??
                                  position['lot'] ??
                                  position['units'] ??
                                  0;

                              final avgPrice = position['avg_price'] ??
                                  position['average_price'] ??
                                  position['buy_price'] ??
                                  0;

                              final currentPrice = position['current_price'] ??
                                  position['price'] ??
                                  position['last_price'] ??
                                  0;

                              final pnl = position['profit_loss'] ??
                                  position['pnl'] ??
                                  position['gain_loss'] ??
                                  0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        symbol.toString(),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Adet: $quantity'),
                                      Text(
                                        'Ortalama Fiyat: ${formatValue(avgPrice)}',
                                      ),
                                      Text(
                                        'Güncel Fiyat: ${formatValue(currentPrice)}',
                                      ),
                                      Text(
                                        'Kar / Zarar: ${formatValue(pnl)}',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                        ],
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
            Text(
              title,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}