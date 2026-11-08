//
//  ValidationRatioCard.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte affichant la cohérence entre la dose saisie et la dose suggérée
/// par le ratio actif : cohérente, faible, élevée, ou aucune dose saisie.
///
/// Une conclusion et les deux doses ; le ratio utilisé, l'écart, l'historique
/// et la charge vivent dans le détail. Icône en cercle coloré + titre + lignes,
/// sur un fond uni à `0.10` d'opacité dans la couleur d'accent. Pas de bordure
/// extérieure (qui se faisait clipper par le `Form` parent).
struct ValidationRatioCard: View {

    let validation: ValidationRatio
    /// Charge active au moment du repas, montrée dans le détail. `nil` si
    /// indisponible.
    var chargeSynthese: SyntheseChargeActive? = nil

    @State private var afficherExplication: Bool = false

    var body: some View {
        Button {
            afficherExplication = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                iconeCirculaire
                contenu
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .surfaceCarte(fond: couleurAccent.opacity(0.10))
            .animation(.easeOut(duration: 0.2), value: validation.etat)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $afficherExplication) {
            FeuilleExplicationValidation(validation: validation, chargeSynthese: chargeSynthese)
        }
    }

    // MARK: - Sous-vues

    /// Icône circulaire à gauche : fond teinté en accent, glyphe SF Symbol
    /// dans la même couleur d'accent. Donne le focus visuel sur le statut.
    private var iconeCirculaire: some View {
        ZStack {
            Circle()
                .fill(couleurAccent.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: nomIcone)
                .font(.title3.bold())
                .foregroundStyle(couleurAccent)
        }
    }

    private var contenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 2)

            if !sansDose {
                ligne("\(validation.doseSaisie.unitesFormatees) \(validation.doseSaisie >= 2 ? "saisies" : "saisie") · \(validation.doseSuggeree.unitesFormatees) au ratio")
            }
            if validation.ajustements != 0 {
                ligne("Ajustement \(validation.ajustements.unitesSigneesFormatees) en plus")
            }
            // Seule observation d'historique utile au moment de doser. Rien
            // sous ratio sport : le mining ne couvre que les ratios par moment.
            if !validation.ratioSportApplique, validation.ecartObserve != nil {
                let moment = validation.repartition.libelleMomentPluriel
                ligne(moment.isEmpty ? "Écart observé sur ce moment" : "Écart observé sur vos \(moment)")
            }
        }
    }

    private func ligne(_ texte: String) -> some View {
        Text(texte)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
    }

    // MARK: - Calculs visuels

    /// Aucune dose encore saisie : rien à juger, la carte donne seulement la
    /// dose au ratio. Annoncer « dose faible » avant toute saisie était faux.
    private var sansDose: Bool { validation.doseSaisie == 0 }

    private var titre: String {
        let ratio = validation.ratioSportApplique ? "ratio sport" : "ratio"
        if sansDose { return "Dose au \(ratio) : \(validation.doseSuggeree.unitesFormatees)" }
        switch validation.etat {
        case .coherente: return "Dose cohérente avec le \(ratio)"
        case .faible:    return "Dose faible vs \(ratio)"
        case .elevee:    return "Dose élevée vs \(ratio)"
        }
    }

    private var nomIcone: String {
        if sansDose { return "circle.dashed" }
        switch validation.etat {
        case .coherente:        return "checkmark.circle.fill"
        case .faible, .elevee:  return "exclamationmark.triangle.fill"
        }
    }

    private var couleurAccent: Color {
        if sansDose { return .secondary }
        switch validation.etat {
        case .coherente: return .green
        case .faible:    return .orange
        case .elevee:    return .red
        }
    }

}

private extension Double {
    /// « 2,1 u » — virgule de la langue de l'appareil, décimale seulement utile.
    var unitesFormatees: String {
        "\(formatted(.number.precision(.fractionLength(0...1)))) u"
    }

    /// « −0,5 u » / « +1 u ».
    var unitesSigneesFormatees: String {
        "\(self < 0 ? "\u{2212}" : "+")\(abs(self).unitesFormatees)"
    }
}

// MARK: - Sheet de détail

/// Tout ce que la carte ne dit pas, une valeur par ligne.
private struct FeuilleExplicationValidation: View {
    let validation: ValidationRatio
    var chargeSynthese: SyntheseChargeActive? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Dose saisie", value: validation.doseSaisie.unitesFormatees)
                    LabeledContent("Dose au ratio", value: validation.doseSuggeree.unitesFormatees)
                    if validation.etat != .coherente {
                        LabeledContent("Écart", value: validation.ecart.unitesSigneesFormatees)
                    }
                    LabeledContent("Ratio \(validation.profil.libelle) actuel", value: ratio(validation.profil.grammesParUnite))
                } footer: {
                    Text("Seule la dose de base est confrontée au ratio : ni la correction, ni l'ajustement, ni l'insuline active.")
                }

                if validation.ajustements != 0 {
                    Section("Ajustement") {
                        LabeledContent("Ajustement", value: validation.ajustements.unitesSigneesFormatees)
                        if let effectif = validation.ratioEffectifApresAjustement {
                            LabeledContent("Ajustement inclus", value: ligneAjustementInclus(effectif))
                        }
                    }
                }

                if !validation.ratioSportApplique, let ecart = validation.ecartObserve {
                    Section("Bons résultats observés") {
                        LabeledContent(
                            "Repas à \(ecart.trancheOptimale.libelle)",
                            value: resultat(ecart.tauxOptimal, ecart.bonsOptimal, ecart.effectifOptimal)
                        )
                        LabeledContent(
                            "Repas à votre ratio actuel",
                            value: resultat(ecart.tauxConfigure, ecart.bonsConfigure, ecart.effectifConfigure)
                        )
                    }
                }

                if case let .disponible(_, niveau, depuisJours)? = chargeSynthese?.etat {
                    Section {
                        LabeledContent("Charge active", value: libelleCharge(niveau, depuisJours: depuisJours))
                    }
                }
            }
            .navigationTitle("Validation du ratio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func ratio(_ grammesParUnite: Double) -> String {
        "1 u / \(grammesParUnite.formatted(.number.precision(.fractionLength(0...1)))) g"
    }

    private func ligneAjustementInclus(_ effectif: Double) -> String {
        let total = validation.doseSaisie + validation.ajustements
        let glucides = validation.glucides.formatted(.number.precision(.fractionLength(0...1)))
        return "\(total.unitesFormatees) pour \(glucides) g, soit \(ratio(effectif))"
    }

    private func resultat(_ taux: Double, _ bons: Int, _ effectif: Int) -> String {
        "\(Int((taux * 100).rounded()))\u{00A0}% (\(bons)/\(effectif))"
    }

    private func libelleCharge(_ niveau: NiveauChargeActive, depuisJours: Int?) -> String {
        let libelle = niveau.libelleCourt.prefix(1).uppercased() + niveau.libelleCourt.dropFirst()
        return depuisJours.map { "\(libelle), depuis \($0) j" } ?? libelle
    }
}

#if DEBUG
private func _repartition(
    analyses: Int = 0, enAttente: Int = 0, ajustes: Int = 0,
    avantChangement: Int = 0, dateChangement: Date? = nil
) -> RepartitionRepasMoment {
    var r = RepartitionRepasMoment()
    r.analyses = analyses
    r.enAttente = enAttente
    r.ajustes = ajustes
    r.avantChangementRatio = avantChangement
    r.dateChangementRatio = dateChangement
    r.libelleMoment = "dîner"
    r.libelleMomentPluriel = "dîners"
    return r
}

#Preview("Trois états") {
    let profil = ProfilRatio(grammesParUnite: 10, libelle: "midi")
    VStack(spacing: 12) {
        ValidationRatioCard(validation: ValidationRatio(doseSaisie: 9.5, doseSuggeree: 9.5, profil: profil))
        ValidationRatioCard(validation: ValidationRatio(doseSaisie: 0, doseSuggeree: 9.5, profil: profil))
        ValidationRatioCard(validation: ValidationRatio(doseSaisie: 6.5, doseSuggeree: 4.5, profil: profil))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

/// Le ratio est respecté sur la part repas, l'ajustement est signalé à part :
/// carte verte + badge ambre, jamais un faux « dose faible ».
#Preview("Avec ajustement") {
    let profil = ProfilRatio(grammesParUnite: 10, libelle: "dîner")
    VStack(spacing: 12) {
        ValidationRatioCard(validation: ValidationRatio(
            doseSaisie: 12, doseSuggeree: 12, profil: profil,
            ajustements: -2, glucides: 120,
            repartition: _repartition(analyses: 7)
        ))
        ValidationRatioCard(validation: ValidationRatio(
            doseSaisie: 12, doseSuggeree: 12, profil: profil,
            ajustements: 1.5, glucides: 120
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

/// Séance récente : le ratio post-sport remplace celui du moment, et les
/// observations R1 (qui ne portent que sur les ratios par moment) disparaissent.
#Preview("Ratio sport en vigueur") {
    VStack(spacing: 12) {
        ValidationRatioCard(validation: ValidationRatio(
            doseSaisie: 8.5, doseSuggeree: 8.6,
            profil: ProfilRatio(grammesParUnite: 14, libelle: "post-musculation"),
            glucides: 120, ratioSportApplique: true,
            repartition: _repartition(analyses: 7)
        ))
        ValidationRatioCard(validation: ValidationRatio(
            doseSaisie: 12, doseSuggeree: 8.6,
            profil: ProfilRatio(grammesParUnite: 14, libelle: "post-course à pied"),
            glucides: 120, ratioSportApplique: true
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
