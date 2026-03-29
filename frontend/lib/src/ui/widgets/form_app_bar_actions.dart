import 'package:flutter/material.dart';

class FormAppBarSecondaryAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDestructive;

  const FormAppBarSecondaryAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDestructive = false,
  });
}

class FormAppBarActions extends StatelessWidget {
  final bool canSave;
  final bool isSaving;
  final VoidCallback onSave;
  final String saveTooltip;
  final FormAppBarSecondaryAction? secondaryAction;

  const FormAppBarActions({
    required this.canSave,
    required this.isSaving,
    required this.onSave,
    required this.saveTooltip,
    this.secondaryAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = secondaryAction;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (secondary != null)
          IconButton(
            tooltip: secondary.tooltip,
            onPressed: isSaving ? null : secondary.onPressed,
            icon: Icon(secondary.icon),
            color: secondary.isDestructive
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        IconButton(
          tooltip: saveTooltip,
          onPressed: (!canSave || isSaving) ? null : onSave,
          icon: isSaving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : const Icon(Icons.save_outlined),
        ),
      ],
    );
  }
}
