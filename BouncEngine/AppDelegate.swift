import UIKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureAudioSession()
        registerForAudioInterruptions()
        return true
    }

    // MARK: - Audio Session

    /// Configures AVAudioSession so WKWebView AudioContexts survive background/lock/interruptions.
    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps audio alive; .mixWithOthers avoids killing other apps' audio
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[Audio] Failed to configure session: \(error)")
        }
    }

    private func registerForAudioInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            configureAudioSession()
            // Tell the GameViewController to resume web AudioContexts
            NotificationCenter.default.post(name: .resumeWebAudio, object: nil)
        }
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}

// MARK: - Notifications
extension Notification.Name {
    static let resumeWebAudio = Notification.Name("resumeWebAudio")
}
