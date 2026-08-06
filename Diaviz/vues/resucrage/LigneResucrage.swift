//
//  LigneResucrage.swift
//  diaviz
//

import SwiftUI

/// Row d'un resucrage dans la liste du journal — icône d'intention, heure,
/// total glucides, badge cible si renseignée.
///
/// Consomme un `ResucrageAffiche` (snapshot value type), **jamais** le
/// `@Model` : la row survit à l'animation de suppression sans jamais relire
/// un objet invalidé (voir `ResucrageAffiche`).
struct LigneResucrage: View {
    let resucrage: ResucrageAffiche

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resucrage.intention.icone)
                .font(.title3)
                .foregroundStyle(resucrage.intention.couleur)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(resucrage.intention.rawValue)
                    .font(.body)
                Text(sousLigne)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.formatterHeure.string(from: resucrage.date))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if resucrage.glucidesTotal > 0 {
                    Text("\(resucrage.glucidesTotal)g")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var sousLigne: String {
        var parts: [String] = []
        if let cible = resucrage.glycemieCible {
            parts.append("Cible \(Int(cible)) mg/dL")
        }
        if resucrage.nombreAliments == 0 {
            parts.append("Aucun aliment renseigné")
        } else if let nom = resucrage.nomAlimentUnique {
            parts.append(nom)
        } else {
            parts.append("\(resucrage.nombreAliments) aliments")
        }
        return parts.joined(separator: " · ")
    }

    private static let formatterHeure: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "H'h'mm"
        return f
    }()
}

#Preview {
    List {
        LigneResucrage(resucrage: Resucrage(
            intention: .correctifHypo,
            aliments: [.collationGenerique(glucidesGrammes: 15)]
        ).affichage)
        LigneResucrage(resucrage: Resucrage(
            intention: .preventifMaintien,
            aliments: [.collationGenerique(glucidesGrammes: 12)],
            glycemieCible: 140
        ).affichage)
    }
}
