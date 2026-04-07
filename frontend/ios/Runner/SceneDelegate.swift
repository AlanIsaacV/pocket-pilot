import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let aiChannelName = "com.pocketpilot/ai_assistant"

  override func scene(
    _ scene: UIScene,
    continue userActivity: NSUserActivity
  ) {
    super.scene(scene, continue: userActivity)

    guard userActivity.activityType == "com.pocketpilot.launchAssistant" else {
      return
    }

    guard let flutterScene = scene as? FlutterScene else {
      return
    }

    let channel = FlutterMethodChannel(
      name: aiChannelName,
      binaryMessenger: flutterScene.engine.binaryMessenger
    )
    channel.invokeMethod("onLaunchAssistant", arguments: nil)
  }

}
