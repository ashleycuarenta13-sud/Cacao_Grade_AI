import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cacao/widgets/modal_frame.dart';
import 'package:cacao/widgets/widgets.dart';

const _soft = Color(0xFFE6D8CF);
const _gold = Color(0xFFE6AD67);

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
                fontSize: 11,
                letterSpacing: 3,
                color: _gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Meet the Developers',
              style: GoogleFonts.playfairDisplay(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Three developers working together to bring smarter cacao assessment to mobile and web.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _soft, height: 1.5),
            ),
            const SizedBox(height: 22),
            ResponsiveGrid(
              minWidth: 190,
              children: [
                for (final d in devs)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0x12FFFFFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x26FFFFFF)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF4A281C), Color(0xFF8D5838)],
                            ),
                          ),
                          child: Text(
                            d.$1,
                            style: GoogleFonts.playfairDisplay(
                              color: const Color(0xFFF5D4A5),
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          d.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'Developer',
                          style: TextStyle(
                            color: Color(0xFFB9A79C),
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
                color: _gold,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
