//
//  EncartResultatPrise.swift
//  diaviz
//

import SwiftUI

/// Détail chiffré d'un resucrage jugé, déplié sous sa ligne dans la liste
/// d'événements. N'apparaît qu'au tap — c'est ce qui donne un rôle propre au
/// geste, la surbrillance du curseur se contentant de désigner la ligne.
///
/// Volontairement factuel : ce que la glycémie a fait, sur quelle fenêtre, et
/// dans quelle tendance elle était avant. Aucune recommandation.
struct EncartResultatPrise: View {

    let resultat: ResultatPrise

    var body: some View {
        VStack(spacing: 5) {
            if let avant = resultat.glycemieAvant {
                ligne("Glycémie", valeurGlycemie(avant: avant, apres: resultat.glycemieApres))
            }
            ligne("Fenêtre observée", libelleFenetre)
            if let tendance = resultat.tendanceAvant {
                ligne("Tendance avant", tendance.libelle)
            }
            // Les trois cas de non-jugement se ressemblent à l'écran alors
            // qu'ils ne disent pas la même chose — on nomme lequel s'applique.
            if let raison = resultat.raison {
                Divider().padding(.vertical, 2)
                Text(raison.libelle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(.compact, fond: Color(.tertiarySystemFill))
    }

    private func ligne(_ libelle: String, _ valeur: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(libelle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(valeur)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    /// « 138 → 76 » quand la fenêtre a pu être observée, sinon la seule
    /// valeur de départ.
    private func valeurGlycemie(avant: Double, apres: Double?) -> String {
        guard let apres else { return "\(Int(avant.rounded()))" }
        return "\(Int(avant.rounded())) → \(Int(apres.rounded()))"
    }

    private var libelleFenetre: String {
        "\(resultat.libelleFenetre) · \(resultat.dureeFenetreMinutes) min"
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        EncartResultatPrise(
            resultat: ResultatPrise(
                id: "1",
                verdict: .chuteNonEnrayee,
                glycemieAvant: 138,
                glycemieApres: 76,
                tendanceAvant: .baisse,
                dureeFenetreMinutes: 25,
                libelleFenetre: "jusqu'à la fin de l'effort",
                idEpisode: 0
            )
        )
        EncartResultatPrise(
            resultat: ResultatPrise(
                id: "2",
                verdict: .nonEvaluable,
                glycemieAvant: 64,
                glycemieApres: nil,
                tendanceAvant: .stable,
                dureeFenetreMinutes: 30,
                libelleFenetre: "30 min après la prise",
                idEpisode: 1
            )
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
