import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import '../constants.dart';
import '../theme.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  final String token;

  const StockDetailScreen({
    super.key,
    required this.symbol,
    required this.token,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  bool isLoading = true;
  Map<String, dynamic>? stockData;
  Map<String, dynamic>? analysisData;
  String? errorMessage;
  String? analysisError;
  String selectedPeriod = '1mo';
  List<double> prices = [];
  List<Map<String, dynamic>> candles = [];
  bool showCandlestick = true;
  List<dynamic> stockNews = [];
  bool newsLoading = true;
  bool analysisLoading = true;

  // Alarm
  List<dynamic> alarms = [];
  bool alarmsLoading = true;

  final Map<String, String> periodMap = {
    '1G': '1d',
    '1A': '1mo',
    '6A': '6mo',
    '1Y': '1y',
  };

  final List<String> periods = ['1G', '1A', '6A', '1Y'];

  @override
  void initState() {
    super.initState();
    fetchStockData();
    fetchStockNews();
    fetchAnalysis();
    fetchAlarms();
  }

  Future<void> fetchAlarms() async {
    setState(() => alarmsLoading = true);
    try {
      final url = Uri.parse('$baseUrl/alarms/${widget.symbol}');
      final r = await http.get(url, headers: {'Authorization': 'Bearer ${widget.token}'});
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() { alarms = jsonDecode(r.body); alarmsLoading = false; });
      } else {
        setState(() => alarmsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => alarmsLoading = false);
    }
  }

  Future<void> deleteAlarm(int alarmId) async {
    try {
      await http.delete(
        Uri.parse('$baseUrl/alarms/$alarmId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (!mounted) return;
      fetchAlarms();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  void _showAlarmDialog() {
    final lowerCtrl = TextEditingController();
    final upperCtrl = TextEditingController();
    final currentPrice = prices.isNotEmpty ? prices.last : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${widget.symbol} Fiyat Alarmı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Güncel fiyat: ₺${currentPrice.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: lowerCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Alt Sınır (₺)',
                hintText: 'Fiyat bu değerin altına düşerse',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.arrow_downward, color: Colors.red),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: upperCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Üst Sınır (₺)',
                hintText: 'Fiyat bu değerin üstüne çıkarsa',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.arrow_upward, color: Colors.green),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () async {
              final lower = double.tryParse(lowerCtrl.text.replaceAll(',', '.'));
              final upper = double.tryParse(upperCtrl.text.replaceAll(',', '.'));
              if (lower == null && upper == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('En az bir sınır giriniz.')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final r = await http.post(
                  Uri.parse('$baseUrl/alarms/'),
                  headers: {
                    'Authorization': 'Bearer ${widget.token}',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'symbol': widget.symbol,
                    if (lower != null) 'lower_bound': lower,
                    if (upper != null) 'upper_bound': upper,
                  }),
                );
                if (!mounted) return;
                if (r.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alarm oluşturuldu ✓')),
                  );
                  fetchAlarms();
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> fetchStockNews() async {
    setState(() => newsLoading = true);
    try {
      final url = Uri.parse('$baseUrl/news/stock/${widget.symbol}');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200) {
        setState(() {
          stockNews = jsonDecode(response.body);
          newsLoading = false;
        });
      } else {
        setState(() => newsLoading = false);
      }
    } catch (e) {
      setState(() => newsLoading = false);
    }
  }

  Future<void> fetchAnalysis() async {
    setState(() {
      analysisLoading = true;
      analysisError = null;
    });

    try {
      final url = Uri.parse('$baseUrl/analyze/${widget.symbol}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        setState(() {
          analysisData = jsonDecode(response.body);
          analysisLoading = false;
        });
      } else {
        setState(() {
          analysisError = 'Analiz alınamadı';
          analysisLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        analysisError = 'Analiz alınamadı: $e';
        analysisLoading = false;
      });
    }
  }

  Future<void> fetchStockData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final yfinancePeriod = periodMap[selectedPeriod] ?? '1mo';
      final url = Uri.parse(
        '$baseUrl/market/stock/${widget.symbol}?period=$yfinancePeriod',
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          stockData = data;
          isLoading = false;
          if (data['chart'] != null) {
            final chartData = data['chart'] as List;
            prices = chartData
                .map((e) => (e['close'] as num).toDouble())
                .toList();

            // Mum grafik için OHLC listesi
            final parsed = <Map<String, dynamic>>[];
            for (final e in chartData) {
              final o = (e['open']  as num?)?.toDouble() ?? 0;
              final h = (e['high']  as num?)?.toDouble() ?? 0;
              final l = (e['low']   as num?)?.toDouble() ?? 0;
              final c = (e['close'] as num?)?.toDouble() ?? 0;
              if (c <= 0 || o <= 0 || h <= 0 || l <= 0) continue;
              if (h < l) continue;
              parsed.add({'open': o, 'high': h, 'low': l, 'close': c, 'date': e['date']});
            }
            candles = parsed;
          }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol), centerTitle: true),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await fetchStockData();
                await fetchStockNews();
                await fetchAnalysis();
                await fetchAlarms();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPriceCard(),
                    const SizedBox(height: 24),
                    _buildPeriodSelector(),
                    const SizedBox(height: 12),
                    _buildChartTypeToggle(),
                    const SizedBox(height: 8),
                    _buildChart(),
                    const SizedBox(height: 24),
                    _buildStockInfo(),
                    const SizedBox(height: 24),
                    _buildAnalysisSection(),
                    const SizedBox(height: 24),
                    _buildAlarmSection(),
                    const SizedBox(height: 24),
                    _buildNewsSection(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Haberler & Fiyat Etkisi',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (newsLoading)
          const Center(child: CircularProgressIndicator())
        else if (stockNews.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.newspaper_outlined, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  const Text('Bu hisse için haber bulunamadı.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ...stockNews.map((article) {
            final title = article['title'] ?? '';
            final source = article['source'] ?? '';
            final publishedAt = (article['published_at'] ?? '').toString().substring(0, 10);
            final changePct = article['price_change_pct'] as double?;
            final priceClose = article['price_close'] as double?;

            final hasImpact = changePct != null;
            final changeValue = changePct ?? 0;
            final isPositive = hasImpact && changeValue >= 0;
            final impactColor = hasImpact
                ? (isPositive ? Colors.green : Colors.red)
                : Colors.grey;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (hasImpact) ...
                            [
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: impactColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: impactColor.withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      isPositive
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      color: impactColor,
                                      size: 14,
                                    ),
                                    Text(
                                      '${isPositive ? '+' : ''}${changeValue.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        color: impactColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (priceClose != null)
                                      Text(
                                        '₺${priceClose.toStringAsFixed(1)}',
                                        style: TextStyle(
                                          color: impactColor,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            source,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                          const SizedBox(width: 8),
                          Text('•',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey[400])),
                          const SizedBox(width: 8),
                          Text(
                            publishedAt,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                          if (hasImpact) ...
                            [
                              const Spacer(),
                              Text(
                                'O gün kapanış',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[400]),
                              ),
                            ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPriceCard() {
    final currentPrice = prices.isNotEmpty ? prices.last : 0.0;
    final previousPrice = prices.length > 1
        ? prices[prices.length - 2]
        : currentPrice;
    final change = prices.isNotEmpty ? currentPrice - previousPrice : 0.0;
    final changePercent = previousPrice != 0
        ? (change / previousPrice) * 100
        : 0.0;
    final isPositive = change >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.symbol,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '₺${currentPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isPositive ? Colors.green : Colors.red,
                  size: 20,
                ),
                Text(
                  '₺${change.abs().toStringAsFixed(2)} (${changePercent.abs().toStringAsFixed(2)}%)',
                  style: TextStyle(
                    fontSize: 16,
                    color: isPositive ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: periods.map((period) {
        final isSelected = period == selectedPeriod;
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedPeriod = period;
            });
            fetchStockData();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              period,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChartTypeToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _toggleBtn(Icons.candlestick_chart, 'Mum', showCandlestick, () {
          setState(() => showCandlestick = true);
        }),
        const SizedBox(width: 8),
        _toggleBtn(Icons.show_chart, 'Çizgi', !showCandlestick, () {
          setState(() => showCandlestick = false);
        }),
      ],
    );
  }

  Widget _toggleBtn(IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: active
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (prices.isEmpty) {
      return const SizedBox(
        height: 320,
        child: Center(child: Text('Veri yok')),
      );
    }

    if (showCandlestick && candles.isNotEmpty) {
      return SizedBox(
        height: 320,
        child: _CandlestickChart(candles: candles),
      );
    }

    // Çizgi grafik (fallback)
    final spots = prices.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final minY = prices.reduce(min) * 0.95;
    final maxY = prices.reduce(max) * 1.05;
    final isPositive = prices.last >= prices.first;

    return SizedBox(
      height: 320,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(color: Colors.grey[300], strokeWidth: 1);
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '₺${value.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (prices.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: isPositive ? Colors.green : Colors.red,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: (isPositive ? Colors.green : Colors.red).withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '₺${spot.y.toStringAsFixed(2)}',
                    const TextStyle(color: Colors.white),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStockInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hisse Bilgileri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Güncel Fiyat',
              '₺${stockData?['price']?.toStringAsFixed(2) ?? 'N/A'}',
            ),
            _buildInfoRow(
              'Değişim',
              '%${stockData?['change_percent']?.toStringAsFixed(2) ?? '0.00'}',
            ),
            _buildInfoRow('Grafik Periyodu', selectedPeriod),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisSection() {
    final recommendation = (analysisData?['recommendation'] ?? 'TUT').toString();
    final buyP  = (analysisData?['up_probability']   as num?)?.toDouble() ?? 0.0;
    final holdP = (analysisData?['hold_probability'] as num?)?.toDouble() ?? 0.0;
    final sellP = (analysisData?['sell_probability'] as num?)?.toDouble() ?? 0.0;
    final riskScore = (analysisData?['risk_score'] as num?)?.toDouble() ?? 0.0;
    final confidence = (analysisData?['confidence'] as num?)?.toDouble() ?? 0.0;
    final reasons = (analysisData?['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final currentPrice = (analysisData?['current_price'] as num?)?.toDouble();
    final changePercent = (analysisData?['change_percent'] as num?)?.toDouble();

    Color recommendationColor;
    if (recommendation == 'AL') {
      recommendationColor = AppColors.up;
    } else if (recommendation == 'SAT') {
      recommendationColor = AppColors.down;
    } else {
      recommendationColor = Colors.orange;
    }

    final riskText = riskScore < 0.35 ? 'Düşük' : riskScore < 0.7 ? 'Orta' : 'Yüksek';
    final riskColor = riskScore < 0.35 ? AppColors.up : riskScore < 0.7 ? Colors.orange : AppColors.down;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Analiz', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (analysisLoading)
          const Center(child: CircularProgressIndicator())
        else if (analysisError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  Expanded(child: Text(analysisError!, style: const TextStyle(color: Colors.grey))),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Tavsiye + fiyat satırı ──
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: recommendationColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: recommendationColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          recommendation,
                          style: TextStyle(color: recommendationColor, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const Spacer(),
                      if (currentPrice != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₺${currentPrice.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            if (changePercent != null)
                              Text(
                                '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: changePercent >= 0 ? AppColors.up : AppColors.down,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── AL / TUT / SAT olasılık çubukları ──
                  _buildProbBar('AL',  buyP,  AppColors.up),
                  const SizedBox(height: 6),
                  _buildProbBar('TUT', holdP, Colors.orange),
                  const SizedBox(height: 6),
                  _buildProbBar('SAT', sellP, AppColors.down),
                  const SizedBox(height: 16),

                  // ── Risk & Güven ──
                  Row(
                    children: [
                      Expanded(child: _buildMetricChip('Risk', riskText, riskColor)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildMetricChip('Güven', '%${(confidence * 100).toStringAsFixed(0)}', AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Sebepler ──
                  if (reasons.isEmpty)
                    const Text('Şu an açıklama üretilemedi.')
                  else
                    ...reasons.map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: TextStyle(color: Colors.grey[600])),
                            Expanded(
                              child: Text(
                                reason,
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Not: Bu sonuç yatırım tavsiyesi değildir.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAnalysisMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildProbBar(String label, double prob, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: prob.clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text('%${(prob * 100).toStringAsFixed(1)}',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAlarmSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Fiyat Alarmları',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _showAlarmDialog,
              icon: const Icon(Icons.add_alert, size: 18),
              label: const Text('Alarm Ekle'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (alarmsLoading)
          const Center(child: CircularProgressIndicator())
        else if (alarms.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.notifications_none, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  const Text('Henüz alarm kurulmamış.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ...alarms.map((alarm) {
            final lower = alarm['lower_bound'] as double?;
            final upper = alarm['upper_bound'] as double?;
            final isTriggered = alarm['is_triggered'] == true;
            final currentPrice = prices.isNotEmpty ? prices.last : 0.0;

            // Bant görseli için hesapla
            double? bandMin = lower ?? (upper != null ? upper * 0.9 : null);
            double? bandMax = upper ?? (lower != null ? lower * 1.1 : null);

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: isTriggered ? Colors.orange[50] : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isTriggered ? Icons.notifications_active : Icons.notifications,
                          color: isTriggered ? Colors.orange : Colors.grey[600],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (lower != null)
                                Row(children: [
                                  const Icon(Icons.arrow_downward, color: Colors.red, size: 14),
                                  const SizedBox(width: 4),
                                  Text('Alt sınır: ₺${lower.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 13)),
                                ]),
                              if (upper != null)
                                Row(children: [
                                  const Icon(Icons.arrow_upward, color: Colors.green, size: 14),
                                  const SizedBox(width: 4),
                                  Text('Üst sınır: ₺${upper.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 13)),
                                ]),
                            ],
                          ),
                        ),
                        if (isTriggered)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Tetiklendi',
                                style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => deleteAlarm(alarm['id']),
                        ),
                      ],
                    ),
                    // Bant görseli
                    if (bandMin != null && bandMax != null && currentPrice > 0) ...[
                      const SizedBox(height: 10),
                      _buildPriceBand(currentPrice, bandMin, bandMax, lower, upper),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ── Yardımcı Widget'lar ──────────────────────────────────────────────────

  Widget _buildPriceBand(double current, double bandMin, double bandMax, double? lower, double? upper) {
    final rangeMin = [current, bandMin].reduce(min) * 0.97;
    final rangeMax = [current, bandMax].reduce(max) * 1.03;
    final range = rangeMax - rangeMin;
    if (range <= 0) return const SizedBox();

    final currentPos = ((current - rangeMin) / range).clamp(0.0, 1.0);
    final lowerPos = lower != null ? ((lower - rangeMin) / range).clamp(0.0, 1.0) : null;
    final upperPos = upper != null ? ((upper - rangeMin) / range).clamp(0.0, 1.0) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fiyat bandı', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Arka plan bant
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Yeşil bölge (alt-üst arası)
                if (lowerPos != null && upperPos != null)
                  Positioned(
                    left: lowerPos * w,
                    width: (upperPos - lowerPos) * w,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                // Alt sınır çizgisi
                if (lowerPos != null)
                  Positioned(
                    left: lowerPos * w - 1,
                    child: Container(width: 2, height: 8, color: Colors.red),
                  ),
                // Üst sınır çizgisi
                if (upperPos != null)
                  Positioned(
                    left: upperPos * w - 1,
                    child: Container(width: 2, height: 8, color: Colors.green),
                  ),
                // Güncel fiyat göstergesi
                Positioned(
                  left: (currentPos * w - 6).clamp(0, w - 12),
                  top: -4,
                  child: Container(
                    width: 12,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (lower != null)
              Text('₺${lower.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10, color: Colors.red)),
            Text('₺${current.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
            if (upper != null)
              Text('₺${upper.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10, color: Colors.green)),
          ],
        ),
      ],
    );
  }
}

// ── Custom Candlestick Chart ─────────────────────────────────────────────────

class _CandlestickChart extends StatefulWidget {
  final List<Map<String, dynamic>> candles;
  const _CandlestickChart({required this.candles});

  @override
  State<_CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<_CandlestickChart> {
  // Ekranda gösterilecek maksimum mum sayısı — bu kadardan fazlası varsa kaydırma açılır
  static const int _maxVisible = 60;
  int _offset = 0;

  int get _visibleCount => widget.candles.length.clamp(1, _maxVisible);
  int get _maxOffset => (widget.candles.length - _visibleCount).clamp(0, widget.candles.length);
  bool get _canPan => widget.candles.length > _maxVisible;

  void _resetOffset() {
    _offset = _maxOffset; // en son mumları göster
  }

  @override
  void initState() {
    super.initState();
    _resetOffset();
  }

  @override
  void didUpdateWidget(_CandlestickChart old) {
    super.didUpdateWidget(old);
    if (old.candles.length != widget.candles.length) {
      _resetOffset();
    }
  }

  void _pan(DragUpdateDetails d) {
    if (!_canPan) return;
    final step = (d.delta.dx < 0) ? 1 : -1;
    setState(() {
      _offset = (_offset + step).clamp(0, _maxOffset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.candles.sublist(
      _offset,
      (_offset + _visibleCount).clamp(0, widget.candles.length),
    );

    return GestureDetector(
      onHorizontalDragUpdate: _pan,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _CandlestickPainter(
                candles: visible,
                gridColor: Theme.of(context).dividerColor,
                labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (_canPan)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '← kaydır →',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ),
        ],
      ),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<Map<String, dynamic>> candles;
  final Color gridColor;
  final Color labelColor;
  _CandlestickPainter({
    required this.candles,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final highs  = candles.map((c) => (c['high']  as num).toDouble()).toList();
    final lows   = candles.map((c) => (c['low']   as num).toDouble()).toList();
    final maxH   = highs.reduce(max);
    final minL   = lows.reduce(min);
    final range  = maxH - minL;
    if (range <= 0) return;

    final padT = 16.0, padB = 24.0, padLR = 8.0;
    final chartH = size.height - padT - padB;
    final chartW = size.width - padLR * 2;

    double toY(double v) => padT + (1 - (v - minL) / range) * chartH;

    final n         = candles.length;
    final candleW   = chartW / n;
    final bodyW     = (candleW * 0.6).clamp(2.0, 16.0);

    // Y ekseni etiketleri
    final textStyle  = TextStyle(fontSize: 9, color: labelColor);
    for (int i = 0; i <= 4; i++) {
      final v    = minL + range * i / 4;
      final y    = toY(v);
      // yatay grid çizgisi
      canvas.drawLine(
        Offset(padLR, y),
        Offset(size.width - padLR, y),
        Paint()..color = gridColor..strokeWidth = 0.5,
      );
      // etiket
      final tp = TextPainter(
        text: TextSpan(text: '₺${v.toStringAsFixed(0)}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padLR, y - 10));
    }

    // Mumlar
    for (int i = 0; i < n; i++) {
      final c = candles[i];
      final open  = (c['open']  as num).toDouble();
      final high  = (c['high']  as num).toDouble();
      final low   = (c['low']   as num).toDouble();
      final close = (c['close'] as num).toDouble();

      final isGreen = close >= open;
      final color   = isGreen ? Colors.green : Colors.red;
      final paint   = Paint()..color = color..strokeWidth = 1;

      final cx  = padLR + (i + 0.5) * candleW;
      final top = toY(isGreen ? close : open);
      final bot = toY(isGreen ? open  : close);

      // Fitil (wick)
      canvas.drawLine(Offset(cx, toY(high)), Offset(cx, toY(low)), paint);

      // Gövde (body)
      final bodyHeight = (bot - top).abs().clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, bodyHeight),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_CandlestickPainter old) => old.candles != candles;
}
