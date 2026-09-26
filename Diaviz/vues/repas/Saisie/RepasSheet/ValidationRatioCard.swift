//
//  ValidationRatioCard.swift
//  diaviz
//
//  Created by Alexandre on 29/04/2026.
//

import SwiftUI

/// Carte affichant la cohérence entre la dose saisie et la dose suggérée
/// par le ratio actif. 3 variantes selon l'état (cohérente/faible/élevée).
///
/// Design simple : icône en cercle coloré + titre + badge profil + détail,
/// sur un fond uni à `0.10` d'opacité dans la couleur d'accent. Pas de bordure
/// extérieure (qui se faisait clipper par le `Form` parent).
struct ValidationRatioCard: View {

    let validation: ValidationRatio
    /// Charge active au moment du repas (niveau vs référence), affichée quel que
    /// soit le ratio en vigueur — contrairement au ratio post-sport, elle
    /// ne dépend pas d'une séance récente précise. `nil` si indisponible.
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
            FeuilleExplicationValidation(validation: validation)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(titre)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            // Deux badges de nature différente : le ratio **en vigueur**
            // (celui qui a produit le verdict) et, le cas échéant, la
            // déviation volontaire que l'app ne juge pas.
            //
            // Côte à côte seulement s'ils tiennent réellement sur la ligne :
            // « 1u/15g profil post-musculation » à côté d'un ajustement se
            // faisait comprimer et le texte partait sur trois lignes dans la
            // capsule. `ViewThatFits` bascule alors en pile verticale, et les
            // badges gardent leur largeur naturelle (`fixedSize`).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { badges }
                VStack(alignment: .leading, spacing: 6) { badges }
            }

            if validation.etat != .coherente {
                Text(ligneEcart)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.top, 2)
            }

            // Ratio réellement appliqué une fois l'ajustement inclus : un
            // fait, sans verdict. Le verdict au-dessus ne porte que sur la
            // dose de base, seule part censée couvrir les glucides.
            if let ratioEffectif = validation.ratioEffectifApresAjustement {
                Text(ligneRatioEffectif(ratioEffectif))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.top, 2)
            }

            // Observation R1 (mining du ratio observé) : jamais une dose à
            // utiliser, toujours restituée avec ses dénominateurs bruts. Rien
            // sous ratio sport — le mining ne couvre que les ratios par
            // moment de la journée, il n'a rien à dire sur celui-ci.
            if !validation.ratioSportApplique {
                if let ecartObserve = validation.ecartObserve {
                    Text(ligneEcartObserve(ecartObserve))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    // Pas d'écart significatif : dit combien de repas
                    // alimentent déjà l'analyse de ce moment — jamais une
                    // conclusion, juste où on en est.
                    Text(ligneEffectif)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

        }
    }

    /// Badge charge — même famille visuelle que `badgeProfil`/`badgeAjustement`
    /// (capsule, icône + texte bold), affiché **quel que soit le ratio en
    /// vigueur** (pas seulement le post-sport). Niveau de charge active au
    /// moment du repas, avec la durée depuis la dernière bascule.
    @ViewBuilder
    private func badgeCharge(_ niveau: NiveauChargeActive, depuisJours: Int?) -> some View {
        let couleur = niveau.couleur
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.caption2.bold())
            Text(depuisJours.map { "Charge \(niveau.libelleCourt) · \($0)j" } ?? "Charge \(niveau.libelleCourt)")
                .font(.caption.bold())
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(couleur)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(couleur.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private var badges: some View {
        badgeProfil
        if validation.ajustements != 0 {
            badgeAjustement
        }
        if case let .disponible(_, niveau, depuisJours)? = chargeSynthese?.etat {
            badgeCharge(niveau, depuisJours: depuisJours)
        }
    }

    /// Écart volontaire signalé sans être jugé — teinte ambre fixe, jamais la
    /// couleur d'état de la carte : un ajustement n'est pas une erreur, et
    /// faire virer la carte au rouge à chaque fois apprendrait à ignorer le
    /// rouge.
    private var badgeAjustement: some View {
        HStack(spacing: 4) {
            Image(systemName: "slider.horizontal.3")
                .font(.caption2.bold())
            Text("Ajustement \(validation.ajustements.ecartDoseFormate)")
                .font(.caption.bold())
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.14), in: Capsule())
    }

    private func ligneRatioEffectif(_ grammesParUnite: Double) -> String {
        let total = validation.doseSaisie + validation.ajustements
        let formatteRatio = grammesParUnite == floor(grammesParUnite)
            ? String(format: "1u/%.0fg", grammesParUnite)
            : String(format: "1u/%.1fg", grammesParUnite)
        return "Ajustement inclus : \(format(total))u pour \(format(validation.glucides))g, soit \(formatteRatio)."
    }

    /// Formulation factuelle de l'écart observé — jamais « utilise tel ratio »,
    /// toujours les décomptes bruts.
    private func ligneEcartObserve(_ ecart: EcartRatioObserve) -> String {
        let optimal = Int((ecart.tauxOptimal * 100).rounded())
        let configure = Int((ecart.tauxConfigure * 100).rounded())
        return "Vos repas à \(ecart.trancheOptimale.libelle) ont \(optimal) % de bons résultats "
            + "(\(ecart.bonsOptimal)/\(ecart.effectifOptimal)), contre \(configure) % "
            + "(\(ecart.bonsConfigure)/\(ecart.effectifConfigure)) à votre ratio actuel."
    }

    /// Où en est l'analyse de ce moment, faute d'écart à signaler — une
    /// phrase par situation réelle, jamais une conclusion.
    ///
    /// Une phrase unique (« Aucun repas encore analysé sur ce moment »)
    /// couvrait quatre cas sans rapport : rien de saisi, saisi mais verdict
    /// en attente des glycémies, écarté volontairement, ou rendu incomparable
    /// par un changement de ratio. Elle se lisait comme « l'app ignore mes
    /// saisies » alors que les repas étaient bien là.
    private var ligneEffectif: String {
        let r = validation.repartition
        let un = r.libelleMoment
        let plusieurs = r.libelleMomentPluriel

        // Cas nominal : des repas alimentent déjà la comparaison. Ce qui
        // reste en attente est mentionné, parce que c'est la seule part qui
        // bougera d'elle-même.
        if r.analyses > 0 {
            let base = "\(r.analyses) \(r.analyses > 1 ? plusieurs : un) analysé\(r.analyses > 1 ? "s" : ""), pas d'écart à signaler."
            guard r.enAttente > 0 else { return base }
            return base + " \(r.enAttente) en attente des glycémies."
        }

        // Rien d'analysé : dire *pourquoi*, du motif le plus temporaire au
        // plus définitif.
        if r.enAttente > 0 {
            return "\(r.enAttente) \(r.enAttente > 1 ? plusieurs : un) enregistré\(r.enAttente > 1 ? "s" : ""), verdict en attente des glycémies."
        }
        if let date = r.dateChangementRatio, r.avantChangementRatio > 0 {
            let jour = date.formatted(.dateTime.day().month(.abbreviated))
            return "Ratio changé le \(jour) : les \(r.avantChangementRatio) \(plusieurs) d'avant ne sont plus comparables."
        }
        if r.ecartes > 0 {
            return "\(r.ecartes) \(r.ecartes > 1 ? plusieurs : un) écarté\(r.ecartes > 1 ? "s" : "") de l'analyse : ajustement ou contexte particulier."
        }
        if r.donneesManquantes + r.sansInjection > 0 {
            let n = r.donneesManquantes + r.sansInjection
            return "\(n) \(n > 1 ? plusieurs : un) sans glycémies exploitables sur leur fenêtre."
        }
        return "Aucun \(un) enregistré pour l'instant."
    }

    /// Badge profil ratio : capsule teintée d'accent avec icône "détection
    /// auto" et libellé du profil (matin/midi/soir).
    private var badgeProfil: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
                .font(.caption2.bold())
            Text(validation.profil.description)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }

    // MARK: - Calculs visuels

    private var titre: String {
        switch validation.etat {
        case .coherente: return "Dose cohérente avec le ratio"
        case .faible:    return "Dose faible vs ratio"
        case .elevee:    return "Dose élevée vs ratio"
        }
    }

    private var nomIcone: String {
        switch validation.etat {
        case .coherente:        return "checkmark.circle.fill"
        case .faible, .elevee:  return "exclamationmark.triangle.fill"
        }
    }

    private var ligneEcart: String {
        let saisie = format(validation.doseSaisie)
        let suggeree = format(validation.doseSuggeree)
        let signe = validation.ecart >= 0 ? "+" : ""
        let ecart = "\(signe)\(format(validation.ecart))"
        return "\(saisie)u saisie · \(suggeree)u suggérée · \(ecart)u écart"
    }

    private func format(_ valeur: Double) -> String {
        valeur == floor(valeur)
            ? String(format: "%.0f", valeur)
            : String(format: "%.1f", valeur)
    }

    private var couleurAccent: Color {
        switch validation.etat {
        case .coherente: return .green
        case .faible:    return .orange
        case .elevee:    return .red
        }
    }

}

// MARK: - Sheet explicative (placeholder)

private struct FeuilleExplicationValidation: View {
    let validation: ValidationRatio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ratio en vigueur") {
                    Text(validation.profil.description)
                    if validation.ratioSportApplique {
                        Text("Ratio post-sport de votre profil — il remplace celui du moment de la journée tant que la séance est dans la fenêtre d'effet réglée.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Calcul") {
                    LabeledContent("Dose de base", value: "\(String(format: "%.1f", validation.doseSaisie))u")
                    LabeledContent("Dose suggérée", value: "\(String(format: "%.1f", validation.doseSuggeree))u")
                    LabeledContent("Écart", value: "\(String(format: "%.1f", validation.ecart))u")
                }
                if validation.ajustements != 0 {
                    Section("Ajustement") {
                        LabeledContent("Ajustement saisi", value: validation.ajustements.ecartDoseFormate)
                        Text("Exclu du calcul ci-dessus : une déviation décidée volontairement ne mesure plus le ratio. Elle est reportée telle quelle, sans verdict.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Le calcul confronte la seule dose de base du repas au ratio en vigueur. La correction d'hyperglycémie et l'IOB n'y entrent pas.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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

/// Les cinq phrases possibles de la ligne d'état, à ratio inchangé.
#Preview("États du décompte") {
    let profil = ProfilRatio(grammesParUnite: 12, libelle: "dîner")
    func carte(_ r: RepartitionRepasMoment) -> some View {
        ValidationRatioCard(validation: ValidationRatio(
            doseSaisie: 10, doseSuggeree: 10, profil: profil, glucides: 120, repartition: r
        ))
    }
    return ScrollView {
        VStack(spacing: 12) {
            carte(_repartition(analyses: 7, enAttente: 4))
            carte(_repartition(analyses: 7))
            carte(_repartition(enAttente: 4))
            carte(_repartition(avantChangement: 14, dateChangement: Calendar.current.date(byAdding: .day, value: -30, to: Date())))
            carte(_repartition(ajustes: 8))
            carte(_repartition())
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
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
