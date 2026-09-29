import Foundation

/// Имя в профиле. Живёт только на телефоне: серверу имя не нужно, и то,
/// чего у него нет, не может утечь.
public enum ProfileName {

    public static let maxLength = 40

    /// Чистое имя: без пробелов по краям и двойных пробелов, не длиннее
    /// `maxLength` — длинное имя ломает шапку профиля.
    public static func clean(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(words.joined(separator: " ").prefix(maxLength))
    }

    /// Имя из данных входа через Apple. Apple отдаёт имя только при самом
    /// первом входе — поэтому его и надо сохранить сразу.
    public static func from(givenName: String?, familyName: String?) -> String? {
        let joined = clean([givenName, familyName].compactMap { $0 }.joined(separator: " "))
        return joined.isEmpty ? nil : joined
    }

    /// Инициалы для аватарки без фото: первые буквы первых двух слов.
    /// Слова без букв (эмодзи, цифры) пропускаются.
    public static func initials(_ name: String) -> String {
        let letters = clean(name)
            .split(separator: " ")
            .compactMap { word in word.first(where: { $0.isLetter }) }
            .prefix(2)
        return String(letters).uppercased()
    }
}

/// Геометрия аватарки: из любого фото — квадрат по центру, уменьшенный
/// до разумного размера. Большое фото с камеры весит мегабайты, а на
/// экране аватарка — 90 точек.
public enum AvatarGeometry {

    public struct Square: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var side: Double

        public init(x: Double, y: Double, side: Double) {
            self.x = x
            self.y = y
            self.side = side
        }
    }

    /// Сторона сохранённой аватарки в пикселях: хватает на @3x.
    public static let maxSide = 512.0

    /// Центральный квадрат фото. Пустое или битое изображение — nil.
    public static func centerSquare(width: Double, height: Double) -> Square? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let side = min(width, height)
        return Square(x: (width - side) / 2, y: (height - side) / 2, side: side)
    }

    /// До какого размера уменьшить квадрат. Маленькие не увеличиваются.
    public static func outputSide(for side: Double) -> Double {
        guard side.isFinite, side > 0 else { return 0 }
        return min(side, maxSide).rounded(.down)
    }
}
