class AppConfig {
  // آی‌پی لپ‌تاپ و پورت سرور جنگو
  static const String serverIp = '192.168.1.3:8000';
  
  // آدرس‌های پایه
  static const String usersBaseUrl = 'http://$serverIp/api/users';
  static const String watchBaseUrl = 'http://$serverIp/api/watch';
}