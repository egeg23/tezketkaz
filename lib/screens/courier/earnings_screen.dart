import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

// Моковые данные заработка
class _EarningsData {
  final String day;
  final double amount;
  final int orders;
  _EarningsData(this.day, this.amount, this.orders);
}

final _weekData = [
  _EarningsData('Du', 45000, 4),
  _EarningsData('Se', 62000, 5),
  _EarningsData('Ch', 38000, 3),
  _EarningsData('Pa', 71000, 6),
  _EarningsData('Ju', 89000, 7),
  _EarningsData('Sh', 55000, 4),
  _EarningsData('Ya', 67500, 5),  // сегодня
];

final _history = [
  _HistoryItem(
    id: '#co_041', shop: 'Korzinka — Yunusobod',
    address: 'Yunusobod, 25-uy', reward: 12000,
    time: '14:32', date: 'Bugun', km: 1.8,
  ),
  _HistoryItem(
    id: '#co_040', shop: 'Makro — Mirzo Ulug\'bek',
    address: 'Sebzor, 7-uy', reward: 18000,
    time: '12:15', date: 'Bugun', km: 3.1,
  ),
  _HistoryItem(
    id: '#co_039', shop: 'Korzinka — Chilonzor',
    address: 'Chilonzor, 9-kvartal', reward: 14000,
    time: '10:44', date: 'Bugun', km: 2.3,
  ),
  _HistoryItem(
    id: '#co_038', shop: 'Smart — Yakkasaroy',
    address: 'Yakkasaroy, 1-mavze', reward: 11000,
    time: '09:20', date: 'Bugun', km: 1.5,
  ),
  _HistoryItem(
    id: '#co_037', shop: 'Korzinka — Shayxontohur',
    address: 'Olmazor, 34-uy', reward: 22000,
    time: '18:55', date: 'Kecha', km: 4.2,
  ),
  _HistoryItem(
    id: '#co_036', shop: 'Makro — Hamza',
    address: 'Hamza, 12-mavze', reward: 16000,
    time: '16:30', date: 'Kecha', km: 2.7,
  ),
];

class _HistoryItem {
  final String id, shop, address, time, date;
  final double reward, km;
  _HistoryItem({
    required this.id, required this.shop, required this.address,
    required this.reward, required this.time, required this.date,
    required this.km,
  });
}

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _selectedDay = 6; // Сегодня — последний

  final _balance = 234500.0;      // Доступно к выводу
  final _pending = 67500.0;       // В обработке
  final _monthTotal = 1250000.0; // Месяц

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
    '${(v / 1000).toStringAsFixed(0)} ming';

  String _fmtFull(double v) =>
    '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) {
    final maxAmount = _weekData.map((d) => d.amount).reduce((a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Daromad'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Balance card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFE55A2B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.courier.withValues(alpha: 0.3),
                  blurRadius: 20, offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text('Hisobingizda',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _fmtFull(_balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30, fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _BalanceStat(
                        label: 'Kutilmoqda',
                        value: _fmtFull(_pending),
                        icon: '⏳',
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    Expanded(
                      child: _BalanceStat(
                        label: 'Bu oy',
                        value: '${(_monthTotal / 1000).toStringAsFixed(0)}k so\'m',
                        icon: '📅',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Withdraw button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showWithdrawSheet(context),
                    icon: const Icon(Icons.account_balance_wallet_outlined,
                        size: 18),
                    label: const Text('Pul yechib olish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.courier,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Weekly chart
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Haftalik statistika',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      '${_fmt(_weekData.fold(0.0, (s, d) => s + d.amount))} so\'m',
                      style: const TextStyle(
                        color: AppColors.courier,
                        fontWeight: FontWeight.w700, fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Bar chart
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _weekData.asMap().entries.map((e) {
                      final i = e.key;
                      final d = e.value;
                      final isSelected = i == _selectedDay;
                      final pct = d.amount / maxAmount;

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDay = i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Tooltip
                              if (isSelected) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.courier,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _fmt(d.amount),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10, fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ] else
                                const SizedBox(height: 25),

                              // Bar
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                height: 80 * pct,
                                decoration: BoxDecoration(
                                  color: isSelected
                                    ? AppColors.courier
                                    : AppColors.courier.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Day label
                              Text(
                                d.day,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                    ? FontWeight.w700 : FontWeight.w400,
                                  color: isSelected
                                    ? AppColors.courier : AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Selected day detail
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(_selectedDay),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.courierLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniStat(
                          label: 'Buyurtmalar',
                          value: '${_weekData[_selectedDay].orders} ta',
                          emoji: '📦',
                        ),
                        _MiniStat(
                          label: 'Daromad',
                          value: _fmtFull(_weekData[_selectedDay].amount),
                          emoji: '💰',
                        ),
                        _MiniStat(
                          label: 'O\'rtacha',
                          value: _fmt(_weekData[_selectedDay].amount /
                              _weekData[_selectedDay].orders),
                          emoji: '📊',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // History tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Tarix',
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: 12),

          // Group by date
          ..._groupByDate(_history).entries.map((entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fmtFull(entry.value.fold(0.0, (s, h) => s + h.reward)),
                      style: const TextStyle(
                        color: AppColors.courier,
                        fontWeight: FontWeight.w600, fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: entry.value.asMap().entries.map((e) => Column(
                    children: [
                      _HistoryTile(item: e.value),
                      if (e.key < entry.value.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  )).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          )),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Map<String, List<_HistoryItem>> _groupByDate(List<_HistoryItem> items) {
    final map = <String, List<_HistoryItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.date, () => []).add(item);
    }
    return map;
  }

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daromad haqida',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            const _InfoRow('💰', 'Asosiy to\'lov',
                'Har bir yetkazib berish uchun 8 000 – 25 000 so\'m'),
            const _InfoRow('⏱', 'Tez bonus',
                '15 daqiqadan tez yetkazsangiz +10%'),
            const _InfoRow('⭐', 'Reyting bonusi',
                '4.8+ reyting uchun haftalik +5%'),
            const _InfoRow('📅', 'To\'lov kunlari',
                'Har dushanba va juma kuni hisobga tushadi'),
            const _InfoRow('🏦', 'Yechib olish',
                'Click, Payme, UzCard yoki Humo kartasiga'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showWithdrawSheet(BuildContext context) {
    final ctrl = TextEditingController(
      text: _balance.toInt().toString(),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pul yechib olish',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text('Mavjud: ${_fmtFull(_balance)}',
                style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14,
                )),
            const SizedBox(height: 20),

            // Amount input
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Summa (so\'m)',
                suffixText: 'so\'m',
              ),
            ),
            const SizedBox(height: 12),

            // Quick amounts
            Wrap(
              spacing: 8,
              children: [50000, 100000, 200000].map((v) => ActionChip(
                label: Text('${v ~/ 1000}k'),
                onPressed: () => ctrl.text = v.toString(),
                backgroundColor: AppColors.courierLight,
                labelStyle: const TextStyle(
                  color: AppColors.courier, fontWeight: FontWeight.w600,
                ),
              )).toList(),
            ),
            const SizedBox(height: 20),

            // Card selector
            const Text('Karta tanlang',
                style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14,
                )),
            const SizedBox(height: 10),
            _CardOption(
              icon: '💳',
              name: 'Humo **** 4521',
              isSelected: true,
              onTap: () {},
            ),
            const SizedBox(height: 8),
            _CardOption(
              icon: '💳',
              name: 'UzCard **** 8834',
              isSelected: false,
              onTap: () {},
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ So\'rov yuborildi! 1-2 soat ichida tushadi'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.courier,
              ),
              child: const Text('Yechib olish'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label, value, icon;
  const _BalanceStat({
    required this.label, required this.value, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 13,
            )),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value, emoji;
  const _MiniStat({
    required this.label, required this.value, required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13,
              color: AppColors.courier,
            )),
        Text(label,
            style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11,
            )),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final _HistoryItem item;
  const _HistoryTile({required this.item});

  String _fmt(double v) =>
    '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.courierLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('📦', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.shop,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(item.time,
                        style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12,
                        )),
                    const SizedBox(width: 6),
                    Container(
                      width: 3, height: 3,
                      decoration: const BoxDecoration(
                        color: AppColors.textHint, shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${item.km} km',
                        style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12,
                        )),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '+ ${_fmt(item.reward)}',
            style: const TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w700, fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon, title, subtitle;
  const _InfoRow(this.icon, this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardOption extends StatelessWidget {
  final String icon, name;
  final bool isSelected;
  final VoidCallback onTap;

  const _CardOption({
    required this.icon, required this.name,
    required this.isSelected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.courierLight : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.courier : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.courier, size: 20),
          ],
        ),
      ),
    );
  }
}
