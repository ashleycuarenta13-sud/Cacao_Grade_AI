import 'package:flutter/material.dart';

/// Purple gradient call-to-action button.
class PrimaryPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const PrimaryPill({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF8B5CC0), Color(0xFF6D469B)],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF583283).withValues(alpha: 0.3),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
  );
}

/// Navbar pill used for Login / Dashboard / Log out.
class LoginPill extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final Color background;
  const LoginPill({
    super.key,
    required this.onTap,
    this.label = 'Login',
    this.background = const Color(0xFF7852A9),
  });

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: const StadiumBorder(),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}
