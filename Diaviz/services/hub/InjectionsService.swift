//
//  InjectionsService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service de la page Médications, branché sur le hub SwiftData. Lit et écrit
/// réellement les `Injection` (remplace `InjectionsServiceMock`).
///
/// Pattern de démarrage aligné sur `HealthKitCGMService` : la vue crée le
/// service vide puis lui passe le `ModelContext` de l'environnement via `.task`.
/// Le service garde le contexte, recharge `injections` après chaque mutation et
/// l'expose en `@Observable` pour rafraîchir la vue.
@Observable
@MainActor
final class InjectionsService {

    /// Contexte du hub, fourni au démarrage. `nil` tant que `demarrer` n'a pas
    /// été appelé — toutes les opérations sont alors des no-op (dégradation
    /// gracieuse plutôt que crash).
    private var contexte: ModelContext?

    /// Toutes les injections du hub, triées par heure ascendante. Rechargé
    /// depuis le store après chaque écriture.
    private(set) var injections: [Injection] = []

    // MARK: - Démarrage

    /// Branche le service sur le contexte du hub et charge les données. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        recharger()
    }

    // MARK: - Lecture par jour

    /// Injections d'un jour donné, triées par heure ascendante.
    func injectionsDuJour(_ jour: Date) -> [Injection] {
        let cal = Calendar.current
        return injections
            .filter { cal.isDate($0.heure, inSameDayAs: jour) }
            .sorted { $0.heure < $1.heure }
    }

    /// Lente du jour donné, s'il y en a une enregistrée.
    func lenteDuJour(_ jour: Date) -> Injection? {
        injectionsDuJour(jour).first { $0.type == .lente }
    }

    /// Nombre d'injections enregistrées aujourd'hui — alimente le sous-titre
    /// de la carte « Médications » du journal.
    var nombreInjectionsAujourdhui: Int {
        injectionsDuJour(Date()).count
    }

    /// Date de la prochaine dose de lente **attendue**, dérivée de la
    /// **dernière injection lente enregistrée** (n'importe quel jour) +
    /// l'intervalle minimum du profil. Adaptatif plutôt qu'ancré sur une
    /// heure fixe chaque jour : si la dernière dose a été prise à 23h10,
    /// la prochaine est attendue à 23h10 + intervalle le lendemain — pas à
    /// une heure de mur figée.
    ///
    /// `nil` si aucune lente n'a jamais été enregistrée — pas d'ancrage
    /// possible tant qu'il n'y a pas de première dose à partir de laquelle
    /// dériver.
    func prochaineLenteAttendue(intervalleHeures: Double) -> Date? {
        let lentes: [Injection] = injections.filter { $0.type == .lente }
        guard let derniere = lentes.max(by: { $0.heure < $1.heure }) else { return nil }
        return derniere.heure.addingTimeInterval(intervalleHeures * 3600)
    }

    // MARK: - Écriture

    /// Enregistre une injection (création ou édition). **Upsert par `id`** : si
    /// une injection de même `id` existe déjà (cas édition — la sheet réémet un
    /// objet détaché avec l'`id` d'origine), elle est remplacée plutôt que
    /// doublonnée.
    /// - Parameter notifier: `false` pour une écriture qui n'est pas une
    ///   saisie utilisateur directe (restauration après annulation) — la
    ///   pilule de confirmation ferait alors doublon avec celle qui vient
    ///   d'être utilisée.
    func enregistrer(_ injection: Injection, notifier: Bool = true) {
        guard let contexte else { return }
        if notifier {
            ToastsService.shared.afficher(
                .insuline,
                titre: "\(injection.type.libelle) enregistrée",
                detail: injection.dose.doseInsulineFormatee
            )
        }
        let cible = injection.id
        let descripteur = FetchDescriptor<Injection>(predicate: #Predicate { $0.id == cible })
        if let existant = try? contexte.fetch(descripteur).first, existant !== injection {
            contexte.delete(existant)
        }
        contexte.insert(injection)
        try? contexte.save()
        recharger()
    }

    /// Supprime une injection du hub, en laissant une porte de sortie.
    ///
    /// Le snapshot est pris **avant** la suppression : une fois l'objet retiré
    /// du contexte, ses propriétés ne sont plus lisibles. La restauration
    /// recrée une injection identique, `id` compris — un repas qui référence
    /// ce bolus (`repasAssocieId`) reste donc correctement relié.
    func supprimer(_ injection: Injection) {
        guard let contexte else { return }
        let copie = Self.copie(de: injection)
        let libelle = "\(injection.type.libelle) supprimée"
        let dose = injection.dose.doseInsulineFormatee
        contexte.delete(injection)
        try? contexte.save()
        recharger()
        ToastsService.shared.afficherSuppression(titre: libelle, detail: dose) { [weak self] in
            self?.enregistrer(copie, notifier: false)
        }
    }

    /// Duplique une injection champ par champ. **À tenir à jour** avec
    /// `Injection.init` : un champ oublié ici serait silencieusement perdu à
    /// la restauration.
    private static func copie(de injection: Injection) -> Injection {
        Injection(
            id: injection.id,
            type: injection.type,
            dose: injection.dose,
            heure: injection.heure,
            zoneInjection: injection.zoneInjection,
            coteInjection: injection.coteInjection,
            note: injection.note,
            glycemieAuMoment: injection.glycemieAuMoment,
            repasAssocieId: injection.repasAssocieId,
            nomMedicament: injection.nomMedicament,
            labelRepas: injection.labelRepas,
            emojiRepas: injection.emojiRepas,
            motif: injection.motif,
            source: injection.source
        )
    }

    // MARK: - Privé

    private func recharger() {
        guard let contexte else { return }
        let descripteur = FetchDescriptor<Injection>(sortBy: [SortDescriptor(\.heure)])
        injections = (try? contexte.fetch(descripteur)) ?? []
    }
}

#if DEBUG
extension InjectionsService {

    /// Container in-memory peuplé pour les `#Preview` — remplace l'ancien jeu
    /// mock. Hors `DEBUG`, l'app démarre sur un hub vide (dégradation gracieuse).
    @MainActor
    static var conteneurApercu: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Injection.self, configurations: config)
        for injection in echantillonsApercu() {
            container.mainContext.insert(injection)
        }
        return container
    }

    /// Jeu d'injections de démonstration sur 7 jours (1 lente/soir, corrections
    /// et bolus repas). Uniquement pour previews / captures.
    static func echantillonsApercu() -> [Injection] {
        let cal = Calendar.current

        func dateA(_ h: Int, _ m: Int = 0, ilYA jours: Int = 0) -> Date {
            let jourBase = cal.date(byAdding: .day, value: -jours, to: Date()) ?? Date()
            return cal.date(bySettingHour: h, minute: m, second: 0, of: jourBase) ?? Date()
        }

        return [
            Injection(type: .rapideCorrection, dose: 0.5, heure: dateA(9, 15),
                      zoneInjection: .ventre, coteInjection: .gauche, glycemieAuMoment: 240),
            Injection(type: .rapideCorrection, dose: 1.5, heure: dateA(13, 0),
                      zoneInjection: .bras, coteInjection: .droite, glycemieAuMoment: 195),
            Injection(type: .rapideRepas, dose: 4.0, heure: dateA(8, 30),
                      zoneInjection: .ventre, coteInjection: .droite,
                      nomMedicament: "NovoRapid", labelRepas: "Petit-déjeuner", emojiRepas: "🍞"),
            Injection(type: .rapideRepas, dose: 6.5, heure: dateA(13, 0),
                      zoneInjection: .ventre, coteInjection: .gauche,
                      nomMedicament: "NovoRapid", labelRepas: "Déjeuner", emojiRepas: "🍝"),
            Injection(type: .rapideRepas, dose: 5.0, heure: dateA(19, 30),
                      zoneInjection: .cuisse, coteInjection: .droite,
                      nomMedicament: "NovoRapid", labelRepas: "Dîner", emojiRepas: "🍚"),

            Injection(type: .lente, dose: 12, heure: dateA(22, 0, ilYA: 1),
                      zoneInjection: .cuisse, coteInjection: .gauche, nomMedicament: "Lantus"),
            Injection(type: .rapideRepas, dose: 5.0, heure: dateA(8, 0, ilYA: 1),
                      zoneInjection: .ventre, coteInjection: .gauche,
                      labelRepas: "Petit-déjeuner", emojiRepas: "🥐"),
            Injection(type: .rapideRepas, dose: 7.0, heure: dateA(12, 45, ilYA: 1),
                      zoneInjection: .ventre, coteInjection: .droite,
                      labelRepas: "Déjeuner", emojiRepas: "🍕"),
            Injection(type: .rapideCorrection, dose: 1.0, heure: dateA(16, 0, ilYA: 1),
                      zoneInjection: .bras, coteInjection: .gauche, glycemieAuMoment: 200),

            Injection(type: .lente, dose: 12, heure: dateA(22, 5, ilYA: 2),
                      zoneInjection: .cuisse, coteInjection: .droite, nomMedicament: "Lantus"),
            Injection(type: .rapideRepas, dose: 5.5, heure: dateA(13, 15, ilYA: 2),
                      zoneInjection: .ventre, coteInjection: .centre,
                      labelRepas: "Déjeuner", emojiRepas: "🥗"),

            Injection(type: .lente, dose: 17.5, heure: dateA(22, 0, ilYA: 3),
                      zoneInjection: .cuisse, coteInjection: .gauche, nomMedicament: "Lantus"),
            Injection(type: .rapideCorrection, dose: 2.0, heure: dateA(17, 30, ilYA: 3),
                      zoneInjection: .cuisse, coteInjection: .droite, glycemieAuMoment: 270),

            Injection(type: .lente, dose: 12, heure: dateA(21, 50, ilYA: 4),
                      zoneInjection: .fesse, coteInjection: .droite, nomMedicament: "Lantus"),
            Injection(type: .lente, dose: 12, heure: dateA(22, 10, ilYA: 5),
                      zoneInjection: .cuisse, coteInjection: .gauche, nomMedicament: "Lantus"),
            Injection(type: .lente, dose: 12, heure: dateA(22, 0, ilYA: 6),
                      zoneInjection: .cuisse, coteInjection: .droite, nomMedicament: "Lantus"),
        ]
    }
}
#endif
