import XCTest
@testable import AJFMCore

/// Формы сверены с таблицами спряжения (Priberam для португальского,
/// Treccani для итальянского): ошибка здесь — ошибка, выученная человеком.
final class ConjugatorTests: XCTestCase {

    private func forms(_ verb: String, _ language: StudyLanguage, _ tense: Tense = .present,
                       file: StaticString = #filePath, line: UInt = #line) -> [String] {
        guard let conjugation = Conjugator.conjugate(verb, language: language, tense: tense) else {
            XCTFail("\(verb) не спрягается", file: file, line: line)
            return []
        }
        return conjugation.forms.map(\.form)
    }

    // MARK: - Португальский: настоящее

    func testPortugueseRegularPresent() {
        XCTAssertEqual(forms("falar", .portuguese), ["falo", "falas", "fala", "falamos", "falam"])
        XCTAssertEqual(forms("comer", .portuguese), ["como", "comes", "come", "comemos", "comem"])
        XCTAssertEqual(forms("partir", .portuguese), ["parto", "partes", "parte", "partimos", "partem"])
    }

    func testPortugueseSpellingOfTheFirstPerson() {
        XCTAssertEqual(forms("conhecer", .portuguese).first, "conheço")
        XCTAssertEqual(forms("proteger", .portuguese).first, "protejo")
        XCTAssertEqual(forms("dirigir", .portuguese).first, "dirijo")
        XCTAssertEqual(forms("distinguir", .portuguese), ["distingo", "distingues", "distingue",
                                                          "distinguimos", "distinguem"])
    }

    func testPortugueseStemChangeOnlyInTheFirstPerson() {
        XCTAssertEqual(forms("dormir", .portuguese), ["durmo", "dormes", "dorme", "dormimos", "dormem"])
        XCTAssertEqual(forms("seguir", .portuguese), ["sigo", "segues", "segue", "seguimos", "seguem"])
    }

    func testPortugueseEarAndUirVerbs() {
        XCTAssertEqual(forms("passear", .portuguese),
                       ["passeio", "passeias", "passeia", "passeamos", "passeiam"])
        XCTAssertEqual(forms("incluir", .portuguese),
                       ["incluo", "incluis", "inclui", "incluímos", "incluem"])
    }

    func testPortugueseIrregularPresent() {
        XCTAssertEqual(forms("ser", .portuguese), ["sou", "és", "é", "somos", "são"])
        XCTAssertEqual(forms("ter", .portuguese), ["tenho", "tens", "tem", "temos", "têm"])
        XCTAssertEqual(forms("ir", .portuguese), ["vou", "vais", "vai", "vamos", "vão"])
        XCTAssertEqual(forms("pôr", .portuguese), ["ponho", "pões", "põe", "pomos", "põem"])
    }

    /// Европейская энклиза: местоимение после глагола, у «nós» выпадает s.
    func testPortugueseReflexiveVerbsTakeThePronounAfter() {
        XCTAssertEqual(forms("levantar-se", .portuguese),
                       ["levanto-me", "levantas-te", "levanta-se", "levantamo-nos", "levantam-se"])
    }

    // MARK: - Португальский: pretérito perfeito

    /// «falámos» с ударением — норма Португалии; без него — бразильская.
    func testPortugueseRegularPastIsEuropean() {
        XCTAssertEqual(forms("falar", .portuguese, .past),
                       ["falei", "falaste", "falou", "falámos", "falaram"])
        XCTAssertEqual(forms("comer", .portuguese, .past),
                       ["comi", "comeste", "comeu", "comemos", "comeram"])
        XCTAssertEqual(forms("partir", .portuguese, .past),
                       ["parti", "partiste", "partiu", "partimos", "partiram"])
    }

    func testPortuguesePastSpellingOfTheFirstPerson() {
        XCTAssertEqual(forms("ficar", .portuguese, .past).first, "fiquei")
        XCTAssertEqual(forms("chegar", .portuguese, .past).first, "cheguei")
        XCTAssertEqual(forms("começar", .portuguese, .past).first, "comecei")
        XCTAssertEqual(forms("seguir", .portuguese, .past).first, "segui")
    }

    func testPortugueseIrregularPast() {
        XCTAssertEqual(forms("fazer", .portuguese, .past), ["fiz", "fizeste", "fez", "fizemos", "fizeram"])
        XCTAssertEqual(forms("ir", .portuguese, .past), ["fui", "foste", "foi", "fomos", "foram"])
        XCTAssertEqual(forms("incluir", .portuguese, .past),
                       ["incluí", "incluíste", "incluiu", "incluímos", "incluíram"])
    }

    func testPortugueseReflexivePast() {
        XCTAssertEqual(forms("levantar-se", .portuguese, .past),
                       ["levantei-me", "levantaste-te", "levantou-se", "levantámo-nos", "levantaram-se"])
    }

    func testPortuguesePhraseConjugatesTheVerbOnly() {
        XCTAssertEqual(forms("ter saudades", .portuguese).first, "tenho saudades")
        XCTAssertEqual(Conjugator.conjugate("ter saudades", language: .portuguese, tense: .present)?.verb,
                       "ter saudades")
    }

    /// Чего правило не знает — не придумывает.
    func testPortugueseUnknownWordsAreRefused() {
        for word in ["atrair", "o comboio", "telemóvel", "a", "", "  ", "x1ar", "pre-ver-se"] {
            XCTAssertNil(Conjugator.conjugate(word, language: .portuguese, tense: .present), word)
        }
    }

    // MARK: - Итальянский

    func testItalianRegularPresent() {
        XCTAssertEqual(forms("parlare", .italian),
                       ["parlo", "parli", "parla", "parliamo", "parlate", "parlano"])
        XCTAssertEqual(forms("leggere", .italian),
                       ["leggo", "leggi", "legge", "leggiamo", "leggete", "leggono"])
        XCTAssertEqual(forms("dormire", .italian),
                       ["dormo", "dormi", "dorme", "dormiamo", "dormite", "dormono"])
    }

    func testItalianSpellingKeepsTheSound() {
        XCTAssertEqual(forms("cercare", .italian),
                       ["cerco", "cerchi", "cerca", "cerchiamo", "cercate", "cercano"])
        XCTAssertEqual(forms("pagare", .italian)[3], "paghiamo")
        XCTAssertEqual(forms("mangiare", .italian),
                       ["mangio", "mangi", "mangia", "mangiamo", "mangiate", "mangiano"])
    }

    func testItalianIscVerbs() {
        XCTAssertEqual(forms("capire", .italian),
                       ["capisco", "capisci", "capisce", "capiamo", "capite", "capiscono"])
    }

    func testItalianIrregularPresent() {
        XCTAssertEqual(forms("essere", .italian), ["sono", "sei", "è", "siamo", "siete", "sono"])
        XCTAssertEqual(forms("andare", .italian),
                       ["vado", "vai", "va", "andiamo", "andate", "vanno"])
    }

    func testItalianPassatoProssimoWithAvere() {
        XCTAssertEqual(forms("parlare", .italian, .past),
                       ["ho parlato", "hai parlato", "ha parlato", "abbiamo parlato",
                        "avete parlato", "hanno parlato"])
        XCTAssertEqual(forms("vendere", .italian, .past).first, "ho venduto")
        XCTAssertEqual(forms("dormire", .italian, .past).first, "ho dormito")
    }

    func testItalianIrregularParticiples() {
        XCTAssertEqual(forms("fare", .italian, .past).first, "ho fatto")
        XCTAssertEqual(forms("leggere", .italian, .past).first, "ho letto")
        XCTAssertEqual(forms("vedere", .italian, .past).first, "ho visto")
        XCTAssertEqual(forms("conoscere", .italian, .past).first, "ho conosciuto")
    }

    /// С essere причастие согласуется с подлежащим: andato — andati.
    func testItalianEssereVerbsAgree() {
        XCTAssertEqual(forms("andare", .italian, .past),
                       ["sono andato", "sei andato", "è andato", "siamo andati",
                        "siete andati", "sono andati"])
    }

    func testItalianReflexiveVerbs() {
        XCTAssertEqual(forms("alzarsi", .italian),
                       ["mi alzo", "ti alzi", "si alza", "ci alziamo", "vi alzate", "si alzano"])
        XCTAssertEqual(forms("alzarsi", .italian, .past),
                       ["mi sono alzato", "ti sei alzato", "si è alzato", "ci siamo alzati",
                        "vi siete alzati", "si sono alzati"])
    }

    func testItalianPhrase() {
        XCTAssertEqual(forms("fare la spesa", .italian).first, "faccio la spesa")
    }

    func testItalianUnknownWordsAreRefused() {
        for word in ["la casa", "produrre", "il treno", "bello"] {
            XCTAssertNil(Conjugator.conjugate(word, language: .italian, tense: .present), word)
        }
    }

    // MARK: - Английский

    func testEnglishPresent() {
        XCTAssertEqual(forms("go", .english), ["go", "go", "goes", "go", "go"])
        XCTAssertEqual(forms("watch", .english)[2], "watches")
        XCTAssertEqual(forms("study", .english)[2], "studies")
        XCTAssertEqual(forms("play", .english)[2], "plays")
        XCTAssertEqual(forms("have", .english)[2], "has")
        XCTAssertEqual(forms("be", .english), ["am", "are", "is", "are", "are"])
    }

    func testEnglishPast() {
        XCTAssertEqual(forms("go", .english, .past).first, "went")
        XCTAssertEqual(forms("be", .english, .past), ["was", "were", "was", "were", "were"])
        XCTAssertEqual(forms("stop", .english, .past).first, "stopped")
        XCTAssertEqual(forms("study", .english, .past).first, "studied")
        XCTAssertEqual(forms("play", .english, .past).first, "played")
        XCTAssertEqual(forms("like", .english, .past).first, "liked")
        XCTAssertEqual(forms("visit", .english, .past).first, "visited")
        XCTAssertEqual(forms("open", .english, .past).first, "opened")
        XCTAssertEqual(forms("rain", .english, .past).first, "rained")
    }

    func testEnglishPhrasalVerbAndInfinitiveParticle() {
        XCTAssertEqual(forms("get up", .english, .past).first, "got up")
        XCTAssertEqual(forms("get up", .english)[2], "gets up")
        XCTAssertEqual(forms("to work", .english, .past).first, "worked")
    }

    func testEnglishRefusesNonWords() {
        XCTAssertNil(Conjugator.conjugate("check-in", language: .english, tense: .past))
        XCTAssertNil(Conjugator.conjugate("", language: .english, tense: .past))
    }

    // MARK: - Общее

    func testEveryFormHasItsPerson() {
        for language in StudyLanguage.allCases {
            let verb = ["en": "work", "pt-PT": "falar", "it": "parlare"][language.rawValue]!
            for tense in Tense.allCases {
                let conjugation = Conjugator.conjugate(verb, language: language, tense: tense)
                XCTAssertEqual(conjugation?.forms.map(\.person), Conjugator.persons(for: language))
            }
        }
    }

    func testCaseAndSpacesDoNotMatter() {
        XCTAssertEqual(forms("  Falar ", .portuguese).first, "falo")
    }
}
