import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = DashboardViewController()
        w.makeKeyAndVisible()
        window = w
        // L'écran reste toujours allumé : c'est un tableau de bord.
        application.isIdleTimerDisabled = true
        return true
    }
}
