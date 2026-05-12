import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _ctrl = TextEditingController();

  bool get _isValid => _ctrl.text.trim().length >= 2;

  void _continue() {
    if (!_isValid) return;
    context.read<AuthProvider>().setName(_ctrl.text.trim());
    context.go('/buyer');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Center(
                child: Text('👋', style: TextStyle(fontSize: 64)),
              ),
              const SizedBox(height: 32),
              Text(
                t(context, 'auth.name.title'),
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t(context, 'auth.name.subtitle'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                decoration: InputDecoration(hintText: t(context, 'auth.name.hint')),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _continue(),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              AnimatedOpacity(
                opacity: _isValid ? 1 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  onPressed: _isValid ? _continue : null,
                  child: Text(t(context, 'common.continue')),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
