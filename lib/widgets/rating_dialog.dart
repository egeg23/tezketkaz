import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

class RatingResult {
  final int rating;
  final String? text;
  final List<String> photos;
  const RatingResult({
    required this.rating,
    this.text,
    this.photos = const [],
  });
}

/// Reusable 5-star rating dialog with optional text and up to 3 photos.
///
/// Returns a [RatingResult] when the buyer taps "Yuborish" and `null` when
/// dismissed. Photo URLs returned here are local file paths — the calling
/// screen is responsible for uploading them to the backend before passing the
/// resulting URLs to `ReviewApi.create`.
class RatingDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  /// Show the photo-upload row. Pass `false` for courier ratings if you don't
  /// want to allow photos.
  final bool allowPhotos;

  const RatingDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.allowPhotos = true,
  });

  static Future<RatingResult?> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    bool allowPhotos = true,
  }) {
    return showDialog<RatingResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatingDialog(
        title: title,
        subtitle: subtitle,
        allowPhotos: allowPhotos,
      ),
    );
  }

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 0;
  final _textCtrl = TextEditingController();
  final List<String> _photos = [];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (picked != null) {
        setState(() => _photos.add(picked.path));
      }
    } catch (_) {
      // Picker can fail on web / desktop — ignore quietly.
    }
  }

  void _submit() {
    if (_rating == 0) return;
    Navigator.of(context).pop(RatingResult(
      rating: _rating,
      text: _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
      photos: List<String>.from(_photos),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return IconButton(
                  onPressed: () => setState(() => _rating = i + 1),
                  iconSize: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled ? AppColors.warning : AppColors.border,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Izoh (ixtiyoriy)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
            if (widget.allowPhotos) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < _photos.length; i++) ...[
                    _PhotoThumb(
                      path: _photos[i],
                      onRemove: () => setState(() => _photos.removeAt(i)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_photos.length < 3)
                    InkWell(
                      onTap: _pickPhoto,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius:
                              BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Bekor qilish"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _rating > 0 ? _submit : null,
                    child: const Text('Yuborish'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _PhotoThumb({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            color: AppColors.surfaceMuted,
            image: DecorationImage(
              image: _imageProvider(path),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ImageProvider _imageProvider(String path) {
    if (path.startsWith('http')) return NetworkImage(path);
    if (kIsWeb) return NetworkImage(path);
    return FileImage(File(path));
  }
}
