import SwiftUI

/// The shop "screen" floating in front of the person: flower cards (the 3D stems hover in front of them),
/// the running bouquet tally, and shop controls.
struct ShopPanelView: View {
    let studio: BouquetStudio

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: PanelLayout.headerHeight)
            cards
                .frame(height: PanelLayout.cardSize.height)
            footer
                .frame(maxHeight: .infinity)
        }
        .frame(width: PanelLayout.size.width, height: PanelLayout.size.height)
        .background { backdrop }
        .clipShape(.rect(cornerRadius: PanelLayout.cornerRadius))
        .glassBackgroundEffect(in: .rect(cornerRadius: PanelLayout.cornerRadius))
        .overlay {
            if !studio.isStocked {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Stocking the shelves…")
                        .font(.title2)
                }
                .padding(40)
                .glassBackgroundEffect()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The Flower Shop")
                    .font(.system(size: 64, weight: .semibold, design: .serif))
                Text(subtitle)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            if studio.usingPlaceholderModels {
                Label("Preview models", systemImage: "cube.transparent")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassBackgroundEffect(in: .capsule)
            }
        }
        .padding(.horizontal, 70)
        .padding(.top, 20)
        .animation(.easeInOut, value: studio.bouquetIsComplete)
    }

    private var subtitle: String {
        if studio.bouquetIsComplete {
            return "💐 That's a bouquet! Keep adding stems, or start a new one."
        }
        return "Look at a flower, pinch, and pull it out. Let go over the vase to drop it in."
    }

    // MARK: Cards

    private var cards: some View {
        HStack(spacing: PanelLayout.cardSpacing) {
            ForEach(FlowerKind.allCases) { kind in
                FlowerCard(kind: kind, count: studio.arranged[kind] ?? 0) {
                    studio.quickAdd(kind)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 28) {
            BouquetTally(studio: studio)
            Spacer(minLength: 20)
            HStack(spacing: 16) {
                Button {
                    studio.startNewBouquet()
                } label: {
                    Label("New Bouquet", systemImage: "arrow.counterclockwise")
                }
                Button {
                    studio.recenter()
                } label: {
                    Label("Recenter", systemImage: "scope")
                }
                Button {
                    studio.onLeave?()
                } label: {
                    Label("Leave Shop", systemImage: "door.left.hand.open")
                }
            }
            .controlSize(.extraLarge)
            .font(.title3)
        }
        .padding(.horizontal, 70)
        .padding(.bottom, 24)
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            if let image = ShopArt.background {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: PanelLayout.size.width, height: PanelLayout.size.height)
                    .blur(radius: 6)
                    .clipped()
            }
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.45), .black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// One stem for sale. The top of the card stays empty: the real 3D flower floats there.
private struct FlowerCard: View {
    let kind: FlowerKind
    let count: Int
    let add: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RadialGradient(colors: [kind.accent.opacity(0.45), .clear], center: .center, startRadius: 4, endRadius: 150)
                    .blendMode(.plusLighter)
                if count > 0 {
                    Text("\(count) in vase")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: .capsule)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: PanelLayout.flowerAreaHeight)
            .padding(.top, PanelLayout.flowerAreaInset)

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(kind.displayName)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                Text(kind.blurb)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text(kind.price.asPrice)
                    .font(.system(size: 22, weight: .medium).monospacedDigit())
                Spacer()
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonBorderShape(.circle)
                .accessibilityLabel("Add a \(kind.displayName.lowercased()) to the vase")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(width: PanelLayout.cardSize.width, height: PanelLayout.cardSize.height)
        .background(.ultraThinMaterial.opacity(0.85), in: .rect(cornerRadius: 36))
        .overlay {
            RoundedRectangle(cornerRadius: 36)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
        }
        .animation(.spring(duration: 0.35), value: count)
    }
}

/// The running receipt for the bouquet in the vase.
private struct BouquetTally: View {
    let studio: BouquetStudio

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(studio.bouquetIsComplete ? Color.pink : Color.white, style: .init(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(studio.bouquetIsComplete ? "💐" : "\(studio.stemCount)")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .contentTransition(.numericText())
            }
            .frame(width: 84, height: 84)
            .animation(.spring(duration: 0.5), value: studio.stemCount)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                Text(detail)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var progress: CGFloat {
        min(CGFloat(studio.stemCount) / CGFloat(BouquetStudio.bouquetSize), 1)
    }

    private var headline: String {
        let count = studio.stemCount
        if count == 0 { return "Your vase is empty" }
        if studio.bouquetIsComplete { return "\(count) stems · \(studio.total.asPrice)" }
        let remaining = BouquetStudio.bouquetSize - count
        return "\(count) stem\(count == 1 ? "" : "s") · \(remaining) more for a bouquet"
    }

    private var detail: String {
        if studio.stemCount == 0 { return "Seven stems make a bouquet." }
        return FlowerKind.allCases.compactMap { kind in
            guard let n = studio.arranged[kind], n > 0 else { return nil }
            return "\(n) \(n == 1 ? kind.displayName : kind.pluralName)"
        }
        .joined(separator: " · ")
    }
}

enum ShopArt {
    static let background: UIImage? = {
        guard let url = Bundle.main.url(forResource: "shop_background", withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()
}
