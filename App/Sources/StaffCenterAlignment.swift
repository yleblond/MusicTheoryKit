import SwiftUI

/// A custom vertical alignment for lining a sibling (typically a mini keyboard) up on a
/// `ChordStaffView`'s own vertical center specifically — rather than the enclosing `HStack`'s
/// plain `.top`/`.center`, which would align by each column's OVERALL height (stepper/label
/// included), not just the staff itself. Apply `.alignmentGuide(.staffCenter) { $0[.center] }`
/// to both the `ChordStaffView` and whatever should line up with it; any other child of the same
/// `HStack(alignment: .staffCenter)` that doesn't set this guide falls back to ITS OWN vertical
/// center (`defaultValue`), which reads reasonably too when nothing else applies it.
struct StaffCenterAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
}

extension VerticalAlignment {
    static let staffCenter = VerticalAlignment(StaffCenterAlignmentID.self)
}
