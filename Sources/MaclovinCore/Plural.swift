/// Counts written out in prose.
///
/// Reports state counts in sentences often enough — batch titles, history
/// headlines, ambiguity errors — that "1 candidates" would show up in the one
/// place a user is being asked to confirm something.
public enum Plural {
    public static func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number) \(number == 1 ? singular : plural ?? singular + "s")"
    }
}
