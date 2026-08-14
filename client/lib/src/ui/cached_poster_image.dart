import 'dart:io';

import 'package:flutter/material.dart';

import '../storage/poster_cache_store.dart';

class CachedPosterImage extends StatefulWidget {
  const CachedPosterImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<CachedPosterImage> createState() => _CachedPosterImageState();
}

class _CachedPosterImageState extends State<CachedPosterImage> {
  Future<File?>? _fileFuture;

  @override
  void initState() {
    super.initState();
    _resetFuture();
  }

  @override
  void didUpdateWidget(covariant CachedPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resetFuture();
    }
  }

  void _resetFuture() {
    final url = widget.url;
    _fileFuture = url == null ? null : PosterCacheStore.instance.imageFile(url);
  }

  @override
  Widget build(BuildContext context) {
    final future = _fileFuture;
    if (future == null) {
      return widget.fallback;
    }

    return FutureBuilder<File?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final file = snapshot.data;
        if (file == null) {
          return widget.fallback;
        }

        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => widget.fallback,
        );
      },
    );
  }
}
