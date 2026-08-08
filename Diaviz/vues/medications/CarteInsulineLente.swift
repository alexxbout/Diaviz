//
//  CarteInsulineLente.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Carte « héro » d'insuline lente, posée sous le graphe.
///
/// Trois états mutuellement exclusifs, dérivés de la lente du jour
/// affiché et de l'heure habituelle configurée par l'utilisateur :
/// 1. **enregistree** : la lente du jour a été prise → ✓ vert, dose et
///    infos lisibles.
/// 2. **aPrendre** : pas de lente aujourd'hui ET heure habituelle déjà
///    passée → ⚠ orange + libellé « À prendre » orange, tappable.
/// 3. **prochainePrevue** : pas de lente aujourd'hui ET heure pas encore
///    atteinte → 🕐 + libellé « Prochaine injection ».
///
/// Tous les états partagent le même fond neutre
/// `secondarySystemGroupedBackground` et n'ont pas de bordure : la carte
/// se fond dans la section `List` ; la sémantique de chaque état est
/// portée par l'icône, le libellé et leur couleur.
///
/// La carte est dimensionnée pour s'insérer dans une row de `List`
/// `.insetGrouped` avec `listRowInsets(EdgeInsets())` et un row
/// background transparent — elle apporte sa propre couleur de fond.
struct CarteInsulineLente: View {

    enum Etat: Equatable {
        case enregistree(Injection)
        /// `heureHabituelle` est une date pleine (pas juste une heure du
        /// jour) : elle est dérivée de la dernière dose + l'intervalle
        /// minimum du profil, donc peut glisser d'un jour à l'autre.
        case aPrendre(heureHabituelle: Date)
        case prochainePrevue(heureHabituelle: Date)
    }

    // MARK: - Paramètres

    let etat: Etat

    /// Tap sur la carte → ouvre la sheet d'enregistrement (uniquement
    /// pertinent pour l'état `aPrendre` ; les autres sont passifs).
    let onTap: () -> Void

    // MARK: - Corps

    var body: some View {
        // Wrapping conditionnel : un `Button.disabled(...)` applique un
        // dimming global au contenu, ce qui ternit visuellement les
        // états passifs. On ne wrappe en bouton que si la carte est
        // réellement actionnable.
        Group {
            if estTappable {
                Button(action: onTap) { carte }
                    .buttonStyle(.plain)
            } else {
                carte
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
        .accessibilityAddTraits(estTappable ? .isButton : [])
        .accessibilityHint(hintAccessible)
    }

    private var carte: some View {
        contenu
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                NiveauCarte.carte.forme
                    .fill(couleurFond)
                    .overlay {
                        if let bordure = couleurBordure {
                            NiveauCarte.carte.forme
                                .strokeBorder(bordure, lineWidth: 1)
                        }
                    }
            }
            .contentShape(NiveauCarte.carte.forme)
    }

    // MARK: - Contenu

    @ViewBuilder
    private var contenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete

            switch etat {
            case .enregistree(let injection):
                contenuEnregistree(injection)
            case .aPrendre(let heure):
                contenuAPrendre(heure)
            case .prochainePrevue(let heure):
                contenuProchaine(heure)
            }
        }
    }

    /// En-tête : libellé « INSULINE LENTE » + icône d'état (✓ ou ⚠ ou rien).
    private var entete: some View {
        HStack {
            Label("INSULINE LENTE", systemImage: "drop.fill")
                .font(.caption.bold())
                .foregroundStyle(couleurAccent)
                .labelStyle(.titleAndIcon)

            Spacer()

            iconeEtat
        }
    }

    @ViewBuilder
    private var iconeEtat: some View {
        switch etat {
        case .enregistree:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .aPrendre:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        case .prochainePrevue:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    // MARK: - Variantes de contenu

    @ViewBuilder
    private func contenuEnregistree(_ injection: Injection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(formate(injection.dose))u")
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let nom = injection.nomMedicament {
                    Text("· \(nom)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Text(libelleHeureSite(injection))
                .font(.body)
                .foregroundStyle(.secondary)

            Text(tempsRelatif(depuis: injection.heure))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func contenuAPrendre(_ heure: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("À prendre")
                .font(.title.bold())
                .foregroundStyle(.orange)

            Text("Heure habituelle : \(libelleHeure(heure))")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Tape pour enregistrer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func contenuProchaine(_ heure: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prochaine injection")
                .font(.title.bold())
                .foregroundStyle(.primary)

            Text("Prévue à \(libelleHeure(heure))")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Style dérivé de l'état

    private var couleurFond: Color {
        // `secondarySystemGroupedBackground` matche le fond des cellules
        // d'un List en .insetGrouped — blanc en clair, gris foncé en
        // sombre. Tous les états utilisent ce fond neutre ; l'urgence de
        // l'état `aPrendre` est portée par l'icône ⚠ et le libellé orange,
        // pas par un wash de couleur.
        Color(.secondarySystemGroupedBackground)
    }

    /// `nil` quand on ne veut pas de bordure. Aucun état n'a de bordure :
    /// la carte se fond dans la section `List` comme les autres rows.
    private var couleurBordure: Color? { nil }

    /// Couleur de l'icône drop.fill et du libellé d'en-tête.
    /// Bleu sauf pour l'alerte où l'orange prime visuellement.
    private var couleurAccent: Color {
        switch etat {
        case .aPrendre: return .orange
        default:        return .blue
        }
    }

    private var estTappable: Bool {
        switch etat {
        case .aPrendre, .enregistree: return true
        case .prochainePrevue:        return false
        }
    }

    // MARK: - Accessibilité

    private var libelleAccessible: String {
        switch etat {
        case .enregistree(let inj):
            return "Insuline lente enregistrée. \(formate(inj.dose)) unités, \(inj.libelleSite), à \(inj.heure.formatted(date: .omitted, time: .shortened))."
        case .aPrendre(let h):
            return "Insuline lente à prendre. Heure habituelle : \(libelleHeure(h))."
        case .prochainePrevue(let h):
            return "Prochaine insuline lente prévue à \(libelleHeure(h))."
        }
    }

    private var hintAccessible: String {
        switch etat {
        case .aPrendre:        return "Touchez deux fois pour enregistrer"
        case .enregistree:     return "Touchez deux fois pour modifier"
        case .prochainePrevue: return ""
        }
    }

    // MARK: - Helpers

    private func formate(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private func libelleHeureSite(_ injection: Injection) -> String {
        let heure = injection.heure.formatted(date: .omitted, time: .shortened)
        return "\(heure) · \(injection.libelleSite)"
    }

    /// Formate une heure habituelle adaptative : heure seule si elle tombe
    /// aujourd'hui, sinon heure + jour (ex. « 23h10 demain ») — l'ancrage
    /// dérivé de la dernière dose peut glisser sur un autre jour calendaire.
    private func libelleHeure(_ date: Date) -> String {
        let heure = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return heure
        }
        let jour = date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
        return "\(heure) \(jour.lowercased())"
    }

}

// MARK: - Aperçu

#Preview("État enregistrée") {
    let inj = Injection(
        type: .lente,
        dose: 18,
        heure: Calendar.current.date(byAdding: .hour, value: -16, to: Date()) ?? Date(),
        zoneInjection: .cuisse,
        coteInjection: .gauche,
        nomMedicament: "Lantus"
    )
    return CarteInsulineLente(etat: .enregistree(inj), onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("État à prendre") {
    CarteInsulineLente(
        etat: .aPrendre(heureHabituelle: HeureDuJour(heure: 22, minute: 0).date()),
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("État prochaine prévue") {
    CarteInsulineLente(
        etat: .prochainePrevue(heureHabituelle: HeureDuJour(heure: 22, minute: 0).date()),
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
