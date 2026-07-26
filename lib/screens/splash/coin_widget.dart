import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'coin_painter.dart';

/// Renders the 3D spinning metallic gold coin with authentic depth and PBR lighting.
class CoinWidget extends StatelessWidget {
  final double rotationAngle;
  final double size;
  final bool isDarkTheme;
  final double reflectionOffset;

  const CoinWidget({
    super.key,
    required this.rotationAngle,
    required this.size,
    required this.isDarkTheme,
    required this.reflectionOffset,
  });

  @override
  Widget build(BuildContext context) {
    // 3D perspective distortion parameter
    const double perspective = 0.0013;
    final bool isFrontFacing = math.cos(rotationAngle) >= 0;

    // Generate 7 internal cylinder slices to simulate 3D milled rim depth
    final List<Widget> rimLayers = [];
    const int rimSliceCount = 7;
    const double totalThickness = 12.0;

    // Shared centered logo container for seamless startup transition
    final Widget logoContainer = Container(
      width: size * 0.58,
      height: size * 0.58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/icon/app_icon.png',
          fit: BoxFit.cover,
          cacheWidth: 300,
          cacheHeight: 300,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.account_balance_wallet,
            color: Color(0xFFD4AF37),
            size: 48,
          ),
        ),
      ),
    );

    for (int i = 0; i < rimSliceCount; i++) {
      final double zOffset = -totalThickness / 2 + (totalThickness / (rimSliceCount - 1)) * i;
      rimLayers.add(
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, perspective)
            ..rotateY(rotationAngle)
            ..translateByDouble(0.0, 0.0, zOffset, 1.0),
          child: CustomPaint(
            size: Size(size, size),
            painter: CoinRimPainter(reflectionAngle: reflectionOffset),
          ),
        ),
      );
    }

    // Front face (Side A - Engraved Currency Symbol)
    final Widget sideA = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, perspective)
        ..rotateY(rotationAngle)
        ..translateByDouble(0.0, 0.0, totalThickness / 2 + 0.2, 1.0),
      child: CustomPaint(
        size: Size(size, size),
        painter: CoinFacePainter(
          isSideA: true,
          reflectionAngle: reflectionOffset,
          isDarkTheme: isDarkTheme,
        ),
      ),
    );

    // Back face (Side B - Centered Credits Logo)
    // Rotate an additional PI radians around Y so the logo is not mirrored horizontally when facing the camera.
    final Widget sideB = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, perspective)
        ..rotateY(rotationAngle)
        ..translateByDouble(0.0, 0.0, -totalThickness / 2 - 0.2, 1.0)
        ..rotateY(math.pi),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: CoinFacePainter(
              isSideA: false,
              reflectionAngle: reflectionOffset,
              isDarkTheme: isDarkTheme,
            ),
          ),
          logoContainer,
        ],
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isFrontFacing) sideB else sideA,
          ...rimLayers,
          if (isFrontFacing) sideA else sideB,
        ],
      ),
    );
  }
}
