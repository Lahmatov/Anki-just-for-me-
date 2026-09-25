import Foundation

/// Карточки, которые проваливаются снова и снова.
///
/// В Anki их называют «пиявками» — они съедают непропорционально много
/// времени. Держать их в общей очереди бессмысленно: если слово забыто
/// восемь раз, девятый повтор той же карточки ничего не изменит.
/// Менять надо саму карточку, а не расписание.
public enum LeechPolicy {

    /// Порог, после которого карточка считается проблемной.
    public static let defaultThreshold = 5

    public static func isLeech(lapses: Int, threshold: Int = defaultThreshold) -> Bool {
        lapses >= threshold
    }

    /// Насколько всё плохо — по этому сортируется список трудных.
    public static func severity(lapses: Int, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        return Double(lapses) / Double(reps)
    }

    /// Что конкретно делать с такой карточкой.
    ///
    /// Советы разные, потому что причины разные: слово без контекста,
    /// слишком длинная фраза, два похожих слова, которые путаются между собой.
    public static func advice(lapses: Int, hasExample: Bool, termWordCount: Int) -> String {
        if !hasExample {
            return tr("Добавь пример из сериала: слово без контекста почти не держится "
                        + "в памяти. Кинь субтитры в набор — примеры подставятся сами.",
                      "Junta um exemplo da série: uma palavra sem contexto quase não fica "
                        + "na memória. Adiciona legendas ao baralho e os exemplos entram sozinhos.",
                      "Add an example from the show: a word without context barely sticks. "
                        + "Drop subtitles into the deck and examples fill in by themselves.")
        }
        if termWordCount > 4 {
            return tr("Фраза длинная. Разбей её на части или оставь ключевое слово — "
                        + "целиком такие конструкции почти не запоминаются.",
                      "A frase é longa. Divide-a em partes ou deixa só a palavra-chave — "
                        + "construções inteiras assim quase não se memorizam.",
                      "The phrase is long. Split it up or keep just the key word — "
                        + "whole constructions like this rarely stick.")
        }
        if lapses >= 10 {
            return tr("Десять провалов — карточка не работает. Перепиши её своими словами, "
                        + "придумай мнемонику или временно отложи: это слово пока не твоё.",
                      "Dez falhas — o cartão não funciona. Reescreve-o por palavras tuas, "
                        + "inventa uma mnemónica ou põe-no de parte: esta palavra ainda não é tua.",
                      "Ten lapses — the card isn't working. Rewrite it in your own words, "
                        + "make up a mnemonic or set it aside: this word isn't yours yet.")
        }
        return tr("Проверь, не путается ли оно с похожим словом. Если да — заведи "
                    + "карточку с обоими сразу, чтобы разница была видна.",
                  "Vê se não a confundes com uma palavra parecida. Se sim, cria "
                    + "um cartão com as duas, para a diferença ficar à vista.",
                  "Check whether it gets mixed up with a similar word. If so, make "
                    + "a card with both, so the difference is visible.")
    }

    /// Формулировка для экрана.
    public static func summary(lapses: Int) -> String {
        tr("Забыто ", "Esquecida ", "Forgotten ") + Counted.times(lapses)
    }
}
