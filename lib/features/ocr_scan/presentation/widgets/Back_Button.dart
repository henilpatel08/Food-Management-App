import 'dart:ui';
import 'package:flutter/material.dart';

class BackButtonGlass extends StatelessWidget {
  const BackButtonGlass({
    super.key,
    this.onTap,
    this.icon,
    this.iconSize,
    this.blur,
    this.alpha,
  });

  final VoidCallback? onTap;
  final IconData? icon;
  final double? iconSize;
  final double? blur;
  final double? alpha;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.12; // ~12% of screen width

    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur ?? 14,
          sigmaY: blur ?? 14,
        ),
        child: Material(
          color: Colors.black.withValues(alpha: alpha ?? 0.3),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap ?? () => Navigator.of(context).pop(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(
                  icon ?? Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: iconSize ?? 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
