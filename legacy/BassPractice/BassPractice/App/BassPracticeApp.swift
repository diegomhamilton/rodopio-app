import SwiftUI

@main
struct BassPracticeApp: App {
    private let dependencies: AppDependencies

    init() {
        dependencies = .live()
        dependencies.logger.appLaunched()
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(dependencies: dependencies)
        }
    }
}
