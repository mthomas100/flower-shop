import SwiftUI
import UIKit

/// The six stems the shop sells, with everything the UI and the 3D scene need to know about each.
enum FlowerKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case rose, tulip, sunflower, lily, peony, daisy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rose: "Rose"
        case .tulip: "Tulip"
        case .sunflower: "Sunflower"
        case .lily: "Lily"
        case .peony: "Peony"
        case .daisy: "Daisy"
        }
    }

    var pluralName: String {
        switch self {
        case .daisy: "Daisies"
        case .lily: "Lilies"
        default: displayName + "s"
        }
    }

    var blurb: String {
        switch self {
        case .rose: "Classic romance"
        case .tulip: "Spring cheer"
        case .sunflower: "Pure sunshine"
        case .lily: "Elegant & fragrant"
        case .peony: "Lush & ruffled"
        case .daisy: "Fresh & simple"
        }
    }

    /// Price per stem, in dollars.
    var price: Double {
        switch self {
        case .rose: 4.50
        case .tulip: 3.00
        case .sunflower: 5.00
        case .lily: 4.00
        case .peony: 6.50
        case .daisy: 2.00
        }
    }

    /// Real-world height of the cut stem, in meters.
    var height: Float {
        switch self {
        case .rose: 0.45
        case .tulip: 0.40
        case .sunflower: 0.55
        case .lily: 0.48
        case .peony: 0.42
        case .daisy: 0.38
        }
    }

    var accent: Color { Color(uiColor: bloomColor) }

    var bloomColor: UIColor {
        switch self {
        case .rose: UIColor(red: 0.78, green: 0.08, blue: 0.16, alpha: 1)
        case .tulip: UIColor(red: 0.95, green: 0.45, blue: 0.62, alpha: 1)
        case .sunflower: UIColor(red: 0.98, green: 0.76, blue: 0.10, alpha: 1)
        case .lily: UIColor(red: 0.98, green: 0.93, blue: 0.96, alpha: 1)
        case .peony: UIColor(red: 0.97, green: 0.68, blue: 0.75, alpha: 1)
        case .daisy: UIColor(red: 0.99, green: 0.99, blue: 0.97, alpha: 1)
        }
    }

    var resourceName: String { rawValue }
}

extension Double {
    var asPrice: String { formatted(.currency(code: "USD")) }
}
