import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../utils/app_theme.dart';

class Esp32Service {
  static final Esp32Service _instance = Esp32Service._internal();
  factory Esp32Service() => _instance;
  Esp32Service._internal();

  bool _isConnected = false;
  String _baseUrl = AppConstants.esp32BaseUrl;

  bool get isConnected => _isConnected;

  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/ping'))
          .timeout(const Duration(seconds: 3));
      _isConnected = response.statusCode == 200;
      return _isConnected;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  Future<bool> sendCommand(MachineCommand command) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/control'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(command.toJson()),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
  }
}
