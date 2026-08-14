class ImdbApiException implements Exception {
  const ImdbApiException(
    this.message, {
    this.uri,
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final Uri? uri;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() {
    final parts = <String>[message];
    if (statusCode != null) {
      parts.add('status=$statusCode');
    }
    if (uri != null) {
      parts.add('uri=$uri');
    }
    if (responseBody != null && responseBody!.isNotEmpty) {
      parts.add('body=$responseBody');
    }
    return 'ImdbApiException(${parts.join(', ')})';
  }
}
