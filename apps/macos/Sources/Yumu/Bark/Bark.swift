import AppKit
import SwiftUI

/// Localised string from the Bark translation source (generated into Resources/).
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .module)
}

extension View {
    /// Bark animation that becomes instant when the system asks to reduce motion.
    func barkAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation, value: value)
    }
}
