import CoreGraphics

/// Fixed geometry of the shop panel, in points. The 3D shelf flowers are placed from the same numbers,
/// so each one floats in front of its card.
enum PanelLayout {
    static let size = CGSize(width: 1500, height: 940)
    static let cornerRadius: CGFloat = 60

    static let headerHeight: CGFloat = 200
    static let cardsTop: CGFloat = headerHeight
    static let cardSize = CGSize(width: 204, height: 480)
    static let cardSpacing: CGFloat = 22
    static let flowerAreaInset: CGFloat = 18
    static let flowerAreaHeight: CGFloat = 300

    static var rowWidth: CGFloat {
        let count = CGFloat(FlowerKind.allCases.count)
        return count * cardSize.width + (count - 1) * cardSpacing
    }

    static func cardCenterX(_ index: Int) -> CGFloat {
        (size.width - rowWidth) / 2 + cardSize.width / 2 + CGFloat(index) * (cardSize.width + cardSpacing)
    }

    /// Center of the area where the 3D flower hovers, measured from the panel's top-left corner.
    static func flowerCenter(_ index: Int) -> CGPoint {
        CGPoint(x: cardCenterX(index), y: cardsTop + flowerAreaInset + flowerAreaHeight / 2)
    }
}
