import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_ui_state.dart';
import '../features/player/bottom_player.dart';

class AnimatedBottomPlayer extends StatelessWidget {
  const AnimatedBottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerUIState>(
      builder: (context, uiState, child) {
        return AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset: uiState.hideBottomPlayer ? const Offset(0, 1) : Offset.zero,
          curve: Curves.easeInOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: uiState.hideBottomPlayer ? 0.0 : 1.0,
            child: const BottomPlayer(),
          ),
        );
      },
    );
  }
}
