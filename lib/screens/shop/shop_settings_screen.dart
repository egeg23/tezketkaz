import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/shop_settings_api.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart';

/// Phase 6 — Shop Settings screen.
///
/// Tabs:
///   1. "Ish vaqti"  — 7 working-hours rows (Mon..Sun, Sunday=0).
///   2. "Sozlamalar" — placeholder for currency / notifications (Phase 7).
class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _shopId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Local working copy — index by `dayOfWeek` (0..6, Sunday=0).
  final Map<int, ShopWorkingHoursRow> _rows = {};

  static const _dayNames = <int, String>{
    0: 'Yakshanba',
    1: 'Dushanba',
    2: 'Seshanba',
    3: 'Chorshanba',
    4: 'Payshanba',
    5: 'Juma',
    6: 'Shanba',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    _shopId = auth.user?.shopId;
    if (_shopId == null) {
      setState(() {
        _loading = false;
        _error = 'Do\'kon topilmadi';
      });
      return;
    }
    try {
      final fetched =
          await ShopSettingsApi.instance.getWorkingHours(_shopId!);
      final byDay = <int, ShopWorkingHoursRow>{
        for (final r in fetched) r.dayOfWeek: r,
      };
      // Ensure all 7 days exist (defaults: 09:00 – 22:00, open).
      for (var i = 0; i < 7; i++) {
        byDay.putIfAbsent(
          i,
          () => ShopWorkingHoursRow(
            dayOfWeek: i,
            startsAt: '09:00',
            endsAt: '22:00',
            isClosed: false,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(byDay);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _save() async {
    if (_shopId == null) return;
    setState(() => _saving = true);
    try {
      final list = List<ShopWorkingHoursRow>.generate(
        7,
        (i) => _rows[i]!,
      );
      await ShopSettingsApi.instance.putWorkingHours(_shopId!, list);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Ish vaqti saqlandi'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xatolik: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editTime(int day, bool isStart) async {
    final row = _rows[day]!;
    final current = _parse(isStart ? row.startsAt : row.endsAt);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked == null) return;
    final s = _formatHM(picked);
    setState(() {
      _rows[day] = isStart
          ? row.copyWith(startsAt: s)
          : row.copyWith(endsAt: s);
    });
  }

  TimeOfDay _parse(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _formatHM(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: const Text("Do'kon sozlamalari"),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Ish vaqti'),
            Tab(text: 'Sozlamalar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildWorkingHoursTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  Widget _buildWorkingHoursTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Qayta')),
            ],
          ),
        ),
      );
    }

    // Order Mon..Sun for the UI even though backend uses Sunday=0.
    const visualOrder = [1, 2, 3, 4, 5, 6, 0];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final day in visualOrder) _buildDayRow(day),
              const SizedBox(height: 80),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Saqlash'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kShopColor,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayRow(int day) {
    final row = _rows[day]!;
    final isOpen = !row.isClosed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_dayNames[day]!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15,
                    )),
              ),
              Text(isOpen ? 'Ochiq' : 'Yopiq',
                  style: TextStyle(
                    color: isOpen ? AppColors.success : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  )),
              const SizedBox(width: 8),
              Switch(
                value: isOpen,
                onChanged: (v) => setState(() {
                  _rows[day] = row.copyWith(isClosed: !v);
                }),
                activeColor: kShopColor,
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TimePill(
                    label: 'Ochilish',
                    value: row.startsAt,
                    onTap: () => _editTime(day, true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimePill(
                    label: 'Yopilish',
                    value: row.endsAt,
                    onTap: () => _editTime(day, false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Valyuta',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              SizedBox(height: 6),
              Text('UZS — so\'m',
                  style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 12),
              Text('KZT / KGS — Phase 7da faollashadi',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bildirishnomalar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              SizedBox(height: 6),
              Text('Yangi buyurtmalar push + ovoz orqali keladi',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimePill extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _TimePill({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11,
                )),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16,
                )),
          ],
        ),
      ),
    );
  }
}
