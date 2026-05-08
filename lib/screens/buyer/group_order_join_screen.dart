import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../services/api_client.dart';
import '../../services/order_group_api.dart';
import '../../theme/app_theme.dart';

/// Phase 10.1 — single-page form for joining an existing group via its
/// 6-character code. Also reachable from the deep-link handler in main.dart
/// (`tezketkaz://group/<code>`), which prefills [initialCode].
class GroupOrderJoinScreen extends StatefulWidget {
  final String? initialCode;
  const GroupOrderJoinScreen({super.key, this.initialCode});

  @override
  State<GroupOrderJoinScreen> createState() => _GroupOrderJoinScreenState();
}

class _GroupOrderJoinScreenState extends State<GroupOrderJoinScreen> {
  late final TextEditingController _codeCtrl;
  bool _isJoining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.initialCode ?? '');
    if ((widget.initialCode ?? '').isNotEmpty) {
      // Auto-submit if we got here via deep link.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _isJoining = true;
      _error = null;
    });
    try {
      final group = await OrderGroupApi.instance.join(code);
      if (!mounted) return;
      // Replace this screen so the back button doesn't return to the form.
      context.go('/buyer/group/${group.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'group.join'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text('🤝',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                t(context, 'group.share_code'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeCtrl,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(8),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: const InputDecoration(
                  hintText: 'ABCD12',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isJoining ? null : _join,
                child: _isJoining
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(t(context, 'group.join')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
