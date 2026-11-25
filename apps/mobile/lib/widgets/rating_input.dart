import 'package:flutter/material.dart';

/// Shared 1-5 star + optional comment input for the client and captain
/// rating cards. The surrounding screen owns the card container and colors.
class RatingInput extends StatelessWidget {
  const RatingInput({
    super.key,
    required this.stars,
    required this.onStarsChanged,
    required this.commentController,
    required this.busy,
    required this.onSubmit,
    required this.foregroundColor,
    required this.mutedColor,
    required this.accentColor,
    required this.fieldFillColor,
    required this.buttonForegroundColor,
  });

  final int stars;
  final ValueChanged<int> onStarsChanged;
  final TextEditingController commentController;
  final bool busy;
  final VoidCallback onSubmit;
  final Color foregroundColor;
  final Color mutedColor;
  final Color accentColor;
  final Color fieldFillColor;
  final Color buttonForegroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                key: ValueKey('rating-star-$star'),
                onPressed: busy ? null : () => onStarsChanged(star),
                icon: Icon(
                  star <= stars
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: accentColor,
                  size: 30,
                ),
              ),
          ],
        ),
        TextField(
          key: const ValueKey('rating-comment-field'),
          controller: commentController,
          enabled: !busy,
          maxLines: 2,
          maxLength: 500,
          style: TextStyle(color: foregroundColor, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'تعليق اختياري',
            hintStyle: TextStyle(color: mutedColor, fontSize: 12),
            counterText: '',
            filled: true,
            fillColor: fieldFillColor,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            key: const ValueKey('submit-rating-button'),
            onPressed: busy ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: buttonForegroundColor,
            ),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.star_rate_rounded),
            label: const Text(
              'إرسال التقييم',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}
