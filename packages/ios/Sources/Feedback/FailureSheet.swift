#if canImport(UIKit)
import SwiftUI
import UIKit

/// Why a post failed, in full, with **Retry**. A post that lands shows only a toast.
struct FailureSheet: View {
    let name: String
    let problem: Problem
    let retry: () -> Void
    let close: () -> Void

    static func controller(name: String, problem: Problem, retry: @escaping () -> Void) -> UIViewController {
        let host = UIHostingController<FailureSheet?>(rootView: nil)
        host.rootView = FailureSheet(name: name, problem: problem, retry: retry) { [weak host] in host?.dismiss(animated: true) }
        host.overrideUserInterfaceStyle = .dark
        // The sheet's own background is drawn outside the controller's view, so it needs the style too.
        host.sheetPresentationController?.traitOverrides.userInterfaceStyle = .dark
        host.sheetPresentationController?.detents = [.medium(), .large()]
        return host
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { ProblemRows(problem: problem, expanded: true) }
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
