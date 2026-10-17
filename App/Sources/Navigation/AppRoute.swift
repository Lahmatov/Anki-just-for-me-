import Foundation
import SwiftData
import AJFMCore

/// Все экраны, куда можно перейти внутри вкладки или листа (навык
/// ios-architecture, правило 2). Значение маршрута лежит в `NavigationPath`,
/// поэтому в нём только `Hashable`-данные: идентификаторы записей SwiftData,
/// а не сами записи, и никаких замыканий.
enum AppRoute: Hashable {
    // Сегодня и прогресс
    case rewards
    case stats
    case difficultCards
    case journeyMap
    case lessonsMap

    // Слова и наборы
    case search
    case note(PersistentIdentifier)
    case deck(PersistentIdentifier)
    case folder(PersistentIdentifier)
    /// Повторение: набора нет — общая очередь на сегодня.
    case review(deck: PersistentIdentifier?, limit: Int? = nil)

    // Уроки
    case lesson(PersistentIdentifier)
    case lessonDrill(PersistentIdentifier, DrillMode)
    case conjugation(verbs: [String])
    case lessonQuiz(PersistentIdentifier)
    case lessonSpeak(PersistentIdentifier)
    case lessonChat(PersistentIdentifier, retelling: String? = nil)

    // Сериалы
    case show(PersistentIdentifier)
    case episode(show: PersistentIdentifier, EpisodeContext)
    case episodeRecap(show: PersistentIdentifier, EpisodeContext)
    /// Пересказ серии; без серии — свободный пересказ.
    case retell(EpisodeContext?)
    case episodeChat(EpisodeContext, retelling: String? = nil)
    case catalogShow(resource: String)
    case minimalPairs
    case youglish(word: String)

    // Профиль, настройки, помощь
    case account
    case plus
    case aiKeys
    case cloudBackup
    case log
    case serverData
    case privacy
    case sellerInfo
    case legal(LegalDocument.Kind)
    case help
    case whySeries
    case supportTicket
    case supportTickets
}
