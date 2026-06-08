import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';

class SignalsScreen extends StatefulWidget {
  final String token;
  const SignalsScreen({super.key, required this.token});

  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  List<dynamic> _signals = [];
  bool _loading = true;
  String? _error;
  String _filter = 'TUMU'; // TUMU, BUY, HOLD, SELL

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/signals/all'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 120));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _signals = data['signals'] ?? [];
          _loading = false;
        });
      } else {
        setState(() { _error = 'Sunucu hatasi: ${res.statusCode}'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Baglanti hatasi: $e'; _loading = false; });
    }
  }

  List<dynamic> get _filtered {
    if (_filter == 'TUMU') return _signals;
    final map = {'BUY': 'AL', 'HOLD': 'TUT', 'SELL': 'SAT'};
    return _signals.where((s) => s['recommendation'] == map[_filter]).toList();
  }

  Color _signalColor(String rec) {
    if (rec == 'AL') return const Color(0xFF22C55E);
    if (rec == 'SAT') return const Color(0xFFEF4444);
    return const Color(0xFFF59E0B);
  }

  Color _changeColor(double pct) => pct >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

  Widget _probBar(double value, Color color) {
    return SizedBox(
      width: 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: color.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BIST30 Sinyaller'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtre butonlari
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['TUMU', 'BUY', 'HOLD', 'SELL'].map((f) {
                final selected = _filter == f;
                final colors = {
                  'BUY':  const Color(0xFF22C55E),
                  'HOLD': const Color(0xFFF59E0B),
                  'SELL': const Color(0xFFEF4444),
                  'TUMU': Colors.blueGrey,
                };
                final labels = {'BUY': 'AL', 'HOLD': 'TUT', 'SELL': 'SAT', 'TUMU': 'Tumu'};
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(labels[f]!),
                    selected: selected,
                    selectedColor: colors[f]!.withOpacity(0.85),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : null,
                      fontWeight: selected ? FontWeight.bold : null,
                    ),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),

          // Icerik
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _load, child: const Text('Tekrar Dene')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final s    = _filtered[i];
                            final rec  = s['recommendation'] ?? '?';
                            final bp   = (s['buy_probability'] ?? 0.0) as double;
                            final sp   = (s['sell_probability'] ?? 0.0) as double;
                            final hp   = (s['hold_probability'] ?? 0.0) as double;
                            final price = (s['current_price'] ?? 0.0) as double;
                            final chg  = (s['change_percent'] ?? 0.0) as double;
                            final sym  = (s['symbol'] ?? '').replaceAll('.IS', '');
                            final conf = ((s['confidence'] ?? 0.0) as double) * 100;
                            final rank = i + 1;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: rank <= 3
                                    ? BorderSide(color: _signalColor(rec).withOpacity(0.6), width: 1.5)
                                    : BorderSide.none,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Sira numarasi
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '$rank',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: rank <= 3 ? _signalColor(rec) : Colors.grey,
                                        ),
                                      ),
                                    ),
                                    // Sembol
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(sym,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          Text('${price.toStringAsFixed(2)} TL',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        ],
                                      ),
                                    ),
                                    // Degisim
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
                                        style: TextStyle(
                                          color: _changeColor(chg),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    // Sinyal + bar
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _signalColor(rec).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(rec,
                                              style: TextStyle(
                                                color: _signalColor(rec),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              )),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text('AL ', style: TextStyle(fontSize: 10, color: Colors.green[400])),
                                              _probBar(bp, const Color(0xFF22C55E)),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text('SAT ', style: TextStyle(fontSize: 10, color: Colors.red[400])),
                                              _probBar(sp, const Color(0xFFEF4444)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text('Guven: %${conf.toStringAsFixed(0)}',
                                            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}