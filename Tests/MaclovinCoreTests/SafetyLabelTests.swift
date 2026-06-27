import MaclovinCore
import Testing

@Test
func riskLabelsAreHumanReadable() {
    #expect(Risk.low.label == "Low")
    #expect(Risk.medium.label == "Medium")
    #expect(Risk.high.label == "High")
}

@Test
func confidenceLabelsAreHumanReadable() {
    #expect(Confidence.high.label == "High")
    #expect(Confidence.medium.label == "Medium")
    #expect(Confidence.low.label == "Low")
}
