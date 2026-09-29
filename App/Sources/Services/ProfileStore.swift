import Foundation
import UIKit
import Observation
import AJFMCore

/// Профиль: имя и аватарка.
///
/// Всё это живёт только на телефоне — на сервер не уходит ни имя, ни фото.
/// Серверу они не нужны: доступ к подписке связывает вход через Apple, а
/// не имя. Фото людей на сервере — это отдельное хранилище, отдельные
/// сроки и отдельный риск утечки ради картинки размером с ноготь.
@Observable
@MainActor
final class ProfileStore {
    static let shared = ProfileStore()

    enum Avatar: Equatable {
        case initials
        case photo
        case mascot(MascotMood)

        /// В UserDefaults: nil — инициалы, «photo», «mascot:hello».
        var stored: String? {
            switch self {
            case .initials: return nil
            case .photo: return "photo"
            case .mascot(let mood): return "mascot:" + mood.rawValue
            }
        }

        init(stored: String?) {
            if stored == "photo" {
                self = .photo
            } else if let stored, stored.hasPrefix("mascot:"),
                      let mood = MascotMood(rawValue: String(stored.dropFirst("mascot:".count))) {
                self = .mascot(mood)
            } else {
                self = .initials
            }
        }
    }

    enum Failure: LocalizedError {
        case unreadableImage

        var errorDescription: String? {
            tr("Не получилось открыть это фото. Попробуй другое.",
               "Não foi possível abrir esta foto. Tenta outra.",
               "Couldn't open this photo. Try another one.")
        }
    }

    private let defaults: UserDefaults
    private let directory: URL?

    private(set) var name: String
    private(set) var avatar: Avatar
    private(set) var photo: UIImage?

    init(defaults: UserDefaults = .standard, directory: URL? = ProfileStore.defaultDirectory) {
        self.defaults = defaults
        self.directory = directory
        name = defaults.string(forKey: SettingsKey.profileName) ?? ""
        avatar = Avatar(stored: defaults.string(forKey: SettingsKey.profileAvatar))
        photo = nil
        if avatar == .photo {
            photo = photoURL.flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
            // Файл пропал (восстановление из бэкапа без него) — не показываем пустоту.
            if photo == nil { setAvatar(.initials) }
        }
    }

    /// Application Support/Profile — не «Документы»: фото не должно
    /// появляться в приложении «Файлы» рядом с бэкапами наборов.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Profile", directoryHint: .isDirectory)
    }

    private var photoURL: URL? { directory?.appending(path: "avatar.jpg") }

    var initials: String { ProfileName.initials(name) }

    // MARK: - Имя

    func setName(_ raw: String) {
        name = ProfileName.clean(raw)
        if name.isEmpty {
            defaults.removeObject(forKey: SettingsKey.profileName)
        } else {
            defaults.set(name, forKey: SettingsKey.profileName)
        }
    }

    /// Имя из входа через Apple — только если своё ещё не задано.
    func adoptName(givenName: String?, familyName: String?) {
        guard name.isEmpty, let full = ProfileName.from(givenName: givenName, familyName: familyName) else {
            return
        }
        setName(full)
    }

    // MARK: - Аватарка

    func setMascot(_ mood: MascotMood) {
        removePhotoFile()
        setAvatar(.mascot(mood))
    }

    /// Фото из галереи: квадрат по центру, не больше 512 пикселей, JPEG.
    /// Оригинал не хранится — только маленькая копия.
    func setPhoto(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw Failure.unreadableImage }
        let pixelWidth = Double(image.size.width * image.scale)
        let pixelHeight = Double(image.size.height * image.scale)
        guard let square = AvatarGeometry.centerSquare(width: pixelWidth, height: pixelHeight),
              let url = photoURL, let directory else {
            throw Failure.unreadableImage
        }
        let side = AvatarGeometry.outputSide(for: square.side)
        let factor = side / square.side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { _ in
                // Рисуем весь снимок так, чтобы центральный квадрат лёг ровно в холст.
                image.draw(in: CGRect(x: -square.x * factor, y: -square.y * factor,
                                      width: pixelWidth * factor, height: pixelHeight * factor))
            }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { throw Failure.unreadableImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        photo = scaled
        setAvatar(.photo)
    }

    /// Убрать фото или лося — вернуться к инициалам.
    func resetAvatar() {
        removePhotoFile()
        setAvatar(.initials)
    }

    private func setAvatar(_ value: Avatar) {
        avatar = value
        if let stored = value.stored {
            defaults.set(stored, forKey: SettingsKey.profileAvatar)
        } else {
            defaults.removeObject(forKey: SettingsKey.profileAvatar)
        }
    }

    private func removePhotoFile() {
        photo = nil
        if let url = photoURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Удаление

    /// Часть «Удалить все данные»: папка профиля целиком. Настройки
    /// (имя, выбор аватарки) стираются вместе с остальными UserDefaults.
    static func eraseLocal(directory: URL? = defaultDirectory, fileManager: FileManager = .default) {
        if let directory { try? fileManager.removeItem(at: directory) }
    }

    /// После «Удалить все данные» — забыть и то, что уже в памяти.
    func reload() {
        name = defaults.string(forKey: SettingsKey.profileName) ?? ""
        avatar = Avatar(stored: defaults.string(forKey: SettingsKey.profileAvatar))
        photo = avatar == .photo
            ? photoURL.flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
            : nil
        if avatar == .photo, photo == nil { setAvatar(.initials) }
    }
}
