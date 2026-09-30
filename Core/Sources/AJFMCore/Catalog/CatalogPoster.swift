import Foundation

/// Обложка для готового набора: какой из результатов поиска TVMaze —
/// «тот самый» сериал каталога.
public enum CatalogPoster {
    /// Первый результат с постером, тем же названием и годом премьеры.
    /// Год допускается ±1: пилот нередко выходит годом раньше сезона. Без
    /// года с любой стороны решает название. Так британский «The Office»
    /// 2001 года не подменит американский 2005-го, а «Lost Girl» — «Lost».
    public static func pick(_ results: [TVMaze.Show], name: String, year: Int?) -> TVMaze.Show? {
        let wanted = normalized(name)
        guard !wanted.isEmpty else { return nil }
        return results.first { show in
            guard show.posterURL != nil, normalized(show.name) == wanted else { return false }
            guard let year, let premiered = show.premieredYear else { return true }
            return abs(premiered - year) <= 1
        }
    }

    /// Название без регистра, пробелов и знаков: «Grey's Anatomy» и
    /// «Greys Anatomy» — одно и то же.
    static func normalized(_ name: String) -> String {
        String(String.UnicodeScalarView(
            name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }
}
