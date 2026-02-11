import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Re-activate audio session on foreground return
        (UIApplication.shared.delegate as? AppDelegate)?.configureAudioSession()

        // Resume any suspended web AudioContexts
        if let gameVC = window?.rootViewController as? GameViewController {
            gameVC.resumeAudioContext()
        }
    }
}
