//
//  RepasService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service du domaine Repas, branché sur le hub SwiftData. Lit et écrit
/// réellement les `Repas` (fait brut horodaté + ses `Aliment`).
///
/// Pattern de démarrage aligné sur `InjectionsService` : la vue crée le
/// service vide puis lui passe le `ModelContext` de l'environnement via `.task`.
/// Le service garde le contexte, recharge `repas` après chaque mutation et
/// l'expose en `@Observable` pour rafraîchir la vue.
///
/// « Un hub, des dérivations » : le service ne persiste que des faits bruts.
/// La réponse glycémique d'un repas (`Repas.etatAnalyse`) est une dérivation
/// `@Transient` — laissée à `nil` côté hub (aucun assembleur CGM branché pour
/// l'instant).
@Observable
@MainActor
final class RepasService {

    /// Contexte du hub, fourni au démarrage. `nil` tant que `demarrer` n'a pas
    /// été appelé — toutes les opérations sont alors des no-op (dégradation
    /// gracieuse plutôt que crash).
    private var contexte: ModelContext?

    /// Tous les repas du hub, triés par heure ascendante. Rechargé depuis le
    /// store après chaque écriture.
    private(set) var repas: [Repas] = []

    // MARK: - Démarrage

    /// Branche le service sur le contexte du hub et charge les données. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    // MARK: - Lecture par jour

    /// Repas d'un jour donné, triés par heure ascendante.
    func repasDuJour(_ jour: Date) -> [Repas] {
        let cal = Calendar.current
        return repas
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    /// Regroupe les repas d'un jour donné dans les 4 sections canoniques du
    /// journal (« Petit déjeuner », « Déjeuner », « En-cas », « Dîner »), dans
    /// l'ordre attendu par `ListeRepasParSection`. Les sections vides sont
    /// conservées (la vue affiche un état « Aucun repas enregistré »).
    ///
    /// Format identique au tuple historique `[(titre:, repas:)]` consommé par
    /// `JournalVue` / `ListeRepasParSection`, pour brancher la lecture sans
    /// toucher à la signature de ces vues.
    func sectionsDuJour(_ jour: Date) -> [(titre: String, repas: [Repas])] {
        let duJour = repasDuJour(jour)
        return SectionRepas.allCases.map { section in
            (titre: section.titre, repas: duJour.filter { SectionRepas(heure: $0.heure) == section })
        }
    }

    /// Sections du jour courant — raccourci pour le branchement journal.
    var sectionsAujourdhui: [(titre: String, repas: [Repas])] {
        sectionsDuJour(Date())
    }

    /// Nombre de repas (non vides) enregistrés aujourd'hui — alimente le
    /// sous-titre de la carte « Repas » du journal.
    var nombreRepasAujourdhui: Int {
        repasDuJour(Date()).filter { !$0.aliments.isEmpty }.count
    }

    // MARK: - Écriture

    /// Enregistre un repas (création ou édition). **Upsert par `id`** : si un
    /// repas de même `id` existe déjà, il est supprimé puis remplacé (la
    /// relation cascade nettoie ses anciens `Aliment`).
    func enregistrer(_ unRepas: Repas) {
        guard let contexte else { return }
        let cible = unRepas.id
        let descripteur = FetchDescriptor<Repas>(predicate: #Predicate { $0.id == cible })
        if let existant = try? contexte.fetch(descripteur).first, existant !== unRepas {
            contexte.delete(existant)
        }
        contexte.insert(unRepas)
        try? contexte.save()
        recharger()
    }

    /// Construit puis enregistre un repas depuis les entrées de saisie. Point
    /// d'entrée appelé à la validation de `RepasSheet`. Les `EntreeAliment`
    /// (saisie, en grammes, liées à `AlimentCiqual`) sont mappées en `Aliment`
    /// du hub (voir `Aliment.init(depuis:)`).
    ///
    /// Les entrées sans aliment ne produisent rien : on n'enregistre pas un
    /// repas vide.
    @discardableResult
    func enregistrerDepuisSaisie(entrees: [EntreeAliment], heure: Date = Date()) -> Repas? {
        let alimentsHub = entrees.map(Aliment.init(depuis:))
        guard !alimentsHub.isEmpty else { return nil }
        let nouveau = Repas(heure: heure, aliments: alimentsHub)
        enregistrer(nouveau)
        return nouveau
    }

    /// Supprime un repas du hub (ses aliments suivent via la cascade).
    func supprimer(_ unRepas: Repas) {
        guard let contexte else { return }
        contexte.delete(unRepas)
        try? contexte.save()
        recharger()
    }

    // MARK: - Privé

    private func recharger() {
        guard let contexte else { return }
        let descripteur = FetchDescriptor<Repas>(sortBy: [SortDescriptor(\.heure)])
        repas = (try? contexte.fetch(descripteur)) ?? []
    }
}

// MARK: - Mapping EntreeAliment -> Aliment

extension Aliment {

    /// Mappe une entrée de saisie (`EntreeAliment`, liée à `AlimentCiqual`,
    /// quantité en grammes, dose optionnelle) vers l'`Aliment` du hub (forme
    /// déjà résolue, glucides entiers, dose non optionnelle).
    ///
    /// Choix de conversion :
    /// - `emoji` : celui de l'`AlimentCiqual`, ou 🍽 par défaut (le réf. CIQUAL
    ///   a un emoji optionnel).
    /// - `nom` : repris tel quel de l'`AlimentCiqual`.
    /// - `quantite` : grammes consommés, **arrondis** à l'entier le plus proche.
    /// - `glucides` : glucides calculés (proportionnels à la quantité),
    ///   **arrondis** à l'entier le plus proche — l'`Aliment` du hub stocke des
    ///   glucides entiers (précision suffisante, cohérente avec l'affichage).
    /// - `insuline` : `doseInsuline ?? 0` (un aliment logué pour mémoire, sans
    ///   bolus, vaut 0 u).
    convenience init(depuis entree: EntreeAliment) {
        self.init(
            emoji: entree.aliment.emoji ?? "🍽",
            nom: entree.aliment.nom,
            quantite: Int(entree.quantiteGrammes.rounded()),
            glucides: Int(entree.glucides.rounded()),
            insuline: entree.doseInsuline ?? 0
        )
    }
}

// MARK: - Sections de repas (dérivation d'affichage)

/// Les 4 tranches canoniques du journal. Le découpage par heure est
/// **provisoire** (seuils fixes) en attendant le branchement des horaires
/// configurables du profil (`HorairesRepas`). Reste une dérivation d'affichage :
/// le hub ne stocke pas la section, seulement l'heure absolue du repas.
enum SectionRepas: CaseIterable {
    case petitDejeuner
    case dejeuner
    case enCas
    case diner

    /// Libellé exact attendu par `ListeRepasParSection` (mêmes chaînes).
    var titre: String {
        switch self {
        case .petitDejeuner: return "Petit déjeuner"
        case .dejeuner:      return "Déjeuner"
        case .enCas:         return "En-cas"
        case .diner:         return "Dîner"
        }
    }

    /// Classe une heure de repas dans une section. Petit déjeuner < 11h,
    /// déjeuner 11h–14h, dîner ≥ 18h, en-cas le reste (creux de l'après-midi).
    init(heure: Date) {
        let h = Calendar.current.component(.hour, from: heure)
        switch h {
        case ..<11:    self = .petitDejeuner
        case 11..<14:  self = .dejeuner
        case 18...:    self = .diner
        default:       self = .enCas
        }
    }
}

#if DEBUG
extension RepasService {

    /// Container in-memory peuplé pour les `#Preview` — remplace l'ancien jeu
    /// mock du journal. Hors `DEBUG`, l'app démarre sur un hub vide
    /// (dégradation gracieuse → état vide honnête).
    @MainActor
    static var conteneurApercu: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Repas.self, configurations: config)
        for unRepas in echantillonsApercu() {
            container.mainContext.insert(unRepas)
        }
        return container
    }

    /// Jeu de repas de démonstration sur la journée courante (un par section).
    /// Uniquement pour previews / captures. `etatAnalyse` laissé à `nil`
    /// (dérivation non persistée, pas d'assembleur CGM branché).
    static func echantillonsApercu() -> [Repas] {
        let cal = Calendar.current
        func aujourdhui(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        }

        return [
            Repas(
                heure: aujourdhui(7, 30),
                aliments: [
                    Aliment(emoji: "🥣", nom: "Flocons d'avoine", quantite: 80, glucides: 54, insuline: 3.0),
                    Aliment(emoji: "🍌", nom: "Banane", quantite: 120, glucides: 27, insuline: 1.5),
                ]
            ),
            Repas(
                heure: aujourdhui(12, 30),
                aliments: [
                    Aliment(emoji: "🍝", nom: "Pâtes complètes", quantite: 90, glucides: 60, insuline: 3.5),
                    Aliment(emoji: "🥦", nom: "Brocolis vapeur", quantite: 200, glucides: 8, insuline: 0.0),
                ]
            ),
            Repas(
                heure: aujourdhui(16, 0),
                aliments: [
                    Aliment(emoji: "🍪", nom: "Cookie", quantite: 30, glucides: 18, insuline: 0.0),
                ]
            ),
            Repas(
                heure: aujourdhui(19, 45),
                aliments: [
                    Aliment(emoji: "🍚", nom: "Riz basmati", quantite: 70, glucides: 56, insuline: 3.0),
                    Aliment(emoji: "🐟", nom: "Saumon grillé", quantite: 130, glucides: 0, insuline: 0.0),
                ]
            ),
        ]
    }
}
#endif
