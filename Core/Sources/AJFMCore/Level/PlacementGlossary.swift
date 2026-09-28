import Foundation

/// Значения слов теста — для обратной стороны карточки.
///
/// Тест «знаю / не знаю» честен статистически, но сам человек не видит,
/// правильно ли понял слово. Карточка с переворотом это показывает:
/// сказал «знаю» — посмотри значение и сам скажи, угадал ли. Непонятое
/// слово засчитывается как незнакомое, и оценка становится точнее.
///
/// Значение — самое частое в разговорной речи, а не полный словарь:
/// на карточке оно проверяется одним взглядом.
extension PlacementTest {

    private struct Gloss {
        let ru: String
        let pt: String
        let en: String
    }

    private static let glossary: [String: Gloss] = [
        // 1–1000
        "worry": Gloss(ru: "волноваться; беспокойство", pt: "preocupar-se; preocupação",
                       en: "to feel anxious about something"),
        "laugh": Gloss(ru: "смеяться; смех", pt: "rir; riso",
                       en: "to make sounds because something is funny"),
        "smell": Gloss(ru: "запах; пахнуть, нюхать", pt: "cheiro; cheirar",
                       en: "what you notice with your nose"),
        "lucky": Gloss(ru: "везучий, удачный", pt: "com sorte, sortudo",
                       en: "having good things happen by chance"),
        "afraid": Gloss(ru: "испуганный; бояться", pt: "com medo", en: "feeling fear"),
        "proud": Gloss(ru: "гордый; гордиться", pt: "orgulhoso",
                       en: "pleased about something you or someone close did"),
        // 1001–2000
        "bother": Gloss(ru: "беспокоить, докучать", pt: "incomodar, chatear",
                        en: "to annoy or disturb someone"),
        "afford": Gloss(ru: "позволить себе (по деньгам)", pt: "ter dinheiro para",
                        en: "to have enough money for something"),
        "rough": Gloss(ru: "шершавый, грубый; тяжёлый (день)", pt: "áspero; difícil (dia)",
                       en: "not smooth; difficult or unpleasant"),
        "bottom": Gloss(ru: "дно, низ", pt: "fundo, parte de baixo",
                        en: "the lowest part of something"),
        "brave": Gloss(ru: "смелый, храбрый", pt: "corajoso", en: "ready to face danger or pain"),
        "somehow": Gloss(ru: "как-то, каким-то образом", pt: "de alguma forma",
                         en: "in a way you can't explain"),
        // 2001–4000
        "closet": Gloss(ru: "встроенный шкаф, гардероб", pt: "roupeiro, armário embutido",
                        en: "a small room or cupboard for clothes"),
        "climb": Gloss(ru: "лезть, взбираться", pt: "subir, escalar",
                       en: "to go up using your hands and feet"),
        "steady": Gloss(ru: "устойчивый, ровный", pt: "estável, firme",
                        en: "firm and not shaking; regular"),
        "beard": Gloss(ru: "борода", pt: "barba", en: "hair on a man's chin and cheeks"),
        "freeze": Gloss(ru: "замерзать; замереть", pt: "congelar; ficar imóvel",
                        en: "to turn to ice; to suddenly stop moving"),
        "fence": Gloss(ru: "забор, ограда", pt: "cerca, vedação",
                       en: "a wooden or metal wall around a yard"),
        // 4001–7000
        "fierce": Gloss(ru: "свирепый, яростный", pt: "feroz",
                        en: "violent, aggressive or very strong"),
        "hollow": Gloss(ru: "полый, пустой внутри", pt: "oco", en: "empty inside"),
        "stain": Gloss(ru: "пятно; запачкать", pt: "nódoa, mancha; manchar",
                       en: "a dirty mark that is hard to remove"),
        "faint": Gloss(ru: "слабый, еле заметный; упасть в обморок", pt: "ténue; desmaiar",
                       en: "very weak or unclear; to pass out"),
        "shrimp": Gloss(ru: "креветка", pt: "camarão", en: "a small sea animal you can eat"),
        "sweater": Gloss(ru: "свитер", pt: "camisola", en: "a warm knitted top with sleeves"),
        // 7001–12000
        "vouch": Gloss(ru: "ручаться", pt: "garantir, responder por",
                       en: "to say someone is honest or something is true"),
        "tread": Gloss(ru: "ступать; протектор", pt: "pisar; piso do pneu",
                       en: "to walk or step on something"),
        "conceal": Gloss(ru: "скрывать, прятать", pt: "esconder, ocultar", en: "to hide something"),
        "eerie": Gloss(ru: "жуткий, зловещий", pt: "arrepiante, sinistro",
                       en: "strange and a little frightening"),
        "kettle": Gloss(ru: "чайник", pt: "chaleira", en: "a pot for boiling water"),
        "squeal": Gloss(ru: "визжать; визг", pt: "guinchar; guincho",
                        en: "a long, high-pitched cry"),
        // 12001–20000
        "feisty": Gloss(ru: "задиристый, бойкий", pt: "combativo, destemido",
                        en: "lively, determined and ready to argue"),
        "crafty": Gloss(ru: "хитрый, ловкий", pt: "astuto, manhoso",
                        en: "clever at getting what you want, often by tricks"),
        "quaint": Gloss(ru: "старомодно-милый, причудливый", pt: "pitoresco, antiquado",
                        en: "charming in an old-fashioned way"),
        "solace": Gloss(ru: "утешение", pt: "consolo", en: "comfort when you are sad"),
        "smuggle": Gloss(ru: "провозить контрабандой", pt: "contrabandear",
                         en: "to move goods secretly and illegally"),
        "flattery": Gloss(ru: "лесть", pt: "lisonja, bajulação",
                          en: "praise that is too much or not sincere"),
    ]

    /// Значение настоящего слова теста на нужном языке; у выдумок — nil.
    public static func gloss(for word: String, language: AppLanguage) -> String? {
        guard let gloss = glossary[word] else { return nil }
        switch language {
        case .russian: return gloss.ru
        case .portuguese: return gloss.pt
        case .english: return gloss.en
        }
    }
}
