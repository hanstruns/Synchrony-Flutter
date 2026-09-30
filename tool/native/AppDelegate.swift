import Flutter
import UIKit
import AVFoundation
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var feedbackChannel: FlutterMethodChannel?
  private var effectPlayer: AVAudioPlayer?
  private var musicPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(self, selector: #selector(stopAllAudio),
      name: UIApplication.willResignActiveNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "synchrony/feedback",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    feedbackChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      if call.method == "musicStop" { self.stopMusic(); result(nil); return }
      if call.method == "musicVolume" {
        let value = (call.arguments as? NSNumber)?.floatValue ?? 0
        self.musicPlayer?.volume = min(0.5, max(0, value))
        result(nil); return
      }
      if call.method == "musicLoad" {
        guard let bytes = call.arguments as? FlutterStandardTypedData else {
          result(FlutterError(code: "BAD_MUSIC", message: "Falta la música", details: nil)); return
        }
        do {
          self.stopMusic()
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.ambient, mode: .default)
          try session.setActive(true)
          let player = try AVAudioPlayer(data: bytes.data)
          self.musicPlayer = player
          player.numberOfLoops = -1
          player.volume = 0
          player.prepareToPlay()
          player.play()
          result(nil)
        } catch {
          result(FlutterError(code: "MUSIC_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }
      if call.method == "stop" { self.stopFeedback(); result(nil); return }
      guard call.method == "play" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BAD_ARGS", message: "Faltan parámetros", details: nil)); return
      }
      do {
        if args["sound"] as? Bool == true {
          guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "BAD_AUDIO", message: "Falta el sonido", details: nil)); return
          }
          let session = AVAudioSession.sharedInstance()
          // Respeta el interruptor de silencio; los efectos no interrumpen otra música.
          try session.setCategory(.ambient, mode: .default)
          try session.setActive(true)
          self.effectPlayer?.stop()
          self.effectPlayer = try AVAudioPlayer(data: bytes.data)
          self.effectPlayer?.prepareToPlay()
          self.effectPlayer?.play()
        }
        let available = UIDevice.current.userInterfaceIdiom == .phone
        if args["vibration"] as? Bool == true && available {
          let cue = args["cue"] as? String ?? "card"
          if ["mistake", "lost", "test"].contains(cue) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
          } else if ["success", "won"].contains(cue) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
          } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          }
        }
        result(available)
      } catch {
        result(FlutterError(code: "FEEDBACK_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func stopMusic() {
    musicPlayer?.stop()
    musicPlayer = nil
  }

  @objc private func stopAllAudio() {
    stopFeedback()
    stopMusic()
  }

  @objc private func stopFeedback() {
    effectPlayer?.stop()
    effectPlayer = nil
  }
}
