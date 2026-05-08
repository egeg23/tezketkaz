import 'package:flutter/material.dart';
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'address.book_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(t(context, 'address.add')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _addresses.isEmpty
                  ? EmptyState(
                      emoji: '📍',
                      title: t(context, 'address.empty_title'),
                      description: t(context, 'address.empty_desc'),
                      ctaLabel: t(context, 'address.add'),
                      onCta: () => _openEditor(),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _addresses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _AddressTile(
                          address: _addresses[i],
                          onEdit: () => _openEditor(existing: _addresses[i]),
                          onDelete: () => _delete(_addresses[i]),
                          onSetDefault: () => _setDefault(_addresses[i]),
                          onPick: widget.picker
                              ? () => Navigator.of(context).pop(_addresses[i])
                              : null,
                        ),
                      ),
                    ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  final UserAddress address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  /// Non-null when the screen is opened in picker mode — tapping the tile
  /// triggers this callback instead of editing.
  final VoidCallback? onPick;
  const _AddressTile({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(address.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    )),
              ),
              if (address.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(t(context, 'address.default_badge'),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      )),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(address.fullAddress,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              )),
          if (address.apartment != null || address.entrance != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (address.entrance != null) '${t(context, 'address_entrance')}: ${address.entrance}',
                if (address.floor != null) '${t(context, 'address_floor')}: ${address.floor}',
                if (address.apartment != null) '${t(context, 'address_apartment')}: ${address.apartment}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (!address.isDefault)
                TextButton.icon(
                  onPressed: onSetDefault,
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: Text(t(context, 'make_default_address')),
                ),
              const Spacer(),
              IconButton(
                tooltip: t(context, 'address.edit'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.textSecondary),
              ),
              IconButton(
                tooltip: t(context, 'address.delete'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
    if (onPick == null) return tile;
    // Picker mode — tap anywhere on the tile to select. We still want the
    // inline edit / delete / set-default icon buttons to keep working,
    // which Material's InkWell handles via hit-testing children first.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: tile,
      ),
    );
  }
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
              activeColor: AppColors.primary,
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
