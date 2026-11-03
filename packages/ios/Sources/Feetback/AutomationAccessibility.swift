#if canImport(UIKit)
import Darwin

/// SwiftUI only exposes accessibility elements while an assistive client is running. This is the
/// switch XCTest flips; AccessibilitySnapshot uses it the same way. It is private API, so it is
/// looked up at runtime and missing symbols just mean a capture without elements.
@MainActor
enum AutomationAccessibility {
    private typealias Getter = @convention(c) () -> Int32
    private typealias Setter = @convention(c) (Int32) -> Void

    private static let functions: (get: Getter, set: Setter)? = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let get = dlsym(handle, "_AXSAutomationEnabled"),
              let set = dlsym(handle, "_AXSSetAutomationEnabled")
        else { return nil }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    static func whileEnabled<T>(_ body: () async -> T) async -> T {
        guard let functions else { return await body() }
        let previous = functions.get()
        functions.set(1)
        defer { functions.set(previous) }
        return await body()
    }
}
#endif
