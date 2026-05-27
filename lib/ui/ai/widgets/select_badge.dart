import 'package:flutter/material.dart';

class SelectBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  const SelectBadge({super.key, required this.label, required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: filled ? color.withValues(alpha: 0.5) : Colors.grey[300]!),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: filled ? color : Colors.grey[500])),
    );
  }
}
