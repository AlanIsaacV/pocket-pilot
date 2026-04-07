import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_colors.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_session_controller.dart';

class AIOverlay extends StatelessWidget {
  const AIOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AISessionController>();
    if (controller.state == AISessionState.idle) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: controller.endSession,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.displayText.isNotEmpty)
                        _ResponseText(
                          text: controller.displayText,
                          state: controller.state,
                        ),
                      if (controller.displayText.isNotEmpty)
                        const SizedBox(height: 16),
                      _StateLabel(state: controller.state),
                      const SizedBox(height: 20),
                      _MicButton(
                        state: controller.state,
                        onTapStart: controller.startListening,
                        onTapStop: controller.stopListening,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: controller.endSession,
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: AppColors.textMutedDark),
                        ),
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

class _ResponseText extends StatelessWidget {
  final String text;
  final AISessionState state;

  const _ResponseText({required this.text, required this.state});

  @override
  Widget build(BuildContext context) {
    final isListening = state == AISessionState.listening;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 150),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          text,
          style: TextStyle(
            color: isListening
                ? AppColors.textMutedDark
                : AppColors.textPrimaryDark,
            fontSize: isListening ? 14 : 16,
            fontStyle: isListening ? FontStyle.italic : FontStyle.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  final AISessionState state;

  const _StateLabel({required this.state});

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      AISessionState.ready => 'Toca para hablar',
      AISessionState.listening => 'Escuchando...',
      AISessionState.processing => 'Procesando...',
      AISessionState.speaking => 'Respondiendo...',
      AISessionState.error => 'Error',
      AISessionState.idle => '',
    };

    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textMutedDark,
        fontSize: 12,
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final AISessionState state;
  final VoidCallback onTapStart;
  final VoidCallback onTapStop;

  const _MicButton({
    required this.state,
    required this.onTapStart,
    required this.onTapStop,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AISessionState.ready || AISessionState.error => _TappableCircle(
          color: AppColors.primary,
          icon: Icons.mic,
          onTap: onTapStart,
        ),
      AISessionState.listening => _ListeningMicButton(onTap: onTapStop),
      AISessionState.processing => const SizedBox(
          width: 64,
          height: 64,
          child: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
          ),
        ),
      AISessionState.speaking => const _PulsingIcon(
          icon: Icons.volume_up,
          color: AppColors.primary,
        ),
      AISessionState.idle => const SizedBox.shrink(),
    };
  }
}

class _TappableCircle extends StatelessWidget {
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _TappableCircle({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

class _ListeningMicButton extends StatefulWidget {
  final VoidCallback onTap;

  const _ListeningMicButton({required this.onTap});

  @override
  State<_ListeningMicButton> createState() => _ListeningMicButtonState();
}

class _ListeningMicButtonState extends State<_ListeningMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = 1.0 + (_controller.value * 0.2);
          return Container(
            width: 64 * scale,
            height: 64 * scale,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stop, color: Colors.white, size: 28),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: 0.5 + (_controller.value * 0.5),
              child: Icon(widget.icon, color: widget.color, size: 36),
            );
          },
        ),
      ),
    );
  }
}
