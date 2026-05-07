import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class CourierProfileScreen extends StatelessWidget {
  const CourierProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/switch-role'),
            icon: const Text('🛒', style: TextStyle(fontSize: 14)),
            label: const Text('Xaridor',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Profile header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.courierLight,
                          child: Text(
                            (user.name?.isNotEmpty == true)
                              ? user.name![0].toUpperCase() : 'K',
                            style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800,
                              color: AppColors.courier,
                            ),
                          ),
                        ),
                        // Online indicator
                        Positioned(
                          bottom: 2, right: 2,
                          child: Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name ?? 'Kuryer',
                              style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 2),
                          Text(user.phone,
                              style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13,
                              )),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('✅',
                                        style: TextStyle(fontSize: 11)),
                                    SizedBox(width: 4),
                                    Text('Tasdiqlangan kuryer',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.textSecondary),
                      onPressed: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),

                // Rating + stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    _StatBadge(emoji: '⭐', value: '4.9', label: 'Reyting'),
                    _StatBadge(emoji: '📦', value: '127', label: 'Buyurtmalar'),
                    _StatBadge(emoji: '🏆', value: '98%', label: 'Vaqtida'),
                    _StatBadge(emoji: '💨', value: '18 min', label: 'O\'rtacha'),
                  ],
                ),
              ],
            ),
          ),

          // Rating breakdown
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reyting taqsimoti',
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15,
                    )),
                const SizedBox(height: 14),
                ...[
                  [5, 0.78],
                  [4, 0.15],
                  [3, 0.05],
                  [2, 0.01],
                  [1, 0.01],
                ].map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Text('${r[0].toInt()} ⭐',
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: r[1] as double,
                            backgroundColor: AppColors.bg,
                            color: r[0] as int >= 4
                              ? AppColors.success : AppColors.warning,
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${((r[1] as double) * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Sections
          _Section(title: 'Ish sozlamalari', children: [
            _MenuItem(
              icon: '🛵',
              title: 'Transport turi',
              subtitle: 'Moped / Velosiped / Piyoda',
              onTap: () => _showTransportSheet(context),
            ),
            _MenuItem(
              icon: '🗺️',
              title: 'Hudud',
              subtitle: 'Yunusobod, Mirzo Ulug\'bek',
              onTap: () {},
            ),
            _MenuItem(
              icon: '📅',
              title: 'Ish jadvali',
              subtitle: 'Du-Ju, 09:00 – 21:00',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 12),

          _Section(title: 'Hujjatlar', children: [
            _MenuItem(
              icon: '📄',
              title: 'Pasport',
              subtitle: 'AA 1234567 · Tasdiqlangan',
              trailing: const _StatusDot(AppColors.success),
              onTap: () {},
            ),
            _MenuItem(
              icon: '🏛️',
              title: 'STIR (INN)',
              subtitle: '123456789 · Tasdiqlangan',
              trailing: const _StatusDot(AppColors.success),
              onTap: () {},
            ),
            _MenuItem(
              icon: '💼',
              title: 'O\'z-o\'zini band qilish',
              subtitle: 'Soliq qo\'mitasi · Faol',
              trailing: const _StatusDot(AppColors.success),
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 12),

          _Section(title: 'Yordam', children: [
            _MenuItem(
              icon: '💬',
              title: 'Qo\'llab-quvvatlash',
              subtitle: '24/7 onlayn',
              onTap: () {},
            ),
            _MenuItem(
              icon: '📖',
              title: 'Kuryer qo\'llanmasi',
              onTap: () {},
            ),
            _MenuItem(
              icon: '🔔',
              title: 'Bildirishnomalar',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 12),

          // Logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                auth.logout();
                context.go('/auth/login');
              },
              icon: const Icon(Icons.logout, color: AppColors.error, size: 18),
              label: const Text('Chiqish',
                  style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Version
          const Center(
            child: Text('TezKetKaz Kuryer v1.0.0',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showTransportSheet(BuildContext context) {
    final types = [
      {'icon': '🛵', 'name': 'Moped / Skuter', 'desc': 'Maksimal tezlik'},
      {'icon': '🚲', 'name': 'Velosiped', 'desc': 'Yaqin masofalar'},
      {'icon': '🚶', 'name': 'Piyoda', 'desc': 'Faqat yaqin buyurtmalar'},
      {'icon': '🚗', 'name': 'Avtomobil', 'desc': 'Yirik buyurtmalar'},
    ];

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
            Text('Transport turini tanlang',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            ...types.map((t) => ListTile(
              leading: Text(t['icon']!, style: const TextStyle(fontSize: 28)),
              title: Text(t['name']!,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t['desc']!),
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(context),
            )),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String emoji, value, label;
  const _StatBadge({
    required this.emoji, required this.value, required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 15,
              color: AppColors.textPrimary,
            )),
        Text(label,
            style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11,
            )),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontSize: 13,
              )),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: children.asMap().entries.map((e) => Column(
              children: [
                e.value,
                if (e.key < children.length - 1)
                  const Divider(height: 1, indent: 56, endIndent: 16),
              ],
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String icon, title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon, required this.title,
    this.subtitle, this.trailing, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 22)),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: subtitle != null
        ? Text(subtitle!, style: const TextStyle(fontSize: 12))
        : null,
      trailing: trailing ??
        const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
