import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/l10n.dart';
import '../../models/catalog.dart';
import '../../services/address_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map_picker.dart';

/// Buyer address book — lists, edits and removes saved delivery addresses.
///
/// In Phase 6 the cart screen reuses this screen as a picker. When
/// [picker] is true a tap on a tile pops with that [UserAddress] as result
/// rather than navigating to the edit form. Setting / making default
/// remains available either way.
class AddressBookScreen extends StatefulWidget {
  final bool picker;
  const AddressBookScreen({super.key, this.picker = false});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  bool _loading = true;
  String? _error;
  List<UserAddress> _addresses = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await AddressApi.instance.list();
      if (!mounted) return;
      setState(() { _addresses = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setDefault(UserAddress a) async {
    try {
      await AddressApi.instance.setDefault(a.id);
      await _load();
      if (mounted) context.showSuccess(t(context, 'address.default_set'));
    } catch (e) {
      if (mounted) context.showError('$e');
    }
  }

  Future<void> _delete(UserAddress a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t(context, 'address.confirm_delete')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(t(context, 'common.confirm')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await AddressApi.instance.remove(a.id);
      await _load();
    } catch (e) {
      if (mounted) context.showError('$e');
    }
  }

  Future<void> _openEditor({UserAddress? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddressEditScreen(initial: existing),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                title: 'Адреса',
                onBack: () => Navigator.of(context).maybePop(),
                onAdd: () => _openEditor(),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? ErrorView(message: _error!, onRetry: _load)
                        : _addresses.isEmpty
                            ? _Empty(onAdd: () => _openEditor())
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 8, 20, 24),
                                  children: [
                                    for (final a in _addresses)
                                      _AddrItem(
                                        address: a,
                                        onTap: widget.picker
                                            ? () => Navigator.of(context)
                                                .pop(a)
                                            : () => _openEditor(existing: a),
                                        onEdit: () =>
                                            _openEditor(existing: a),
                                        onDelete: () => _delete(a),
                                        onSetDefault: () => _setDefault(a),
                                      ),
                                    const SizedBox(height: 4),
                                    _AddDashedBtn(
                                      label: 'Добавить новый адрес',
                                      onTap: () => _openEditor(),
                                    ),
                                  ],
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onAdd;
  const _Header({
    required this.title,
    required this.onBack,
    required this.onAdd,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            _GlassChip(icon: Icons.chevron_left_rounded, onTap: onBack),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
            const Spacer(),
            _GlassChip(icon: Icons.add_rounded, onTap: onAdd),
          ],
        ),
      );
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassChip({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      );
}

// ─── Item ───────────────────────────────────────────────────────────────────
class _AddrItem extends StatelessWidget {
  final UserAddress address;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  const _AddrItem({
    required this.address,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('дом') || l.contains('home') || l.contains('uy')) {
      return Icons.home_rounded;
    }
    if (l.contains('раб') || l.contains('work') || l.contains('ish')) {
      return Icons.work_rounded;
    }
    return Icons.location_on_rounded;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: address.isDefault
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: address.isDefault
                  ? AppColors.primary.withValues(alpha: 0.30)
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(address.label),
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          address.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (address.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '★ ОСНОВНОЙ',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address.fullAddress,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (address.entrance != null ||
                        address.floor != null ||
                        address.apartment != null ||
                        address.intercom != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (address.entrance != null)
                            'Подъезд ${address.entrance}',
                          if (address.floor != null) '${address.floor} этаж',
                          if (address.apartment != null)
                            'кв. ${address.apartment}',
                          if (address.intercom != null)
                            'домофон ${address.intercom}',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                    if (!address.isDefault) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: onSetDefault,
                        child: Text(
                          'Сделать основным',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  GestureDetector(
                    onTap: onEdit,
                    child: Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.error),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

// ─── Dashed add btn ─────────────────────────────────────────────────────────
class _AddDashedBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddDashedBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.border,
              style: BorderStyle.solid,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📍', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  children: [
                    const TextSpan(text: 'Адресов '),
                    TextSpan(
                      text: 'пока нет',
                      style: GoogleFonts.playfairDisplay(
                        fontStyle: FontStyle.italic,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Добавьте адрес доставки',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              _AddDashedBtn(label: 'Добавить адрес', onTap: onAdd),
            ],
          ),
        ),
      );
}

/// Inline edit form. Pops with `true` once the address is saved successfully.
class AddressEditScreen extends StatefulWidget {
  final UserAddress? initial;
  const AddressEditScreen({super.key, this.initial});

  @override
  State<AddressEditScreen> createState() => _AddressEditScreenState();
}

class _AddressEditScreenState extends State<AddressEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _full;
  late final TextEditingController _entrance;
  late final TextEditingController _floor;
  late final TextEditingController _apartment;
  late final TextEditingController _intercom;
  late final TextEditingController _instructions;
  double? _lat;
  double? _lng;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _label = TextEditingController(text: i?.label ?? '');
    _full = TextEditingController(text: i?.fullAddress ?? '');
    _entrance = TextEditingController(text: i?.entrance ?? '');
    _floor = TextEditingController(text: i?.floor ?? '');
    _apartment = TextEditingController(text: i?.apartment ?? '');
    _intercom = TextEditingController(text: i?.intercom ?? '');
    _instructions = TextEditingController(text: i?.instructions ?? '');
    _lat = i?.lat;
    _lng = i?.lng;
    _isDefault = i?.isDefault ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _full.dispose();
    _entrance.dispose();
    _floor.dispose();
    _apartment.dispose();
    _intercom.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MapPicker(
          initial: _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null,
          // Phase 6 — let the picker auto-fill the full-address line via
          // reverse-geocoding when the user taps "Use current location".
          addressController: _full,
          onConfirm: (_) {},
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _lat = picked.latitude;
        _lng = picked.longitude;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = UserAddress(
        id: widget.initial?.id ?? '',
        label: _label.text.trim(),
        fullAddress: _full.text.trim(),
        lat: _lat,
        lng: _lng,
        entrance: _empty(_entrance.text),
        floor: _empty(_floor.text),
        apartment: _empty(_apartment.text),
        intercom: _empty(_intercom.text),
        instructions: _empty(_instructions.text),
        isDefault: _isDefault,
      );
      if (widget.initial == null) {
        await AddressApi.instance.create(payload);
      } else {
        await AddressApi.instance.update(widget.initial!.id, payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showError('$e');
      }
    }
  }

  String? _empty(String v) {
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.initial == null
            ? t(context, 'address.add')
            : t(context, 'address.edit')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            _Field(controller: _label, label: t(context, 'address.label_hint'), required: true),
            _Field(controller: _full, label: t(context, 'buyer.delivery_address'), required: true, maxLines: 2),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickOnMap,
              icon: const Icon(Icons.map_outlined),
              label: Text(_lat == null
                  ? t(context, 'map_pick_location')
                  : '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Field(controller: _entrance, label: t(context, 'address_entrance'))),
              const SizedBox(width: 8),
              Expanded(child: _Field(controller: _floor, label: t(context, 'address_floor'))),
            ]),
            Row(children: [
              Expanded(child: _Field(controller: _apartment, label: t(context, 'address_apartment'))),
              const SizedBox(width: 8),
              Expanded(child: _Field(controller: _intercom, label: t(context, 'address_intercom'))),
            ]),
            _Field(
              controller: _instructions,
              label: t(context, 'address_instructions'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
              title: Text(t(context, 'make_default_address')),
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: _saving
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(t(context, 'common.save')),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final int maxLines;
  const _Field({
    required this.controller,
    required this.label,
    this.required = false,
    this.maxLines = 1,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty)
              ? t(context, 'common.error')
              : null
          : null,
    ),
  );
}
