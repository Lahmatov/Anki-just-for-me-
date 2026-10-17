import AJFMCore

/// Слова, которые повторяются на каждом втором экране.
///
/// Вынесены, чтобы «Отмена» не переводилась в десяти местах десятью
/// немного разными способами.
enum CommonText {
    static var cancel: String { tr("Отмена", "Cancelar", "Cancel") }
    static var gotIt: String { tr("Понятно", "Entendido", "Got it") }
    static var ok: String { tr("Хорошо", "OK", "OK") }
    static var done: String { tr("Готово", "Feito", "Done") }
    static var close: String { tr("Закрыть", "Fechar", "Close") }
    static var next: String { tr("Дальше", "Seguinte", "Next") }
    static var skip: String { tr("Пропустить", "Saltar", "Skip") }
    static var back: String { tr("Назад", "Voltar", "Back") }
    static var save: String { tr("Сохранить", "Guardar", "Save") }
    static var delete: String { tr("Удалить", "Apagar", "Delete") }
    static var listen: String { tr("Прослушать", "Ouvir", "Listen") }
    static var failedTitle: String { tr("Не получилось", "Não correu bem", "Something went wrong") }
    /// Подпись меню «…» для VoiceOver и Voice Control.
    static var more: String { tr("Ещё", "Mais", "More") }
    static var search: String { tr("Поиск", "Procurar", "Search") }
    static var notSelected: String { tr("Не выбран", "Não escolhido", "Not set") }
}
