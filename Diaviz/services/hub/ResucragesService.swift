//
//  ResucragesService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service de la page Resucrage, branché sur le hub SwiftData. Même pattern
/// de démarrage que `ActivitesSportService`/`InjectionsService` : la vue
/// crée le service vide puis lui passe le `ModelContext` via `.task`.
@Observable
@MainActor
final class ResucragesService {

    private var contexte: ModelContext?

    /// Snapshots d'affichage, triés par date décroissante (le plus récent en
    /// tête). **Value types** — les vues ne reçoivent jamais le `@Model`,
    /// voir `ResucrageAffiche` pour le pourquoi (crash à la suppression).
    private(set) var resucrages: [ResucrageAffiche] = []

    /// Idempotent sur le contexte (branché une seule fois), mais **recharge
    /// toujours** — appelée aussi depuis `.onAppear` du Journal pour refléter
    /// les resucrages ajoutés/supprimés depuis une autre instance du service
    /// (la page Resucrage a la sienne, pas de partage via environnement).
    func demarrer(contexte: ModelContext) {
        if self.contexte == nil { self.contexte = contexte }
        recharger()
    }

    /// Resucrages d'un jour donné, triés par heure ascendante.
    func resucragesDuJour(_ jour: Date) -> [ResucrageAffiche] {
        let cal = Calendar.current
        return resucrages
            .filter { cal.isDate($0.date, inSameDayAs: jour) }
            .sorted { $0.date < $1.date }
    }

    /// Alimente le sous-titre de la carte « Resucrage » du journal.
    var nombreResucragesAujourdhui: Int {
        resucragesDuJour(Date()).count
    }

    /// Le plus récent, tous jours confondus — `resucrages` est déjà trié
    /// décroissant. Alimente `CarteResucrageRecent` (page dédiée + accueil).
    var dernierResucrage: ResucrageAffiche? {
        resucrages.first
    }

    /// - Parameter notifier: `false` pour une restauration après annulation —
    ///   la pilule ferait doublon avec celle qui vient d'être utilisée.
    func enregistrer(_ resucrage: Resucrage, notifier: Bool = true) {
        guard let contexte else { return }
        if notifier {
            ToastsService.shared.afficher(
                .resucrage,
                titre: "Resucrage enregistré",
                detail: "\(resucrage.glucidesTotal) g"
            )
        }
        contexte.insert(resucrage)
        try? contexte.save()
        recharger()
    }

    /// Suppression par `id` — la vue ne détient qu'un snapshot, jamais le
    /// `@Model`. On retire d'abord le snapshot de la liste observable (la row
    /// disparaît proprement, sans jamais relire un objet invalidé), puis on
    /// supprime réellement côté SwiftData.
    func supprimer(_ id: UUID) {
        guard let contexte else { return }
        resucrages.removeAll { $0.id == id }
        let descripteur = FetchDescriptor<Resucrage>(predicate: #Predicate { $0.id == id })
        guard let objet = try? contexte.fetch(descripteur).first else { return }
        let copie = Self.copie(de: objet)
        let detail = "\(objet.glucidesTotal) g"
        contexte.delete(objet)
        try? contexte.save()
        ToastsService.shared.afficherSuppression(titre: "Resucrage supprimé", detail: detail) { [weak self] in
            self?.enregistrer(copie, notifier: false)
        }
    }

    /// Duplique un resucrage, ses aliments compris — un `Aliment` ne peut
    /// appartenir qu'à un parent à la fois, la restauration repart donc de
    /// copies. **À tenir à jour** avec `Resucrage.init`.
    private static func copie(de resucrage: Resucrage) -> Resucrage {
        Resucrage(
            id: resucrage.id,
            date: resucrage.date,
            intention: resucrage.intention,
            aliments: resucrage.aliments.map { aliment in
                Aliment(
                    id: aliment.id, emoji: aliment.emoji, nom: aliment.nom,
                    quantite: aliment.quantite, glucides: aliment.glucides,
                    insuline: aliment.insuline, imageURL: aliment.imageURL,
                    resucrage: aliment.resucrage, idCiqualSource: aliment.idCiqualSource
                )
            },
            glycemieCible: resucrage.glycemieCible
        )
    }

    private func recharger() {
        guard let contexte else { return }
        let descripteur = FetchDescriptor<Resucrage>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let objets = (try? contexte.fetch(descripteur)) ?? []
        resucrages = objets.map(\.affichage)
    }
}

#if DEBUG
extension ResucragesService {
    @MainActor
    static var conteneurApercu: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Resucrage.self, configurations: config)
        for resucrage in echantillonsApercu() {
            container.mainContext.insert(resucrage)
        }
        return container
    }

    @MainActor
    static func apercu() -> ResucragesService {
        let service = ResucragesService()
        service.demarrer(contexte: conteneurApercu.mainContext)
        return service
    }

    static func echantillonsApercu() -> [Resucrage] {
        let cal = Calendar.current
        func dateA(_ h: Int, _ m: Int = 0, ilYA jours: Int = 0) -> Date {
            let jourBase = cal.date(byAdding: .day, value: -jours, to: Date()) ?? Date()
            return cal.date(bySettingHour: h, minute: m, second: 0, of: jourBase) ?? Date()
        }

        return [
            Resucrage(
                date: dateA(17, 20),
                intention: .correctifHypo,
                aliments: [.collationGenerique(glucidesGrammes: 15)]
            ),
            Resucrage(
                date: dateA(7, 35, ilYA: 1),
                intention: .preventifMaintien,
                aliments: [.collationGenerique(glucidesGrammes: 12)],
                glycemieCible: 140
            ),
            Resucrage(
                date: dateA(18, 50, ilYA: 2),
                intention: .preventifAntiChute,
                aliments: [.collationGenerique(glucidesGrammes: 8)]
            ),
        ]
    }
}
#endif
