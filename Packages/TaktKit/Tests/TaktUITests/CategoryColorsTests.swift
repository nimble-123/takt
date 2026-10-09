import Testing

@testable import TaktUI

struct CategoryColorsTests {

  /// Type badges and the checkmark on color swatches: white text on the light dark-mode
  /// variants had about 1.5:1 (#146).
  @Test
  func labelsOnEveryFillReachFourAndAHalfToOne() {
    let fills = CategoryColors.swatches.flatMap { [$0.hex, $0.dark] } + ["#B91C1C", "#0369A1"]
    for fill in fills {
      #expect(CategoryColors.contrast(CategoryColors.labelHex(on: fill), fill) >= 4.5, "\(fill)")
    }
  }

  @Test
  func contrastMatchesTheWCAGExtremes() {
    #expect(CategoryColors.contrast("#FFFFFF", "#000000") == 21)
    #expect(CategoryColors.contrast("#2563EB", "#2563EB") == 1)
  }

}
