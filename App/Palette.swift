import UIKit
import SwiftUI

/// Semantic instrument roles. Foreground tint adapts to the surrounding theme;
/// the playing surface remains dark enough for small white labels.
enum Palette {
    static let tint = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.67, blue: 1, alpha: 1)
            : UIColor(red: 0, green: 0.32, blue: 0.84, alpha: 1)
    }
    static let playing = UIColor(red: 0, green: 0.30, blue: 0.79, alpha: 1)
    static let secondaryText = UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.76 : 0.36, alpha: 1)
    }
    static var accent: Color { Color(uiColor: tint) }
    static var secondary: Color { Color(uiColor: secondaryText) }
}
