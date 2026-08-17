import 'dart:async';

import 'package:flutter/material.dart';

import '../api/backend_api_client.dart';

class ServerConnectionMonitor extends StatefulWidget {
  const ServerConnectionMonitor({
    super.key,
    required this.client,
    required this.child,
    this.checkInterval = const Duration(seconds: 20),
    this.messageInterval = const Duration(minutes: 2),
    this.messageDuration = const Duration(seconds: 5),
  });

  final BackendApiClient client;
  final Widget child;
  final Duration checkInterval;
  final Duration messageInterval;
  final Duration messageDuration;

  @override
  State<ServerConnectionMonitor> createState() =>
      _ServerConnectionMonitorState();
}

class _ServerConnectionMonitorState extends State<ServerConnectionMonitor> {
  Timer? _timer;
  DateTime? _lastMessageAt;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.client.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNow());
      _timer = Timer.periodic(widget.checkInterval, (_) => _checkNow());
    }
  }

  @override
  void didUpdateWidget(covariant ServerConnectionMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client.baseUrl != widget.client.baseUrl) {
      _timer?.cancel();
      _lastMessageAt = null;
      if (widget.client.isConfigured) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkNow());
        _timer = Timer.periodic(widget.checkInterval, (_) => _checkNow());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkNow() async {
    if (_checking || !mounted || !widget.client.isConfigured) {
      return;
    }

    _checking = true;
    final healthy = await widget.client.isHealthy();
    _checking = false;

    if (!mounted) {
      return;
    }

    if (healthy) {
      _lastMessageAt = null;
      return;
    }

    final now = DateTime.now();
    final lastMessageAt = _lastMessageAt;
    final shouldShow =
        lastMessageAt == null ||
        now.difference(lastMessageAt) >= widget.messageInterval;

    if (shouldShow) {
      _lastMessageAt = now;
      _showOfflineMessage();
    }
  }

  void _showOfflineMessage() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: widget.messageDuration,
        behavior: SnackBarBehavior.floating,
        content: const Text(
          'اتصال به اینترنت یا سرور برقرار نیست. لطفا وضعیت اینترنت و IP سرور را بررسی کن.',
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
