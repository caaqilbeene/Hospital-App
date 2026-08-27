import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'fcm_config.dart';

class FcmSender {
  static final FcmSender _instance = FcmSender._internal();
  factory FcmSender() => _instance;
  FcmSender._internal();

  // FCM scope required
  static const _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  AutoRefreshingAuthClient? _client;

  Future<AutoRefreshingAuthClient> _getAuthenticatedClient() async {
    if (_client != null) return _client!;

    try {
      final decodedJson = jsonDecode(FcmConfig.serviceAccountJson);
      if (decodedJson['private_key'] == null || decodedJson['private_key'].toString().isEmpty) {
        throw Exception("Private key in Service Account is empty.");
      }
      
      final credentials = ServiceAccountCredentials.fromJson(decodedJson);
      _client = await clientViaServiceAccount(credentials, _scopes);
      return _client!;
    } catch (e) {
      debugPrint("FcmSender: Error creating authenticated client: $e");
      rethrow;
    }
  }

  // Send notification to a specific device token
  Future<bool> sendNotification({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (token.isEmpty) {
      debugPrint("FcmSender: Token is empty, skipping push notification.");
      return false;
    }

    try {
      final client = await _getAuthenticatedClient();
      final url = 'https://fcm.googleapis.com/v1/projects/${FcmConfig.projectId}/messages:send';

      final Map<String, dynamic> messagePayload = {
        'token': token,
        'notification': {
          'title': title,
          'body': body,
        },
        'android': {
          'priority': 'high',
          'notification': {
            'sound': 'default',
            'channel_id': 'high_importance_channel',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          }
        }
      };

      if (data != null && data.isNotEmpty) {
        messagePayload['data'] = data;
      }

      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': messagePayload}),
      );

      if (response.statusCode == 200) {
        debugPrint("FcmSender: Notification successfully sent to device token.");
        return true;
      } else {
        debugPrint("FcmSender: Failed to send notification: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("FcmSender: Exception while sending notification: $e");
      return false;
    }
  }

  // Send notification to a topic (broadcast to all subscribed users)
  Future<bool> sendTopicNotification({
    required String topic,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final client = await _getAuthenticatedClient();
      final url = 'https://fcm.googleapis.com/v1/projects/${FcmConfig.projectId}/messages:send';

      final Map<String, dynamic> messagePayload = {
        'topic': topic,
        'notification': {
          'title': title,
          'body': body,
        },
        'android': {
          'priority': 'high',
          'notification': {
            'sound': 'default',
            'channel_id': 'high_importance_channel',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          }
        }
      };

      if (data != null && data.isNotEmpty) {
        messagePayload['data'] = data;
      }

      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': messagePayload}),
      );

      if (response.statusCode == 200) {
        debugPrint("FcmSender: Topic notification successfully sent to: $topic.");
        return true;
      } else {
        debugPrint("FcmSender: Failed to send topic notification: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("FcmSender: Exception while sending topic notification: $e");
      return false;
    }
  }
}
