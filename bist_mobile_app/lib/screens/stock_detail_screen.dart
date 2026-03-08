import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import '../constants.dart';

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
  String? errorMessage;
  String selectedPeriod = '1mo';
  List<double> prices = [];

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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPriceCard(),
                  const SizedBox(height: 24),
                  _buildPeriodSelector(),
                  const SizedBox(height: 16),
                  _buildChart(),
                  const SizedBox(height: 24),
                  _buildStockInfo(),
                ],
              ),
            ),
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
              color: isSelected ? Colors.green : Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              period,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChart() {
    if (prices.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(child: Text('Veri yok')),
      );
    }

    final spots = prices.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final minY = prices.reduce(min) * 0.95;
    final maxY = prices.reduce(max) * 1.05;
    final isPositive = prices.last >= prices.first;

    return SizedBox(
      height: 250,
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
                    style: TextStyle(fontSize: 10),
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
                color: (isPositive ? Colors.green : Colors.red).withValues(
                  alpha: 0.1,
                ),
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
}
