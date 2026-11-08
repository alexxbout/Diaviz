//
//  ToastsService.swift
//  diaviz
//

import Foundation
import Observation

/// Famille d'un toast — porte l'icône et laisse la couleur à la vue, seule
/// couche censée décider d'une teinte.
nonisolated enum CategorieToast: Sendable {
    case repas
    case insuline
    case sport
    case resucrage
    /// Réglage du profil (ratio, préférence d'aliment) — pas un fait de santé.
    case reglage
    /// Opération sur l'ensemble des données (export, import d'archive).
    case donnees
    /// Fait existant réécrit (repas modifié).
    case modification
    /// Suppression, quelle que soit la famille de l'objet supprimé : c'est le
    /// caractère irréversible qui prime sur le domaine, et c'est le seul cas
    /// où une pilule porte une action.
    case suppression

    var icone: String {
        switch self {
        case .repas:       "fork.knife"
        case .insuline:    "syringe.fill"
        case .sport:       "figure.run"
        case .resucrage:   "takeoutbag.and.cup.and.straw.fill"
        case .reglage:     "slider.horizontal.3"
        case .donnees:     "externaldrive.fill"
        case .modification: "pencil"
        case .suppression: "trash.fill"
        }
    }
}

/// Action optionnelle portée par une pilule — « Annuler » après une
/// suppression, et rien d'autre pour l'instant : une confirmation qui demande
/// à être lue *et* décidée n'est plus une confirmation.
struct ActionToast {
    let libelle: String
    let executer: @MainActor () -> Void
}

/// Un événement confirmé à l'utilisateur, le temps d'une pilule en haut de
/// l'écran.
struct ToastEvenement: Identifiable, Equatable {
    let id = UUID()
    let categorie: CategorieToast
    let titre: String
    /// Détail chiffré sur une ligne (« 62 g · 6u »). `nil` = titre seul.
    let detail: String?
    /// Bouton d'annulation, quand l'action confirmée est réversible.
    let action: ActionToast?

    init(categorie: CategorieToast, titre: String, detail: String? = nil, action: ActionToast? = nil) {
        self.categorie = categorie
        self.titre = titre
        self.detail = detail
        self.action = action
    }

    /// Identité seule : `ActionToast` porte une closure, et deux pilules ne
    /// sont de toute façon jamais « la même » à contenu identique.
    static func == (gauche: ToastEvenement, droite: ToastEvenement) -> Bool {
        gauche.id == droite.id
    }
}

/// File des confirmations éphémères affichées par `PileToasts`.
///
/// Un enregistrement dans le hub n'a aujourd'hui aucun accusé de réception :
/// la sheet se ferme, et rien ne dit ce qui a été écrit. Ces pilules comblent
/// ce trou **sans jamais interrompre** — pas d'alerte, pas de bouton, elles
/// s'effacent seules.
///
/// Singleton comme `ProfilService.shared` : les services du hub émettent
/// depuis `enregistrer(_:)`, où passent tous les chemins de saisie (sheets,
/// séance en direct, import Santé). Les brancher un par un sur les dizaines
/// de points d'appel garantissait d'en oublier.
///
/// Volontairement **hors du hub** : un toast est un fait d'interface, pas une
/// donnée de santé — rien à persister, rien à synchroniser.
@Observable
@MainActor
final class ToastsService {

    static let shared = ToastsService()

    /// Du plus récent au plus ancien — la vue empile dans cet ordre, le
    /// dernier arrivé devant.
    private(set) var toasts: [ToastEvenement] = []

    /// Durée d'affichage d'une pilule.
    ///
    /// 2,5 s à l'origine : le temps de revenir de la sheet qu'on vient de
    /// valider vers le haut de l'écran, la pilule était déjà partie. Le tap
    /// permet de l'écarter plus tôt, donc l'attente ne coûte rien à qui l'a
    /// déjà lue.
    private static let duree: Duration = .seconds(4.5)

    /// Une pilule porteuse d'une annulation reste plus longtemps : elle n'est
    /// plus seulement lue, elle peut être utilisée.
    private static let dureeAvecAction: Duration = .seconds(7)

    /// Au-delà, les plus anciennes sortent immédiatement : la pile reste
    /// lisible et ne recouvre pas le haut de l'écran (cas d'un import Santé
    /// qui enregistre plusieurs séances d'affilée).
    private static let maximumEmpile = 3

    private init() {}

    func afficher(
        _ categorie: CategorieToast,
        titre: String,
        detail: String? = nil,
        action: ActionToast? = nil
    ) {
        let toast = ToastEvenement(categorie: categorie, titre: titre, detail: detail, action: action)
        toasts.insert(toast, at: 0)
        if toasts.count > Self.maximumEmpile {
            toasts.removeLast(toasts.count - Self.maximumEmpile)
        }
        Task { [weak self] in
            try? await Task.sleep(for: action == nil ? Self.duree : Self.dureeAvecAction)
            self?.retirer(toast.id)
        }
    }

    /// Confirme une suppression en laissant une porte de sortie. `restaurer`
    /// recrée l'objet à l'identique, `id` compris — un masquage ou une
    /// analyse qui référence cet identifiant reste donc valable.
    func afficherSuppression(
        titre: String,
        detail: String? = nil,
        restaurer: @escaping @MainActor () -> Void
    ) {
        afficher(
            .suppression,
            titre: titre,
            detail: detail,
            action: ActionToast(libelle: "Annuler", executer: restaurer)
        )
    }

    /// Retrait manuel — tap sur la pilule, ou fin du délai.
    func retirer(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

#if DEBUG
extension ToastsService {

    /// Instance isolée pour les previews : le singleton porte l'état réel de
    /// l'app, une preview ne doit pas le remplir.
    @MainActor
    static func apercu(_ toasts: [ToastEvenement] = []) -> ToastsService {
        let service = ToastsService()
        service.toasts = toasts
        return service
    }
}
#endif
