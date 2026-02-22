import Flutter
import UIKit

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
    _registerDeviceInfoChannel()
    return launched
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
