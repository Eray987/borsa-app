import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';

const _bist30Symbols = [
  'THYAO','ASELS','GARAN','AKBNK','SISE','EREGL','KCHOL','SASA','HEKTS','PETKM',
  'FROTO','ISCTR','AYGAZ','MGROS','SOKM','TCELL','TUPRS','YKBNK','TTKOM','ULKER',
  'BIMAS','HALKB','VAKBN','ENKAI','ANSGR','SAHOL','KOZAL','PGSUS','TOASO','ARCLK',
];

class TransactionsScreen extends StatefulWidget {
  final String token;
  const TransactionsScreen({super.key, required this.token});

  @override
  State<TransactionsScreen> createState() => TransactionsScreenState();
}

class TransactionsScreenState extends State<TransactionsScreen> {
  bool isLoading = true;
  List<dynamic> transactions = [];
  // sembol → güncel fiyat cache
  Map<String, double> livePrices = {};
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { isLoading = true; errorMessage = null; });
    await fetchTransactions();
    await fetchLivePrices();
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> fetchTransactions() async {
    try {
      final r = await http.get(
        Uri.parse('$baseUrl/portfolio/transactions'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (!mounted) return;
      if (r.statusCode == 200) {
        transactions = jsonDecode(r.body);
      } else {
        errorMessage = 'İşlemler alınamadı.';
      }
    } catch (e) {
      errorMessage = 'Bağlantı hatası: $e';
    }
  }

  Future<void> fetchLivePrices() async {
    // İşlemlerdeki benzersiz sembolleri topla
    final symbols = transactions.map((t) => t['symbol'].toString()).toSet();
    for (final symbol in symbols) {
      try {
        final r = await http.get(
          Uri.parse('$baseUrl/market/stock/$symbol?period=1d'),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        );
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          livePrices[symbol] = (data['price'] as num).toDouble();
        }
      } catch (_) {}
    }
  }

  void showAddDialog() {
    String selectedSymbol = _bist30Symbols.first;
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String side = 'BUY';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('İşlem Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedSymbol,
                  decoration: const InputDecoration(
                    labelText: 'Hisse Sembolü',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  items: _bist30Symbols.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  )).toList(),
                  onChanged: (v) => setLocal(() => selectedSymbol = v!),
                ),
                const SizedBox(height: 12),
                // AL / SAT toggle
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setLocal(() => side = 'BUY'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: side == 'BUY' ? Colors.green : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'AL',
                              style: TextStyle(
                                color: side == 'BUY' ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setLocal(() => side = 'SELL'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: side == 'SELL' ? Colors.red : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'SAT',
                              style: TextStyle(
                                color: side == 'SELL' ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Adet (lot)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Fiyat (₺)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final symbol = selectedSymbol;
                final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
                final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));

                if (qty == null || qty <= 0 || price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen tüm alanları doğru doldurun.')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                try {
                  final r = await http.post(
                    Uri.parse('$baseUrl/portfolio/transactions'),
                    headers: {
                      'Authorization': 'Bearer ${widget.token}',
                      'Content-Type': 'application/json',
                    },
                    body: jsonEncode({
                      'symbol': symbol,
                      'side': side,
                      'qty': qty,
                      'price': price,
                    }),
                  );
                  if (!mounted) return;
                  if (r.statusCode == 200) {
                    // Alım işlemiyse hisseyi otomatik favorilere ekle
                    if (side == 'BUY') {
                      try {
                        await http.post(
                          Uri.parse('$baseUrl/favorites/$symbol'),
                          headers: {'Authorization': 'Bearer ${widget.token}'},
                        );
                      } catch (_) {}
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(side == 'BUY'
                          ? 'İşlem kaydedildi, $symbol favorilere eklendi ✓'
                          : 'İşlem kaydedildi ✓')),
                    );
                    _loadAll();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: ${r.body}')),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İşlemi Sil'),
        content: const Text('Bu işlem notunu silmek istiyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await http.delete(
        Uri.parse('$baseUrl/portfolio/transactions/$id'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (!mounted) return;
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    if (errorMessage != null) {
      return Center(
        child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
      );
    }

    // Özet hesapla
    double totalInvested = 0;
    double totalCurrentValue = 0;
    // sembol → {qty, avgCost}
    final Map<String, Map<String, double>> positions = {};
    for (final tx in transactions) {
      final sym = tx['symbol'].toString();
      final qty = (tx['qty'] as num).toDouble();
      final price = (tx['price'] as num).toDouble();
      final side = tx['side'].toString();

      positions.putIfAbsent(sym, () => {'qty': 0, 'totalCost': 0});
      if (side == 'BUY') {
        positions[sym]!['qty'] = positions[sym]!['qty']! + qty;
        positions[sym]!['totalCost'] = positions[sym]!['totalCost']! + qty * price;
      } else {
        positions[sym]!['qty'] = (positions[sym]!['qty']! - qty).clamp(0, double.infinity);
        positions[sym]!['totalCost'] = positions[sym]!['totalCost']! - qty * price;
        if (positions[sym]!['totalCost']! < 0) positions[sym]!['totalCost'] = 0;
      }
    }

    for (final entry in positions.entries) {
      final sym = entry.key;
      final qty = entry.value['qty']!;
      final totalCost = entry.value['totalCost']!;
      final livePrice = livePrices[sym];
      totalInvested += totalCost;
      if (livePrice != null) totalCurrentValue += qty * livePrice;
    }
    final totalPnL = totalCurrentValue - totalInvested;
    final totalPnLPct = totalInvested > 0 ? (totalPnL / totalInvested) * 100 : 0.0;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Özet kart
          if (transactions.isNotEmpty) ...[
            _buildSummaryCard(totalInvested, totalCurrentValue, totalPnL, totalPnLPct),
            const SizedBox(height: 16),
            // Pozisyon özetleri
            _buildPositionSummary(positions),
            const SizedBox(height: 16),
            const Text('İşlem Geçmişi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
          ],
          if (transactions.isEmpty)
            const SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Henüz işlem notu yok',
                        style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('+ butonuna basarak ekle',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            ...transactions.map((tx) => _buildTransactionCard(tx)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(double invested, double current, double pnl, double pct) {
    final isPositive = pnl >= 0;
    return Card(
      color: isPositive ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Genel Özet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryItem('Toplam Maliyet', '₺${invested.toStringAsFixed(2)}', Colors.black87),
                _summaryItem('Güncel Değer', '₺${current.toStringAsFixed(2)}', Colors.black87),
                _summaryItem(
                  'Kar / Zarar',
                  '${isPositive ? '+' : ''}₺${pnl.toStringAsFixed(2)}\n(${isPositive ? '+' : ''}${pct.toStringAsFixed(2)}%)',
                  isPositive ? Colors.green[700]! : Colors.red[700]!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildPositionSummary(Map<String, Map<String, double>> positions) {
    final activePositions = positions.entries.where((e) => e.value['qty']! > 0).toList();
    if (activePositions.isEmpty) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pozisyonlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...activePositions.map((entry) {
              final sym = entry.key;
              final qty = entry.value['qty']!;
              final totalCost = entry.value['totalCost']!;
              final avgCost = qty > 0 ? totalCost / qty : 0.0;
              final livePrice = livePrices[sym];
              final pnlPerLot = livePrice != null ? livePrice - avgCost : null;
              final totalPnL = pnlPerLot != null ? pnlPerLot * qty : null;
              final pnlPct = avgCost > 0 && pnlPerLot != null ? (pnlPerLot / avgCost) * 100 : null;
              final isPos = pnlPerLot != null && pnlPerLot >= 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('${qty.toStringAsFixed(0)} lot  ×  ₺${avgCost.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (livePrice != null)
                          Text('₺${livePrice.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold))
                        else
                          Text('Fiyat alınamadı',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        if (totalPnL != null)
                          Text(
                            '${isPos ? '+' : ''}₺${totalPnL.toStringAsFixed(2)} (${isPos ? '+' : ''}${pnlPct!.toStringAsFixed(2)}%)',
                            style: TextStyle(
                              color: isPos ? Colors.green[700] : Colors.red[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final sym = tx['symbol'].toString();
    final side = tx['side'].toString();
    final qty = (tx['qty'] as num).toDouble();
    final price = (tx['price'] as num).toDouble();
    final date = tx['created_at']?.toString().substring(0, 10) ?? '';
    final total = qty * price;
    final isBuy = side == 'BUY';
    final livePrice = livePrices[sym];
    final pnlPerLot = isBuy && livePrice != null ? livePrice - price : null;
    final totalPnL = pnlPerLot != null ? pnlPerLot * qty : null;
    final isPos = totalPnL != null && totalPnL >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Sol renk bandı
            Container(
              width: 4,
              height: 60,
              decoration: BoxDecoration(
                color: isBuy ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(sym,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isBuy ? Colors.green[100] : Colors.red[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isBuy ? 'AL' : 'SAT',
                          style: TextStyle(
                            color: isBuy ? Colors.green[800] : Colors.red[800],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${qty.toStringAsFixed(0)} lot  ×  ₺${price.toStringAsFixed(2)}  =  ₺${total.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  if (isBuy && totalPnL != null)
                    Text(
                      'Güncel: ₺${livePrice!.toStringAsFixed(2)}   ${isPos ? '+' : ''}₺${totalPnL.toStringAsFixed(2)} (${isPos ? '+' : ''}${((pnlPerLot! / price) * 100).toStringAsFixed(2)}%)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isPos ? Colors.green[700] : Colors.red[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(date, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _deleteTransaction(tx['id']),
                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
