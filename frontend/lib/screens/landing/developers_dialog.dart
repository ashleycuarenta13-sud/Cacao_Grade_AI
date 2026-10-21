import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/modal_frame.dart';
import 'package:cacao/widgets/widgets.dart';

class DevelopersDialog extends StatelessWidget {
  const DevelopersDialog({super.key});

  @override
  Widget build(BuildContext context) {
    const devs = [
      ('RS', 'Rico D. Respecia'),
      ('AC', 'Ashley C. Cuarenta'),
      ('PC', 'Princess Ivony P. Castillo'),
    ];
    return ModalFrame(
      maxWidth: 720,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Text(
              'THE TEAM BEHIND CACAOGRADE AI',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                letterSpacing: 2,
                color: AppColors.violet,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Meet the Developers',
              style: GoogleFonts.playfairDisplay(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AppColors.brown800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Three developers working together to bring smarter cacao assessment to mobile and web.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mutedBrown),
            ),
            const SizedBox(height: 22),
            ResponsiveGrid(
              minWidth: 190,
              children: [
                for (final d in devs)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.brown800,
                          child: Text(
                            d.$1,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          d.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'Developer',
                          style: TextStyle(
                            color: AppColors.mutedBrown,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Code + Cacao = Impact',
              style: GoogleFonts.playfairDisplay(
                fontStyle: FontStyle.italic,
                color: AppColors.brown700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
