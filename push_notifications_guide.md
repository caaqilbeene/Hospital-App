# Tilmaamaha Push Notifications (Firebase Cloud Messaging - FCM)

Si fariimaha iyo ogeysiisyada ay kor ugu soo koraan shaashadda mobile-ka ee macaamiisha (xitaa marka ay ka maqan yihiin app-ka), waxaa loo baahan yahay in app-ka lagu xiro adeegga **Firebase Cloud Messaging (FCM)**. 

Maadaama shaqadani ay u baahan tahay akoonno horumarineed (Developer Accounts) iyo isku-xirka server-ka, hoos ka eeg tallaabooyinka loo baahan yahay si tan loogu hirgeliyo production-ka.

---

## 1. Firebase Console Configuration (Diyaarinta Platform-yada)

### A. Android Setup
1. Tag [Firebase Console](https://console.firebase.google.com/) kuna dar app-kaaga Android adoo isticmaalaya package name-ka app-ka (tusaale: `com.example.medicine_app`).
2. Soo degso faylka `google-services.json` kuna dar galka `android/app/`.
3. Ku dar Firebase Gradle plugins faylasha `android/build.gradle` iyo `android/app/build.gradle`.

### B. iOS Setup (Wuxuu u baahan yahay Apple Developer Account)
1. Tag [Apple Developer Portal](https://developer.apple.com/) oo ka samee **App ID** leh awoodda **Push Notifications**.
2. Samee **APNs Authentication Key** (fayl `.p8` ah) kana soo soo degso portal-ka.
3. Ku shaqaysii furahaas (.p8) qeybta **Project Settings > Cloud Messaging > iOS app configuration** ee Firebase Console.
4. Soo degso faylka `GoogleService-Info.plist` kuna dar mashruuca Xcode ee hoos yimaada `ios/Runner/`.
5. Ka fur Xcode, qeybta **Signing & Capabilities** ku dar **Push Notifications** iyo **Background Modes** (dooro *Remote notifications*).

---

## 2. Pubspec Dependencies (Maktabadaha loo baahan yahay)

Ku dar maktabadahaan faylkaaga `pubspec.yaml` si ay u taageeraan fariimaha dibadda ka imaanaya:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.0.0
  firebase_messaging: ^15.0.0
  flutter_local_notifications: ^17.0.0
```

---

## 3. Flutter Integration Code (Isku-xirka Qoraalka App-ka)

Tani waa qaabka loo habeeyo Flutter si uu u aqbalo fariimaha asagoo xiran (Background) ama furan (Foreground).

### A. Initialize Firebase Messaging
Qeybta `main.dart` ku dar shaqadaan top-level-ka ah si ay u qabato fariimaha marka app-ku xiran yahay:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Fariin cusub baa timid: ${message.messageId}");
}

// Qeybta dhexdeeda main()
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Diiwaangeli background handler-ka
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  runApp(const MyApp());
}
```

### B. Requesting Permissions (Fadlan u ogolaada Ogeysiisyada)
Marka uu macmiilku app-ka soo galo, weydii ogolaansho push notifications ah:

```dart
void requestNotificationPermission() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('Macmiilku wuu ogolaaday ogeysiisyada!');
    
    // Soo saar Token-ka aaladda si loogu diro Supabase
    String? token = await messaging.getToken();
    print("Device Token: $token");
    // Halkan waxaad token-kaan ugu kaydin kartaa database-ka si aad fariin gaar ah ugu dirto macmiilkaan
  }
}
```

### C. Displaying Foreground Notifications (Marka uu app-ku furan yahay)
Isticmaal `flutter_local_notifications` si aad u soo bandhigto ogeysiiska haddii uu macmiilku ku dhex jiro app-ka:

```dart
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void setupForegroundNotifications() {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  });
}
```

---

## 4. How to Broadcast from Admin/Server (Sida fariinta looga soo diro Backend-ka)

Marka uu Adminku gujiyo **"Send Broadcast"**, server-ku wuxuu wacayaa Firebase API isagoo u diraya payload dhamaan aaladaha ku biiray channel-ka `hospital_announcements`:

* **Topic Subscription**: App-ka macaamiisha ku dar line-kaan:
  `await FirebaseMessaging.instance.subscribeToTopic('hospital_announcements');`
* **Trigger HTTP POST request** oo loo diro Firebase v1 API:
  ```json
  {
    "message": {
      "topic": "hospital_announcements",
      "notification": {
        "title": "Ciid Wanaagsan! 🌙",
        "body": "Cisbitaalka Nasiib wuxuu dhammaan macaamiishiisa u rajaynayaa Ciid barakaysan."
      },
      "android": {
        "priority": "high"
      },
      "apns": {
        "payload": {
          "aps": {
            "content-available": 1
          }
        }
      }
    }
  }
  ```
