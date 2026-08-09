//
//  CarteLenteRappel.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftUI

// MARK: - Contexte (données alimentant la carte)

/// Snapshot des données nécessaires à la carte « Insuline lente »
/// affichée sur l'accueil — heure habituelle configurée, nom et dose
/// d'insuline, dernière prise enregistrée, statut « prise aujourd'hui ».
///
/// Forme volontairement plate et `Equatable` pour piloter proprement
/// les animations SwiftUI (`.animation(_:value:)`) et faciliter les
/// previews. Côté production, ce contexte sera construit par le parent
/// à partir du `ProfilService` et du service d'injections — la carte
/// reste agnostique de la source.
struct ContexteLente: Equatable, Sendable {

    /// Heure habituelle de prise, ancrée sur la journée courante.
    /// Stockée en `Date` plutôt qu'en `HeureDuJour` parce que le calcul
    /// d'état compare directement à `Date.now` (différence en secondes).
    let heureHabituelle: Date

    /// Nom commercial de l'insuline lente (« Toujeo », « Lantus »…).
    let nomInsuline: String

    /// Dose habituelle, en unités. Affichée à titre informatif sur la
    /// carte ; sert aussi (côté parent) au pré-remplissage de la sheet.
    let doseHabituelle: Double

    /// Date+heure de la dernière injection lente enregistrée — sert au
    /// libellé « Dernière prise il y a Xh ».
    let dernierePrise: Date

    /// Site de la dernière injection lente, déjà formaté pour affichage
    /// (« Cuisse gauche »). Sert au libellé « Dernier site : … ».
    let dernierSite: String

    /// `true` si la lente du jour est déjà enregistrée — la carte est
    /// alors masquée par la logique de `EtatRappelLente.calculer(...)`.
    let priseAujourdhui: Bool
}

extension ContexteLente {

    /// Heure habituelle formatée pour l'affichage (« 22:00 »).
    var heureHabituelleLibelle: String {
        heureHabituelle.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Mocks

extension ContexteLente {

    /// Heure habituelle = maintenant → diff = 0 → état `.doux`.
    /// La dernière prise est posée à hier 22h pour donner « il y a 23h ».
    static var mockDoux: ContexteLente {
        ContexteLente(
            heureHabituelle: .now,
            nomInsuline: "Toujeo",
            doseHabituelle: 18,
            dernierePrise: Calendar.current.date(byAdding: .hour, value: -23, to: .now) ?? .now,
            dernierSite: "Cuisse gauche",
            priseAujourdhui: false
        )
    }

    /// Heure habituelle = maintenant - 45min → état `.urgent`.
    /// Le sous-titre affichera « Prévue à HH:MM · il y a 45 min ».
    static var mockUrgent: ContexteLente {
        ContexteLente(
            heureHabituelle: Calendar.current.date(byAdding: .minute, value: -45, to: .now) ?? .now,
            nomInsuline: "Toujeo",
            doseHabituelle: 18,
            dernierePrise: Calendar.current.date(byAdding: .hour, value: -23, to: .now) ?? .now,
            dernierSite: "Cuisse gauche",
            priseAujourdhui: false
        )
    }

    /// Heure habituelle = maintenant - 2h30 → état `.alerte`.
    static var mockAlerte: ContexteLente {
        ContexteLente(
            heureHabituelle: Calendar.current.date(byAdding: .minute, value: -150, to: .now) ?? .now,
            nomInsuline: "Toujeo",
            doseHabituelle: 18,
            dernierePrise: Calendar.current.date(byAdding: .hour, value: -25, to: .now) ?? .now,
            dernierSite: "Cuisse gauche",
            priseAujourdhui: false
        )
    }

    /// Lente déjà prise aujourd'hui → `EtatRappelLente.calculer` retourne
    /// `nil` et la carte est masquée. Utile pour vérifier la disparition
    /// de la carte dans une preview.
    static var mockPrise: ContexteLente {
        ContexteLente(
            heureHabituelle: Calendar.current.date(byAdding: .minute, value: -45, to: .now) ?? .now,
            nomInsuline: "Toujeo",
            doseHabituelle: 18,
            dernierePrise: Calendar.current.date(byAdding: .hour, value: -2, to: .now) ?? .now,
            dernierSite: "Cuisse gauche",
            priseAujourdhui: true
        )
    }
}

// MARK: - Vue

/// Carte contextuelle de rappel « Insuline lente », insérée sur l'accueil
/// entre la carte du score et la section des insights.
///
/// La carte est **purement informative** : elle agrège l'heure prévue,
/// le retard, l'historique récent (dernière prise + site) et propose un
/// bouton circulaire `+` pour ouvrir rapidement la sheet d'enregistrement
/// pré-remplie. Aucun libellé ne prescrit d'action médicale directive ;
/// l'urgence est portée par la couleur d'accent et l'icône.
///
/// Trois états visuels mutuellement exclusifs (cf. `EtatRappelLente`)
/// partagent un **fond opaque neutre** (`secondarySystemGroupedBackground`)
/// pour préserver le contraste texte/fond ; seuls la couleur d'icône,
/// du titre et du bouton `+` portent l'urgence :
/// - `.doux` : accent bleu, titre `.primary`
/// - `.urgent` : accent orange, titre orange
/// - `.alerte` : accent rouge, titre rouge
///
/// La carte elle-même ne gère pas sa visibilité — c'est le parent qui
/// la rend conditionnellement (`if let etat = ... { ... }`) avec une
/// `.transition` et une `.animation(.spring, value:)` pour l'apparition
/// et la disparition.
struct CarteLenteRappel: View {

    // MARK: - Paramètres

    let etat: EtatRappelLente
    let contexte: ContexteLente

    /// Tap sur le bouton `+` → ouvre la sheet d'enregistrement de la
    /// lente (le parent décide quelle sheet présenter).
    var onTapAjouter: () -> Void = {}

    // MARK: - Corps

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            colonneInfo
            Spacer(minLength: 8)
            boutonAjouter
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Surface standard des cartes de l'accueil — voir `surfaceCarte()`.
        .surfaceCarte()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Colonne gauche (info)

    private var colonneInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            // MARK: Ligne 1 — icône + titre
            HStack(spacing: 6) {
                Image(systemName: iconeSysteme)
                    .font(.subheadline)
                    .foregroundStyle(couleurAccent)
                    .accessibilityHidden(true)

                Text(titre)
                    .font(.subheadline.bold())
                    .foregroundStyle(couleurTitre)
            }

            // MARK: Ligne 2 — sous-titre horaire (+ retard si dépassé)
            Text(sousTitre)
                .font(.callout)
                .foregroundStyle(.secondary)

            // MARK: Ligne 3 — insuline + dose habituelle
            Text("\(contexte.nomInsuline) · \(formate(contexte.doseHabituelle))u")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // MARK: Ligne 4 — dernière prise
            Text("Dernière prise \(tempsRelatif(depuis: contexte.dernierePrise))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // MARK: Ligne 5 — dernier site
            Text("Dernier site : \(contexte.dernierSite)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessibleInfo)
    }

    // MARK: - Bouton [+]

    private var boutonAjouter: some View {
        Button(action: onTapAjouter) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(couleurAccent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enregistrer la lente maintenant")
        .accessibilityHint("Ouvre l'enregistrement pré-rempli avec la dose habituelle")
    }

    // MARK: - Style dérivé de l'état

    private var iconeSysteme: String {
        switch etat {
        case .doux:               return "clock.fill"
        case .urgent, .alerte:    return "exclamationmark.triangle.fill"
        }
    }

    private var titre: String {
        switch etat {
        case .doux:    return "Insuline lente"
        case .urgent:  return "Insuline lente en retard"
        case .alerte:  return "Insuline lente non prise"
        }
    }

    /// Couleur de l'icône d'en-tête et du bouton `+`.
    private var couleurAccent: Color {
        switch etat {
        case .doux:    return .blue
        case .urgent:  return .orange
        case .alerte:  return .red
        }
    }

    /// Couleur du titre — neutre en état doux, colorée pour urgent/alerte
    /// afin de renforcer la saillance visuelle sans recourir à des
    /// formulations directives dans le texte.
    private var couleurTitre: Color {
        switch etat {
        case .doux:    return .primary
        case .urgent:  return .orange
        case .alerte:  return .red
        }
    }

    // MARK: - Calculs dynamiques

    /// Sous-titre horaire : « Prévue à 22:00 » en état doux quand
    /// l'heure n'est pas encore dépassée, augmenté du retard « · il y a
    /// 45 min » dès que la fenêtre habituelle est dépassée.
    private var sousTitre: String {
        let heureLib = contexte.heureHabituelleLibelle
        let diff = Date.now.timeIntervalSince(contexte.heureHabituelle)
        if diff <= 60 {
            // Avant l'heure habituelle (ou dans la première minute) :
            // on n'affiche pas de « il y a … » qui n'aurait pas de sens.
            return "Prévue à \(heureLib)"
        }
        return "Prévue à \(heureLib) · \(tempsRelatif(depuis: contexte.heureHabituelle))"
    }

    /// Libellé VoiceOver synthétique reprenant l'ensemble des infos
    /// visibles dans la colonne gauche.
    private var libelleAccessibleInfo: String {
        var parts: [String] = [titre, sousTitre]
        parts.append("Dose habituelle \(formate(contexte.doseHabituelle)) unités de \(contexte.nomInsuline)")
        parts.append("Dernière prise \(tempsRelatif(depuis: contexte.dernierePrise))")
        parts.append("Dernier site \(contexte.dernierSite)")
        return parts.joined(separator: ". ")
    }

    // MARK: - Helpers

    /// « 18 » pour les entiers, « 17.5 » sinon — aligné sur le formatage
    /// utilisé par `CarteInsulineLente` pour cohérence cross-écran.
    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

}

// MARK: - Aperçus

#if DEBUG
#Preview("Lente - Rappel doux") {
    CarteLenteRappel(
        etat: .doux,
        contexte: .mockDoux
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
}

#Preview("Lente - Urgent") {
    CarteLenteRappel(
        etat: .urgent,
        contexte: .mockUrgent
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
}

#Preview("Lente - Alerte") {
    CarteLenteRappel(
        etat: .alerte,
        contexte: .mockAlerte
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
}

/// Pas de carte rendue (lente déjà prise aujourd'hui) — démontre que
/// `EtatRappelLente.calculer(...)` retourne `nil` et que le parent doit
/// donc masquer la carte. La preview affiche un placeholder textuel
/// pour confirmer visuellement le comportement.
#Preview("Lente - Masquée (déjà prise)") {
    VStack(spacing: 8) {
        if let etat = EtatRappelLente.calculer(contexte: .mockPrise) {
            CarteLenteRappel(etat: etat, contexte: .mockPrise)
        } else {
            Text("Carte masquée — lente déjà prise aujourd'hui")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(16)
    .background(Color(.systemGroupedBackground))
}

#Preview("Lente - Urgent (sombre)") {
    CarteLenteRappel(
        etat: .urgent,
        contexte: .mockUrgent
    )
    .padding(16)
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
