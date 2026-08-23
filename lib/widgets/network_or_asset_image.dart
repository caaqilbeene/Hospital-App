import 'package:flutter/material.dart';
import '../config/app_theme.dart';

import 'dart:convert';
import 'dart:io';

class NetworkOrAssetImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final BorderRadius? borderRadius;

  const NetworkOrAssetImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    final clean = imageUrl.trim();

    if (clean.startsWith('data:image/') || clean.startsWith('data:')) {
      try {
        final base64String = imageUrl.contains(',')
            ? imageUrl.split(',')[1]
            : imageUrl;
        final bytes = base64Decode(base64String);
        imageWidget = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      } catch (e) {
        imageWidget = _buildPlaceholder();
      }
    } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      imageWidget = Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    } else if (clean.startsWith('/') || clean.startsWith('file://')) {
      final path = clean.replaceFirst('file://', '');
      try {
        imageWidget = Image.file(
          File(path),
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      } catch (e) {
        imageWidget = _buildPlaceholder();
      }
    } else if (clean.isNotEmpty) {
      final String assetPath = clean.startsWith('assets/') ? clean : 'assets/$clean';
      imageWidget = Image.asset(
        assetPath,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          // If clean was 'images/logo_sa.jpeg' or 'assets/images/logo_sa.jpeg', try 'assets/logo_sa.jpeg'
          final String filenameOnly = clean.split('/').last;
          final String fallbackDirect = 'assets/$filenameOnly';
          return Image.asset(
            fallbackDirect,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              final String fallbackImages = 'assets/images/$filenameOnly';
              return Image.asset(
                fallbackImages,
                width: width,
                height: height,
                fit: fit,
                alignment: alignment,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return Image.asset(
                    'assets/images/logo.jpeg',
                    width: width,
                    height: height,
                    fit: fit,
                    alignment: alignment,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                  );
                },
              );
            },
          );
        },
      );
    } else {
      imageWidget = _buildPlaceholder();
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    final double iconSize = (width != null && width! <= 52)
        ? 22.0
        : (width != null && width! <= 80 ? 34.0 : 44.0);

    return Container(
      width: width,
      height: height,
      color: const Color(0xFFEAF5F2),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: AppTheme.primaryColor,
          size: iconSize,
        ),
      ),
    );
  }
}
