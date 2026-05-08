import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../models/payment_method.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/order_group_api.dart';
import '../../services/payment_method_api.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';

/// Phase 10.1 — the group's "war room". Renders different sub-views based on
/// [OrderGroup.status]:
///
/// - `open`     → invite + member carts + (host) lock button
/// - `locked`   → member shares + per-member pay buttons
/// - `paid`     → success view with link to the placed order
/// - `cancelled` / `expired` → read-only banner
///
/// Subscribes to the `orderGroup:*` socket events on mount and re-fetches
/// the group on each event so all members stay in sync without polling.
class GroupOrderScreen extends StatefulWidget {
  final String groupId;
  const GroupOrderScreen({super.key, required this.groupId});

  @override
  State<GroupOrderScreen> createState() => _GroupOrderScreenState();
}

class _GroupOrderScreenState extends State<GroupOrderScreen> {
  OrderGroup? _group;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  // Socket handlers — kept on the instance so we can detach in dispose.
  late final void Function(dynamic) _memberJoined;
  late final void Function(dynamic) _cartUpdated;
  late final void Function(dynamic) _locked;
  late final void Function(dynamic) _memberPaid;
  late final void Function(dynamic) _completed;
  late final void Function(dynamic) _cancelled;

  @override
  void initState() {
    super.initState();
    _memberJoined = (_) => _refetch();
    _cartUpdated = (_) => _refetch();
    _locked = (_) => _refetch();
    _memberPaid = (_) => _refetch();
    _completed = (_) => _refetch();
    _cancelled = (_) => _refetch();

    final s = SocketService.instance;
    s.on('orderGroup:memberJoined', _memberJoined);
    s.on('orderGroup:cartUpdated', _cartUpdated);
    s.on('orderGroup:locked', _locked);
    s.on('orderGroup:memberPaid', _memberPaid);
    s.on('orderGroup:completed', _completed);
    s.on('orderGroup:cancelled', _cancelled);

    _refetch();
  }

  @override
  void dispose() {
    final s = SocketService.instance;
    s.off('orderGroup:memberJoined', _memberJoined);
    s.off('orderGroup:cartUpdated', _cartUpdated);
    s.off('orderGroup:locked', _locked);
    s.off('orderGroup:memberPaid', _memberPaid);
    s.off('orderGroup:completed', _completed);
    s.off('orderGroup:cancelled', _cancelled);
    super.dispose();
  }

  Future<void> _refetch() async {
    try {
      final g = await OrderGroupApi.instance.getById(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = g;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _money(num v) =>
      Money(v.toDouble()).format(L10n.instance.locale.languageCode);

  String? _myUserId(BuildContext c) =>
      c.read<AuthProvider>().user?.id;

  bool _isHost(BuildContext c) {
    final me = _myUserId(c);
    return me != null && _group?.hostUserId == me;
  }

  OrderGroupMember? _meMember(BuildContext c) {
    final me = _myUserId(c);
    if (me == null || _group == null) return null;
    final mine = _group!.members.where((m) => m.userId == me);
    return mine.isEmpty ? null : mine.first;
  }

  Future<void> _share() async {
    final g = _group;
    if (g == null) return;
    HapticFeedback.lightImpact();
    final code = g.joinCode;
    final link = 'https://tezketkaz.uz/g/$code';
    await Share.share(
      'TezKetKaz · ${t(context, 'group.invite')}\n'
      '${t(context, 'group.share_code')}: $code\n'
      '$link',
    );
  }

  Future<void> _copyCode() async {
    final g = _group;
    if (g == null) return;
    await Clipboard.setData(ClipboardData(text: g.joinCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _addItems() async {
    final g = _group;
    if (g == null) return;
    // Send the buyer to the shop's catalog. On a real app the catalog screen
    // would write to the group cart on add; for now we open it and the user
    // composes their cart there. Once they're done they can return here and
    // the cart is synced via setMyCart from a deeper integration later.
    context.push('/buyer/catalog/all', extra: {
      'shopId': g.shopId,
      'shopName': g.shopName,
    });
  }

  Future<void> _lock() async {
    final g = _group;
    if (g == null || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await OrderGroupApi.instance.lock(g.id);
      if (!mounted) return;
      setState(() => _group = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final g = _group;
    if (g == null || _busy) return;
    setState(() => _busy = true);
    try {
      await OrderGroupApi.instance.cancel(g.id);
      if (!mounted) return;
      await _refetch();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final g = _group;
    if (g == null || _busy) return;
    setState(() => _busy = true);
    try {
      await OrderGroupApi.instance.leave(g.id);
      if (!mounted) return;
      context.go('/buyer');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PaymentMethod?> _pickPaymentMethod() async {
    try {
      final list = await PaymentMethodApi.instance.list();
      if (!mounted) return null;
      if (list.isEmpty) {
        // No saved methods — push the management screen.
        await context.push('/buyer/payment-methods');
        return null;
      }
      // Prefer default — minimal sheet; reuse cart's _PaymentMethodSheet would
      // require sharing it across screens. Inline a simple chooser instead.
      return await showModalBottomSheet<PaymentMethod>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in list)
                ListTile(
                  leading: Text(m.brandEmoji,
                      style: const TextStyle(fontSize: 22)),
                  title: Text(m.displayLabel),
                  subtitle: Text(m.providerName),
                  onTap: () => Navigator.of(context).pop(m),
                ),
            ],
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _payMyShare() async {
    final g = _group;
    if (g == null || _busy) return;
    final pm = await _pickPaymentMethod();
    if (pm == null) return;
    setState(() => _busy = true);
    try {
      await OrderGroupApi.instance.payMyShare(g.id, pm.id);
      await _refetch();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hostPay() async {
    final g = _group;
    if (g == null || _busy) return;
    final pm = await _pickPaymentMethod();
    if (pm == null) return;
    setState(() => _busy = true);
    try {
      await OrderGroupApi.instance.hostPay(g.id, pm.id);
      await _refetch();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final g = _group;
    if (g == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t(context, 'common.error'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? t(context, 'common.error'),
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final isHost = _isHost(context);
    final me = _meMember(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(g.shopName ?? t(context, 'group.create')),
        actions: [
          if (g.isOpen)
            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded),
              tooltip: 'Leave',
              onPressed: _busy ? null : (isHost ? _cancel : _leave),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refetch,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBanner(group: g),
            const SizedBox(height: 12),
            if (g.isOpen) ...[
              _InviteCard(
                joinCode: g.joinCode,
                onCopy: _copyCode,
                onShare: _share,
              ),
              const SizedBox(height: 16),
              _MembersCard(
                group: g,
                myUserId: _myUserId(context),
                fmtMoney: _money,
                showOwed: false,
              ),
              const SizedBox(height: 16),
              _MyBasketCard(
                me: me,
                fmtMoney: _money,
                onAddItems: _addItems,
              ),
              const SizedBox(height: 16),
              if (isHost)
                ElevatedButton.icon(
                  onPressed: (_busy || !_canLock(g)) ? null : _lock,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: Text(t(context, 'group.lock_order')),
                ),
            ] else if (g.isLocked) ...[
              _MembersCard(
                group: g,
                myUserId: _myUserId(context),
                fmtMoney: _money,
                showOwed: true,
              ),
              const SizedBox(height: 16),
              if (me != null && !me.isPaid)
                ElevatedButton.icon(
                  onPressed: _busy ? null : _payMyShare,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(
                    '${t(context, 'group.pay_my_share')} · ${_money(me.amountOwed)}',
                  ),
                ),
              if (isHost && g.paymentMode == 'host') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _hostPay,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(t(context, 'group.pay_for_all')),
                ),
              ],
            ] else if (g.isPaid) ...[
              _PaidSuccessCard(
                orderId: g.orderId,
                onViewOrder: g.orderId == null
                    ? null
                    : () => context.go('/buyer/tracking/${g.orderId}'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  bool _canLock(OrderGroup g) {
    return g.members.any((m) => m.itemCount > 0);
  }
}

class _StatusBanner extends StatelessWidget {
  final OrderGroup group;
  const _StatusBanner({required this.group});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _styleFor(context, group);
    final lockedAt = group.lockedAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(_iconFor(group), color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          if (group.isLocked && lockedAt != null)
            Text('${t(context, 'group.locked_at')} '
                '${lockedAt.hour.toString().padLeft(2, '0')}:${lockedAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  (Color, Color, String) _styleFor(BuildContext c, OrderGroup g) {
    if (g.isPaid) {
      return (
        AppColors.successLight,
        AppColors.success,
        '✅ ${t(c, 'order.status.delivered')}',
      );
    }
    if (g.isCancelled) {
      return (
        AppColors.errorLight,
        AppColors.error,
        t(c, 'group.cancelled'),
      );
    }
    if (g.isExpired) {
      return (
        AppColors.warningLight,
        AppColors.warning,
        t(c, 'group.expired'),
      );
    }
    if (g.isLocked) {
      return (AppColors.warningLight, AppColors.warning, '🔒 ${t(c, 'group.lock_order')}');
    }
    return (AppColors.primaryLight, AppColors.primary,
        '🤝 ${t(c, 'group.create')}');
  }

  IconData _iconFor(OrderGroup g) {
    if (g.isPaid) return Icons.check_circle_outline_rounded;
    if (g.isCancelled || g.isExpired) return Icons.cancel_outlined;
    if (g.isLocked) return Icons.lock_outline_rounded;
    return Icons.group_outlined;
  }
}

class _InviteCard extends StatelessWidget {
  final String joinCode;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  const _InviteCard({
    required this.joinCode,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context, 'group.share_code'),
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCopy,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Text(
                      joinCode,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onShare,
                icon: const Icon(Icons.share_rounded),
                tooltip: t(context, 'group.invite'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MembersCard extends StatelessWidget {
  final OrderGroup group;
  final String? myUserId;
  final String Function(num) fmtMoney;
  final bool showOwed;

  const _MembersCard({
    required this.group,
    required this.myUserId,
    required this.fmtMoney,
    required this.showOwed,
  });

  num _memberSubtotal(OrderGroupMember m) {
    var total = 0.0;
    for (final item in m.cartJson) {
      if (item is Map) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = (item['price'] as num?)?.toDouble() ??
            (item['unitPrice'] as num?)?.toDouble() ??
            0;
        total += qty * price;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final members =
        group.members.where((m) => !m.isLeft).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++) ...[
            _MemberRow(
              member: members[i],
              isHost: members[i].userId == group.hostUserId,
              isMe: members[i].userId == myUserId,
              showOwed: showOwed,
              subtotal: _memberSubtotal(members[i]),
              fmtMoney: fmtMoney,
            ),
            if (i < members.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final OrderGroupMember member;
  final bool isHost;
  final bool isMe;
  final bool showOwed;
  final num subtotal;
  final String Function(num) fmtMoney;

  const _MemberRow({
    required this.member,
    required this.isHost,
    required this.isMe,
    required this.showOwed,
    required this.subtotal,
    required this.fmtMoney,
  });

  @override
  Widget build(BuildContext context) {
    final name = member.userName?.isNotEmpty == true
        ? member.userName!
        : (isMe ? 'You' : member.userId.substring(0, 4));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Online indicator dot — proxied via "joined" status while we wait
          // for real presence telemetry.
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe ? '$name (${t(context, 'group.member_label')})' : name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.shopLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t(context, 'group.host_label'),
                          style: const TextStyle(
                            color: AppColors.shop,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${member.itemCount} items',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtMoney(showOwed ? member.amountOwed : subtotal),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14),
              ),
              if (member.isPaid)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('✓ paid',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.success,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MyBasketCard extends StatelessWidget {
  final OrderGroupMember? me;
  final String Function(num) fmtMoney;
  final VoidCallback onAddItems;

  const _MyBasketCard({
    required this.me,
    required this.fmtMoney,
    required this.onAddItems,
  });

  @override
  Widget build(BuildContext context) {
    final items = me?.cartJson ?? const [];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_basket_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('My basket',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              const Spacer(),
              if (me != null)
                Text(fmtMoney(me!.amountOwed),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(t(context, 'buyer.cart_empty'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13))
          else
            for (final item in items)
              if (item is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (item['productName'] ??
                                  item['name'] ??
                                  'Product')
                              .toString(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '× ${item['quantity'] ?? 1}',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAddItems,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add items'),
          ),
        ],
      ),
    );
  }
}

class _PaidSuccessCard extends StatelessWidget {
  final String? orderId;
  final VoidCallback? onViewOrder;
  const _PaidSuccessCard({required this.orderId, required this.onViewOrder});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            t(context, 'order.status.delivered'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (onViewOrder != null)
            ElevatedButton.icon(
              onPressed: onViewOrder,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('View order tracking'),
            ),
        ],
      ),
    );
  }
}
