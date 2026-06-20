//
//  IOBService.swift
//  diaviz
//

import Foundation
import Observation
import SwiftData

/// Service d'IOB (Insulin On Board) pour l'accueil — **dérivation** branchée sur
/// le hub. Lit les injections rapides récentes et applique `IOBCalculateur` avec
/// la DIA du profil. Rien n'est persisté ; tout est recalculé à `rafraichir()`.
///
/// L'IOB décroît avec le temps : on recalcule à chaque apparition de l'accueil
/// (pas de timer temps réel en V1 — la valeur est fraîche à l'ouverture).
@Observable
@MainActor
final class IOBService {

    private var contexte: ModelContext?

    /// IOB total à l'instant du dernier `rafraichir()` (unités).
    private(set) var iobCourant: Double = 0

    /// Courbe de décroissance projetée sur 6h — alimente la mini-courbe de la carte.
    private(set) var courbe: [PointIOB] = []

    /// Branche le service sur le hub et calcule une première fois. Idempotent.
    func demarrer(contexte: ModelContext) {
        guard self.contexte == nil else { return }
        self.contexte = contexte
        rafraichir()
    }

    /// Recalcule l'IOB courant + la courbe depuis les injections rapides du hub
    /// tombant dans la fenêtre DIA (au-delà, l'insuline est consommée).
    func rafraichir() {
        guard let contexte else { return }
        let profil = ProfilService.shared.profil
        let dia = profil.dureeActionInsulineHeures
        let pic = profil.insulineRapide.picActionMinutes
        let depuis = Date().addingTimeInterval(-dia * 3600)
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= depuis }
        )
        // Le filtre « rapide » se fait en Swift : comparer un enum dans un
        // #Predicate SwiftData est fragile, et le volume est trivial.
        let rapides = ((try? contexte.fetch(descripteur)) ?? [])
            .filter { $0.type != .lente }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }

        let maintenant = Date()
        iobCourant = IOBCalculateur.iob(a: maintenant, injections: rapides, diaHeures: dia, picMinutes: pic)
        courbe = IOBCalculateur.courbe(injections: rapides, depuis: maintenant, diaHeures: dia, picMinutes: pic)
    }

    /// IOB actif **juste avant** `instant`, calculé depuis les injections rapides
    /// du hub antérieures à cet instant. Sert à figer le `iobAuDebut` d'un repas
    /// ou d'une activité à la saisie (snapshot du contexte au moment du fait).
    static func iobDuHub(a instant: Date, contexte: ModelContext) -> Double {
        let profil = ProfilService.shared.profil
        let dia = profil.dureeActionInsulineHeures
        let pic = profil.insulineRapide.picActionMinutes
        let depuis = instant.addingTimeInterval(-dia * 3600)
        let descripteur = FetchDescriptor<Injection>(
            predicate: #Predicate { $0.heure >= depuis && $0.heure < instant }
        )
        let rapides = ((try? contexte.fetch(descripteur)) ?? [])
            .filter { $0.type != .lente }
            .map { InjectionPourIOB(heure: $0.heure, dose: $0.dose) }
        return IOBCalculateur.iob(a: instant, injections: rapides, diaHeures: dia, picMinutes: pic)
    }
}
