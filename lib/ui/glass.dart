import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Fond « aurore » : dégradé nuit + halos de couleur qui dérivent lentement.
/// Il est placé sous toutes les routes (MaterialApp.builder), donc chaque
/// écran reçoit le même décor et ses cartes en verre le floutent.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C1429), inkBase, Color(0xFF090E1D)],
          ),
        ),
      ),
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            return LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              final size = (w < h ? h : w) * 0.75;
              Widget blob(Color color, double x, double y, double s, double a) => Positioned(
                    left: x - s / 2,
                    top: y - s / 2,
                    width: s,
                    height: s,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [color.withValues(alpha: a), color.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  );
              return Stack(clipBehavior: Clip.hardEdge, children: [
                blob(accentDeep, w * (0.12 + 0.05 * _sin(t)), h * (0.10 + 0.04 * _cos(t)), size, 0.40),
                blob(accent, w * (0.95 + 0.04 * _cos(t)), h * (0.55 + 0.05 * _sin(t)), size * 0.75, 0.22),
                blob(const Color(0xFF1D3A7A), w * (0.25 + 0.06 * _cos(t * 1.3)), h * (0.95 + 0.03 * _sin(t)), size * 0.9, 0.35),
              ]);
            });
          },
        ),
      ),
      widget.child,
    ]);
  }
}

double _sin(double x) => math.sin(x);
double _cos(double x) => math.cos(x);

/// Carte en verre dépoli : flou de l'arrière-plan, reflet dégradé, bord fin.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Gradient? tint;
  final double blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 22,
    this.tint,
    this.blur = 22,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: tint ??
                LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0.04),
                  ],
                ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: padding == null ? child : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
  }
}

/// Bouton principal à dégradé vif, avec halo coloré.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final Gradient gradient;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.gradient = brandGradient,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? [BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: SizedBox(
              height: 54,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: Colors.white), const SizedBox(width: 10)],
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre translucide (AppBar ou navigation) avec flou.
class GlassBar extends StatelessWidget {
  final Widget child;
  const GlassBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(color: Colors.white.withValues(alpha: 0.05), child: child),
        ),
      );
}

/// Texte avec dégradé de marque.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;
  const GradientText(this.text, {super.key, required this.style, this.gradient = brandGradient});

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => gradient.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
        blendMode: BlendMode.srcIn,
        child: Text(text, style: style.copyWith(color: Colors.white)),
      );
}
