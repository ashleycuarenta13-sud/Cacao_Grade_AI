import 'package:flutter/material.dart';

/// Rounded dialog shell with a close button, shared by the landing dialogs.
class ModalFrame extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const ModalFrame({super.key, required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Stack(
        children: [
          SingleChildScrollView(child: child),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}
