#if canImport(UIKit)
import SwiftUI
import UIKit

/// Why a webhook post failed, with **Retry**. A post that lands shows only a toast.
struct WebhookFailureSheet: View {
    let name: String
    let problem: Problem
    let retry: () -> Void
    let close: () -> Void

    static func controller(name: String, problem: Problem, retry: @escaping () -> Void) -> UIViewController {
        let host = UIHostingController<WebhookFailureSheet?>(rootView: nil)
        host.rootView = WebhookFailureSheet(name: name, problem: problem, retry: retry) { [weak host] in host?.dismiss(animated: true) }
        host.overrideUserInterfaceStyle = .dark
        // The sheet's own background is drawn outside the controller's view, so it needs the style too.
        host.sheetPresentationController?.traitOverrides.userInterfaceStyle = .dark
        host.sheetPresentationController?.detents = [.medium(), .large()]
        return host
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProblemRows(problem: problem) }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Retry") {
                        close()
                        retry()
                    }
                }
            }
        }
        .dynamicTypeSize(...EditorView.largestTextSize)
    }
}
#endif
