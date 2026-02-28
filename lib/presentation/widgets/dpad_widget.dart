// lib/presentation/widgets/dpad_widget.dart

import 'package:flutter/material.dart';
import '../../domain/entities/tv_command.dart';
import 'remote_button.dart';

class DPadWidget extends StatelessWidget {
  final void Function(TvCommand) onCommand;

  const DPadWidget({super.key, required this.onCommand});

  static const _accent = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: 200,
            height: 200,
            decoration: const BoxDecoration(
              color: Color(0xFF181828),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF111120),
                  offset: Offset(6, 6),
                  blurRadius: 12,
                ),
                BoxShadow(
                  color: Color(0xFF252540),
                  offset: Offset(-6, -6),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          // Up
          Positioned(
            top: 8,
            child: RemoteButton(
              size: 52,
              onTap: () => onCommand(TvCommand.up),
              child: const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 28),
            ),
          ),
          // Down
          Positioned(
            bottom: 8,
            child: RemoteButton(
              size: 52,
              onTap: () => onCommand(TvCommand.down),
              child: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 28),
            ),
          ),
          // Left
          Positioned(
            left: 8,
            child: RemoteButton(
              size: 52,
              onTap: () => onCommand(TvCommand.left),
              child: const Icon(Icons.keyboard_arrow_left, color: Colors.white70, size: 28),
            ),
          ),
          // Right
          Positioned(
            right: 8,
            child: RemoteButton(
              size: 52,
              onTap: () => onCommand(TvCommand.right),
              child: const Icon(Icons.keyboard_arrow_right, color: Colors.white70, size: 28),
            ),
          ),
          // Center OK
          RemoteButton(
            size: 64,
            color: _accent,
            onTap: () => onCommand(TvCommand.ok),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
