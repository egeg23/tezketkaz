import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Horizontal list of 30-minute scheduled-delivery slots for the next 24h.
///
/// • Skips slots that have already passed.
/// • Optionally clamps to a shop's working hours, expressed as `"HH:mm-HH:mm"`
///   (e.g. `"09:00-22:00"`). When `workingHours` is null we offer all slots.
/// • Calls [onSelected] with the chosen [DateTime] and shows the active slot
///   with the brand colour.
class TimeSlotPicker extends StatefulWidget {
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;
  final String? workingHours;
  final Duration slotDuration;
  final Duration leadTime;

  const TimeSlotPicker({
    super.key,
    required this.onSelected,
    this.selected,
    this.workingHours,
    this.slotDuration = const Duration(minutes: 30),
    this.leadTime = const Duration(minutes: 30),
  });

  @override
  State<TimeSlotPicker> createState() => _TimeSlotPickerState();
}

class _TimeSlotPickerState extends State<TimeSlotPicker> {
  late final List<DateTime> _slots = _buildSlots();

  /// Parse `"HH:mm-HH:mm"` → `(start, end)` tuple, or null on parse failure.
  ({TimeOfDay start, TimeOfDay end})? _parseHours(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*$')
        .firstMatch(raw);
    if (m == null) return null;
    return (
      start: TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!)),
      end: TimeOfDay(hour: int.parse(m.group(3)!), minute: int.parse(m.group(4)!)),
    );
  }

  bool _within(DateTime dt, ({TimeOfDay start, TimeOfDay end})? hours) {
    if (hours == null) return true;
    final mins = dt.hour * 60 + dt.minute;
    final s = hours.start.hour * 60 + hours.start.minute;
    final e = hours.end.hour * 60 + hours.end.minute;
    if (e > s) {
      return mins >= s && mins < e;
    }
    // wraps midnight
    return mins >= s || mins < e;
  }

  List<DateTime> _buildSlots() {
    final hours = _parseHours(widget.workingHours);
    final now = DateTime.now().add(widget.leadTime);
    // Round up to the next half hour.
    final remainder = now.minute % widget.slotDuration.inMinutes;
    var cursor = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .subtract(Duration(minutes: remainder, seconds: now.second));
    if (cursor.isBefore(now)) cursor = cursor.add(widget.slotDuration);

    final end = DateTime.now().add(const Duration(hours: 24));
    final out = <DateTime>[];
    while (cursor.isBefore(end) && out.length < 64) {
      if (_within(cursor, hours)) out.add(cursor);
      cursor = cursor.add(widget.slotDuration);
    }
    return out;
  }

  String _label(DateTime dt) {
    final today = DateTime.now();
    final isTomorrow = dt.day != today.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return isTomorrow ? 'Ert. $hh:$mm' : '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          "Bo'sh slot yo'q",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _slots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final slot = _slots[i];
          final isSelected = widget.selected != null &&
              widget.selected!.isAtSameMomentAs(slot);
          return _SlotChip(
            label: _label(slot),
            selected: isSelected,
            onTap: () => widget.onSelected(slot),
          );
        },
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      );
}
