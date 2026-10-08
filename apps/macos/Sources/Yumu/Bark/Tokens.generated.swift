// Generated from bark/tokens by bark/codegen/swift.py. Do not edit.
import SwiftUI

enum Bark {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let emphasized = Animation.spring(response: 0.5, dampingFraction: 0.8)
    }
    enum Colors {
        static let backgroundCanvas = dynamic(light: (0.980, 0.980, 0.973, 1), dark: (0.110, 0.110, 0.118, 1))
        static let backgroundSidebar = dynamic(light: (0.949, 0.949, 0.937, 1), dark: (0.086, 0.086, 0.094, 1))
        static let surfaceDefault = dynamic(light: (1.000, 1.000, 1.000, 1), dark: (0.149, 0.149, 0.157, 1))
        static let surfaceElevated = dynamic(light: (1.000, 1.000, 1.000, 1), dark: (0.180, 0.180, 0.192, 1))
        static let surfaceSunken = dynamic(light: (0.941, 0.941, 0.929, 1), dark: (0.090, 0.090, 0.102, 1))
        static let surfaceHover = dynamic(light: (0.000, 0.000, 0.000, 0.04), dark: (1.000, 1.000, 1.000, 0.06))
        static let surfacePressed = dynamic(light: (0.000, 0.000, 0.000, 0.08), dark: (1.000, 1.000, 1.000, 0.1))
        static let borderSubtle = dynamic(light: (0.000, 0.000, 0.000, 0.08), dark: (1.000, 1.000, 1.000, 0.09))
        static let borderStrong = dynamic(light: (0.000, 0.000, 0.000, 0.18), dark: (1.000, 1.000, 1.000, 0.2))
        static let textPrimary = dynamic(light: (0.078, 0.078, 0.078, 1), dark: (0.949, 0.949, 0.941, 1))
        static let textSecondary = dynamic(light: (0.420, 0.420, 0.408, 1), dark: (0.659, 0.659, 0.647, 1))
        static let textTertiary = dynamic(light: (0.612, 0.612, 0.596, 1), dark: (0.451, 0.451, 0.439, 1))
        static let textOnAccent = dynamic(light: (1.000, 1.000, 1.000, 1), dark: (1.000, 1.000, 1.000, 1))
        static let statusSuccess = dynamic(light: (0.184, 0.541, 0.353, 1), dark: (0.310, 0.710, 0.490, 1))
        static let statusWarning = dynamic(light: (0.776, 0.533, 0.165, 1), dark: (0.878, 0.663, 0.290, 1))
        static let statusDanger = dynamic(light: (0.788, 0.271, 0.231, 1), dark: (0.886, 0.420, 0.380, 1))
    }
    enum Text {
        static let display = Font.system(size: 28, weight: .semibold)
        static let displaySize: CGFloat = 28
        static let title = Font.system(size: 20, weight: .semibold)
        static let titleSize: CGFloat = 20
        static let headline = Font.system(size: 15, weight: .semibold)
        static let headlineSize: CGFloat = 15
        static let body = Font.system(size: 13, weight: .regular)
        static let bodySize: CGFloat = 13
        static let callout = Font.system(size: 12, weight: .regular)
        static let calloutSize: CGFloat = 12
        static let caption = Font.system(size: 11, weight: .regular)
        static let captionSize: CGFloat = 11
    }
}
