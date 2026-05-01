//
//  CarteInsulineLente.swift
//  insulog
//
//  Created by Alexandre on 01/05/2026.
//

import SwiftUI

/// Carte « héro » d'insuline lente, posée sous le graphe.
///
/// Trois états mutuellement exclusifs, dérivés de la lente du jour
/// affiché et de l'heure habituelle configurée par l'utilisateur :
/// 1. **enregistree** : la lente du jour a été prise → fond bleu opaque
///    avec bordure subtile, ✓ vert, dose et infos lisibles.
/// 2. **aPrendre** : pas de lente aujourd'hui ET heure habituelle déjà
///    passée → fond orange opaque avec bordure, ⚠ orange, tappable.
/// 3. **prochainePrevue** : pas de lente aujourd'hui ET heure pas encore
///    atteinte → fond neutre `secondarySystemBackground`, sans bordure.
///
/// La carte est dimensionnée pour s'insérer dans une row de `List`
/// `.insetGrouped` avec `listRowInsets(EdgeInsets())` et un row
/// background transparent — elle apporte sa propre couleur de fond.
struct CarteInsulineLente: View {

    enum Etat: Equatable {
        case enregistree(Injection)
        case aPrendre(heureHabituelle: HeureDuJour)
        case prochainePrevue(heureHabituelle: HeureDuJour)
    }

    // MARK: - Paramètres

    let etat: Etat

    /// Tap sur la carte → ouvre la sheet d'enregistrement (uniquement
    /// pertinent pour l'état `aPrendre` ; les autres sont passifs).
    let onTap: () -> Void

    // MARK: - Corps

    var body: some View {
        Button(action: onTap) {
            contenu
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(couleurFond)
                        .overlay {
                            if let bordure = couleurBordure {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(bordure, lineWidth: 1)
                            }
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!estTappable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(libelleAccessible)
        .accessibilityHint(estTappable ? "Touchez deux fois pour enregistrer" : "")
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
            EmptyView()
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

            Text(libelleIlYA(depuis: injection.heure))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func contenuAPrendre(_ heure: HeureDuJour) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("À prendre")
                .font(.title.bold())
                .foregroundStyle(.orange)

            Text("Heure habituelle : \(heure.libelle)")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Tape pour enregistrer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func contenuProchaine(_ heure: HeureDuJour) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prochaine injection")
                .font(.title.bold())
                .foregroundStyle(.primary)

            Text("Prévue à \(heure.libelle)")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Style dérivé de l'état

    private var couleurFond: Color {
        switch etat {
        case .enregistree:      return Color.blue.opacity(0.15)
        case .aPrendre:         return Color.orange.opacity(0.15)
        // `secondarySystemGroupedBackground` matche le fond des cellules
        // d'un List en .insetGrouped — la carte « neutre » ressort
        // proprement sur le fond gris global de la section, là où
        // `secondarySystemBackground` rendait la carte invisible.
        case .prochainePrevue:  return Color(.secondarySystemGroupedBackground)
        }
    }

    /// `nil` quand on ne veut pas de bordure (état neutre).
    private var couleurBordure: Color? {
        switch etat {
        case .enregistree:      return Color.blue.opacity(0.3)
        case .aPrendre:         return Color.orange.opacity(0.3)
        case .prochainePrevue:  return nil
        }
    }

    /// Couleur de l'icône drop.fill et du libellé d'en-tête.
    /// Bleu sauf pour l'alerte où l'orange prime visuellement.
    private var couleurAccent: Color {
        switch etat {
        case .aPrendre: return .orange
        default:        return .blue
        }
    }

    private var estTappable: Bool {
        if case .aPrendre = etat { return true }
        return false
    }

    // MARK: - Accessibilité

    private var libelleAccessible: String {
        switch etat {
        case .enregistree(let inj):
            return "Insuline lente enregistrée. \(formate(inj.dose)) unités, \(inj.libelleSite), à \(inj.heure.formatted(date: .omitted, time: .shortened))."
        case .aPrendre(let h):
            return "Insuline lente à prendre. Heure habituelle : \(h.libelle)."
        case .prochainePrevue(let h):
            return "Prochaine insuline lente prévue à \(h.libelle)."
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

    /// « il y a 4h », « il y a 32 min », « il y a 16h06 ».
    private func libelleIlYA(depuis: Date) -> String {
        let secondes = Int(Date.now.timeIntervalSince(depuis))
        guard secondes > 60 else { return "il y a quelques instants" }
        let heures = secondes / 3600
        let minutes = (secondes % 3600) / 60
        if heures == 0 { return "il y a \(minutes) min" }
        if minutes == 0 { return "il y a \(heures)h" }
        return "il y a \(heures)h\(String(format: "%02d", minutes))"
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
        etat: .aPrendre(heureHabituelle: HeureDuJour(heure: 22, minute: 0)),
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("État prochaine prévue") {
    CarteInsulineLente(
        etat: .prochainePrevue(heureHabituelle: HeureDuJour(heure: 22, minute: 0)),
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
