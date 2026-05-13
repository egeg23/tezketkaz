import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/verification_api.dart';
import '../../theme/app_theme.dart';

class CourierVerificationScreen extends StatefulWidget {
  const CourierVerificationScreen({super.key});

  @override
  State<CourierVerificationScreen> createState() =>
      _CourierVerificationScreenState();
}

class _CourierVerificationScreenState
    extends State<CourierVerificationScreen> {
  final _pageController = PageController();
  int _step = 0;

  // Form fields
  final _nameCtrl = TextEditingController();
  final _stirCtrl = TextEditingController();        // ИНН 9 цифр
  final _passportCtrl = TextEditingController();    // AA 1234567
  bool _hasSelfEmployed = false;
  bool _isLoading = false;

  // Phase 6 — KYC documents.
  final Map<String, VerificationDocument> _docs = {};
  bool _docsLoading = true;
  String? _docsError;

  bool get _step0Valid => _nameCtrl.text.trim().length >= 4;
  bool get _step1Valid =>
      _stirCtrl.text.length == 9 &&
      _passportCtrl.text.length >= 9 &&
      _allDocsUploaded;
  bool get _step2Valid => _hasSelfEmployed;

  bool get _allDocsUploaded => VerificationDocType.all
      .every((t) => _docs.containsKey(t));

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    try {
      final list = await VerificationApi.instance.myDocs();
      if (!mounted) return;
      setState(() {
        _docs
          ..clear()
          ..addEntries(list.map((d) => MapEntry(d.type, d)));
        _docsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _docsLoading = false;
        _docsError = e.toString();
      });
    }
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.submitCourierVerification(
      stir: _stirCtrl.text,
      passportSeries: _passportCtrl.text,
      fullName: _nameCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _isLoading = false);
      if (ok) {
        _showSuccessAndPop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Xatolik yuz berdi')),
        );
      }
    }
  }

  void _showSuccessAndPop() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('✅', style: TextStyle(fontSize: 40)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ariza yuborildi!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arizangiz 1-2 ish kuni ichida ko\'rib chiqiladi. '
              'Natija haqida SMS va push-xabar olasiz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/buyer');
              },
              child: const Text('Bosh sahifaga qaytish'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(String type) async {
    final source = await _chooseSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked == null) return;

    final file = File(picked.path);
    final existing = _docs[type];

    setState(() {
      // Optimistic — show "uploading" by removing the cached entry briefly.
      _docs.remove(type);
    });

    try {
      // Replace previous upload (delete old + insert new).
      if (existing != null) {
        try {
          await VerificationApi.instance.delete(existing.id);
        } catch (_) {
          // Silently ignore — server may have already cleaned it up.
        }
      }
      final doc = await VerificationApi.instance.upload(type, file);
      if (!mounted) return;
      setState(() => _docs[type] = doc);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Roll back optimistic removal.
      if (existing != null) setState(() => _docs[type] = existing);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yuklab bo\'lmadi: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      if (existing != null) setState(() => _docs[type] = existing);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yuklab bo\'lmadi: $e')),
      );
    }
  }

  Future<ImageSource?> _chooseSource() async {
    if (kIsWeb) return ImageSource.gallery;
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galereya'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Kuryer ro\'yxatdan o\'tish'),
      ),
      body: Column(
        children: [
          // Progress indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: List.generate(3, (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? AppColors.courier : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )),
            ),
          ),

          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StepPersonal(nameCtrl: _nameCtrl, onChanged: () => setState(() {})),
                _StepDocuments(
                  stirCtrl: _stirCtrl,
                  passportCtrl: _passportCtrl,
                  docs: _docs,
                  docsLoading: _docsLoading,
                  docsError: _docsError,
                  onChanged: () => setState(() {}),
                  onPickDoc: _pickAndUpload,
                ),
                _StepSelfEmployed(
                  hasStatus: _hasSelfEmployed,
                  onChanged: (v) => setState(() => _hasSelfEmployed = v),
                ),
              ],
            ),
          ),

          // Bottom button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.courier,
              ),
              onPressed: _canProceed() ? _next : null,
              child: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2,
                    ),
                  )
                : Text(_step < 2 ? 'Keyingisi' : 'Ariza yuborish'),
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case 0: return _step0Valid;
      case 1: return _step1Valid;
      case 2: return _step2Valid;
      default: return false;
    }
  }
}

class _StepPersonal extends StatelessWidget {
  final TextEditingController nameCtrl;
  final VoidCallback onChanged;
  const _StepPersonal({required this.nameCtrl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👤', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Shaxsiy ma\'lumot',
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text(
            'To\'liq ism-sharifingizni kiriting',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'To\'liq ism-sharif',
              hintText: 'Ism Familiya Otasining ismi',
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _StepDocuments extends StatelessWidget {
  final TextEditingController stirCtrl;
  final TextEditingController passportCtrl;
  final Map<String, VerificationDocument> docs;
  final bool docsLoading;
  final String? docsError;
  final VoidCallback onChanged;
  final void Function(String type) onPickDoc;

  const _StepDocuments({
    required this.stirCtrl,
    required this.passportCtrl,
    required this.docs,
    required this.docsLoading,
    required this.docsError,
    required this.onChanged,
    required this.onPickDoc,
  });

  static const _docMeta = <String, ({String label, String emoji})>{
    VerificationDocType.passportFront:
        (label: 'Pasport (old tomoni)', emoji: '🪪'),
    VerificationDocType.passportBack:
        (label: 'Pasport (orqa tomoni)', emoji: '🪪'),
    VerificationDocType.selfie:
        (label: 'Selfie pasport bilan', emoji: '🤳'),
    VerificationDocType.selfEmployedCert:
        (label: 'Samozanyatiy ma\'lumotnomasi', emoji: '📄'),
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📄', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Hujjatlar', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text(
            'Hujjatlar Soliq qo\'mitasi orqali tekshiriladi',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // STIR / ИНН
          TextFormField(
            controller: stirCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: const InputDecoration(
              labelText: 'STIR (INN)',
              hintText: '9 ta raqam',
              helperText: 'Soliq to\'lovchining individual raqami',
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),

          // Passport
          TextFormField(
            controller: passportCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: const InputDecoration(
              labelText: 'Pasport seriyasi va raqami',
              hintText: 'AA 1234567',
              helperText: '2 harf + 7 raqam',
            ),
            onChanged: (_) => onChanged(),
          ),

          const SizedBox(height: 24),
          Text('Hujjat fotosuratlari',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Har bir hujjat aniq va to\'liq ko\'rinadigan bo\'lsin',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),

          if (docsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (docsError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Hujjatlarni yuklab bo\'lmadi: $docsError',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            )
          else
            Column(
              children: [
                for (final type in VerificationDocType.all)
                  _DocTile(
                    label: _docMeta[type]!.label,
                    emoji: _docMeta[type]!.emoji,
                    doc: docs[type],
                    onTap: () => onPickDoc(type),
                  ),
              ],
            ),

          const SizedBox(height: 18),

          // Info box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ma\'lumotlaringiz shifrlangan holda saqlanadi va '
                    'faqat tekshirish uchun ishlatiladi.',
                    style: TextStyle(
                      color: AppColors.primaryDark, fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final String label;
  final String emoji;
  final VerificationDocument? doc;
  final VoidCallback onTap;

  const _DocTile({
    required this.label,
    required this.emoji,
    required this.doc,
    required this.onTap,
  });

  (String, Color, Color) get _statusInfo {
    if (doc == null) {
      return ('Yuklanmagan', AppColors.textHint, AppColors.surfaceMuted);
    }
    if (doc!.isApproved) {
      return ('✓ Tasdiqlangan', AppColors.success, AppColors.primaryLight);
    }
    if (doc!.isRejected) {
      return ('✗ Rad etilgan', AppColors.error, AppColors.errorLight);
    }
    return ('⏳ Tekshirilmoqda', AppColors.warning, AppColors.warningLight);
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, color, bg) = _statusInfo;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: doc == null ? AppColors.border : color,
                width: doc == null ? 1 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14,
                              )),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      doc == null
                          ? Icons.upload_outlined
                          : Icons.refresh,
                      color: AppColors.textHint,
                    ),
                  ],
                ),
                if (doc?.isRejected == true &&
                    doc!.rejectionReason != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(doc!.rejectionReason!,
                              style: const TextStyle(
                                  color: AppColors.error, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepSelfEmployed extends StatelessWidget {
  final bool hasStatus;
  final ValueChanged<bool> onChanged;

  const _StepSelfEmployed({
    required this.hasStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💼', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('O\'z-o\'zini band qilish',
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text(
            'O\'zbekistonda kuryer sifatida ishlash uchun '
            'o\'z-o\'zini band qilgan (самозанятый) maqomiga ega bo\'lishingiz kerak.',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // How to get self-employed status
          const _InfoStep(
            num: '1',
            title: 'my.soliq.uz saytiga kiring',
            subtitle: 'Soliq qo\'mitasining rasmiy portali',
          ),
          const _InfoStep(
            num: '2',
            title: '"O\'z-o\'zini band qilish" bo\'limini toping',
            subtitle: 'Ro\'yxatdan o\'tish bepul va tezkor',
          ),
          const _InfoStep(
            num: '3',
            title: 'Ariza toldiring',
            subtitle: 'Daromaddan 1% soliq — tovar aylanmasi 1 mlrd so\'mgacha',
          ),
          const SizedBox(height: 24),

          // Confirm checkbox
          GestureDetector(
            onTap: () => onChanged(!hasStatus),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasStatus
                  ? AppColors.courierLight
                  : AppColors.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasStatus ? AppColors.courier : AppColors.border,
                  width: hasStatus ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: hasStatus ? AppColors.courier : AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: hasStatus ? AppColors.courier : AppColors.border,
                        width: 2,
                      ),
                    ),
                    child: hasStatus
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Men o\'z-o\'zini band qilgan maqomiga egaman '
                      'yoki uni olishga roziman',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final String num;
  final String title;
  final String subtitle;

  const _InfoStep({
    required this.num,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(
              color: AppColors.courierLight,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: AppColors.courier,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
