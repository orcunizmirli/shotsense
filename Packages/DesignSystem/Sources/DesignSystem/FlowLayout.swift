import SwiftUI

/// Satır sonuna gelince alt satıra kayan yerleşim (etiket/çip bulutu).
///
/// **Neden özel bir `Layout`:** `HStack` içindeki çipler taşarsa kırpılır, `LazyVGrid`
/// ise eşit genişlikli sütun dayatır — oysa çip genişliği metnine bağlıdır. Sarmalayan
/// yerleşim SwiftUI'de yerleşik değildir ve öneri/etiket listeleri onsuz düzgün görünmez.
public struct FlowLayout: Layout {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat? = nil) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing ?? spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(into: CGFloat.zero) { total, row in
            total += row.height + (total > 0 ? lineSpacing : 0)
        }
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.width + size.width + (current.indices.isEmpty ? 0 : spacing)

            if !current.indices.isEmpty, projected > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.indices.append(index)
            current.width += size.width + (current.indices.count > 1 ? spacing : 0)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
