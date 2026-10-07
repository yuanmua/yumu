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
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let emphasized = Animation.spring(response: 0.5, dampingFraction: 0.8)
    }
}
