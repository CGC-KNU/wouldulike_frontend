import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    _clearAppIconBadge(application)
    _registerDeviceInfoChannel()
    return launched
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    _clearAppIconBadge(application)
  }

  /// 홈 화면 앱 아이콘의 알림 숫자 배지를 지운다.
  private func _clearAppIconBadge(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0)
    }
  }

  private func _registerDeviceInfoChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // Root controller might not be ready at didFinish; retry shortly.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?._registerDeviceInfoChannel()
      }
      return
    }

    let deviceChannel = FlutterMethodChannel(
      name: "app/device_info",
      binaryMessenger: controller.binaryMessenger
    )
    deviceChannel.setMethodCallHandler { call, result in
      if call.method == "isSimulator" {
#if targetEnvironment(simulator)
        result(true)
#else
        result(false)
#endif
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
