// features/statistics/ui/widgets/time_window_chips.dart
import 'package:flutter/material.dart';

class TimeWindowChips extends StatelessWidget {
  final int selectedMonths;
  final ValueChanged<int> onChanged;

  const TimeWindowChips({
    super.key,
    required this.selectedMonths,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<int>(value: 3, label: Text('3m')),
        ButtonSegment<int>(value: 6, label: Text('6m')),
        ButtonSegment<int>(value: 12, label: Text('12m')),
      ],
      selected: {selectedMonths},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
