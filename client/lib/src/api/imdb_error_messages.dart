import 'imdb_api_exception.dart';

String friendlyErrorMessage(Object error) {
  if (error is! ImdbApiException) {
    return 'خطای غیرمنتظره رخ داد. دوباره تلاش کن.';
  }

  final message = error.message.toLowerCase();
  final statusCode = error.statusCode;

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection') ||
      message.contains('host lookup') ||
      message.contains('failed host')) {
    return 'اتصال اینترنت برقرار نیست یا سرور پاسخ نمی‌دهد. اینترنت را بررسی کن و دوباره تلاش کن.';
  }

  if (message.contains('timed out') || message.contains('timeout')) {
    return 'دریافت اطلاعات بیش از حد طول کشید. چند لحظه بعد دوباره تلاش کن.';
  }

  if (statusCode == 404 ||
      message.contains('not found') ||
      message.contains('movie not found') ||
      message.contains('incorrect imdb id')) {
    return 'فیلم یا سریالی با این مشخصات پیدا نشد. نام یا شناسه IMDb را دوباره بررسی کن.';
  }

  if (statusCode != null && statusCode >= 500) {
    return 'سرویس IMDb یا OMDb فعلاً در دسترس نیست. کمی بعد دوباره تلاش کن.';
  }

  if (statusCode != null && statusCode >= 400) {
    return 'درخواست اطلاعات رد شد. ورودی‌ها یا تنظیمات API را بررسی کن.';
  }

  return error.message;
}
