import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/order_provider.dart';
import '../../services/api_client.dart';
import '../../services/support_api.dart';
import '../../theme/app_theme.dart';

/// Phase 10.2 — form for creating a new support ticket. Pulls the buyer's
/// recent orders from `OrderProvider` for the optional order picker; backend
/// is the source of truth for the actual list (we just surface what's loaded).
class SupportNewTicketScreen extends StatefulWidget {
  const SupportNewTicketScreen({super.key});

  @override
  State<SupportNewTicketScreen> createState() => _SupportNewTicketScreenState();
}

class _SupportNewTicketScreenState extends State<SupportNewTicketScreen> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String? _category;
  String? _orderId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (subject.isEmpty || body.isEmpty) {
      setState(() => _error = t(context, 'common.error'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ticket = await SupportApi.instance.create(
        subject: subject,
        category: _category,
        orderId: _orderId,
        body: body,
      );
      if (!mounted) return;
      // Replace this screen with the thread view so Back returns to inbox.
      context.go('/buyer/support/${ticket.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>().all;
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'support.new_ticket'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Category ───────────────────────────────────────────────────────
          DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: const InputDecoration(),
            hint: Text(t(context, 'support.category_other')),
            items: [
              for (final cat in supportCategories)
                DropdownMenuItem(
                  value: cat,
                  child: Text(t(context, 'support.category_$cat')),
                ),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),

          // ── Order picker (optional) ───────────────────────────────────────
          if (orders.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              value: _orderId,
              isExpanded: true,
              hint: const Text('Order (optional)'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('—'),
                ),
                for (final o in orders.take(20))
                  DropdownMenuItem<String?>(
                    value: o.id,
                    child: Text(
                      '#${o.orderNumber ?? o.id.substring(0, 6)} · ${o.shopName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _orderId = v),
            ),
            const SizedBox(height: 12),
          ],

          // ── Subject ───────────────────────────────────────────────────────
          TextField(
            controller: _subjectCtrl,
            decoration: InputDecoration(
              hintText: t(context, 'support.subject_hint'),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          // ── Body ──────────────────────────────────────────────────────────
          TextField(
            controller: _bodyCtrl,
            minLines: 5,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: t(context, 'support.body_hint'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text(t(context, 'common.continue')),
          ),
        ],
      ),
    );
  }
}
