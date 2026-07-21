//
//  SheetDetailSoiree.swift
//  diaviz
//

import Charts
import SwiftUI

/// Sheet **« Détail d'une soirée »** — raconte la chaîne complète d'un soir
/// analysé (fusion B2/B3) : timeline des événements (repas → correction →
/// lente → hypo → réveil), courbe de glycémie avec fenêtre analysée
/// surlignée, courbe d'insuline active, constat B1 de la nuit, chips de
/// contexte.
///
/// Réutilisable : présentée depuis la page « Hypos au coucher » (tap sur un
/// soir) et, à terme, depuis la sheet « Comparer à ce soir ».
///
/// Les faits bruts (rapides, repas) de la nuit sont rechargés au boot via
/// `ChargeurFaitsCoucher` ; le reste vient du soir fusionné et de la
/// `NightChartData` B1 déjà calculée. Purement factuel.
struct SheetDetailSoiree: View {

    let soir: SoirCoucher
    /// Nuit B1 correspondante — porte la courbe, les zones et le constat.
    let nuitB1: NightChartData?
    /// Début du palier de dose courant (affiché sur la ligne lente).
    var changementDoseRecent: Date? = nil
    /// Ouvre le détail d'un repas (sheet dédiée, à venir). Le chevron de la
    /// ligne repas n'apparaît que si ce handler est fourni.
    var onOuvrirRepas: ((Date) -> Void)? = nil
    /// Faits injectés directement — pour les previews (court-circuite le hub).
    var faitsApercu: (rapides: [(heure: Date, dose: Double, correction: Bool)],
                      repas: [(heure: Date, glucides: Int)])? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var detail: DetailSoiree?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let detail {
                    contenu(detail)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(titreNuit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { charger() }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Chargement

    private func charger() {
        let cal = Calendar.current
        let borne = cal.date(byAdding: .day, value: -1, to: soir.date) ?? soir.date
        let faits = faitsApercu ?? (
            rapides: ChargeurFaitsCoucher.rapides(modelContext, depuis: borne),
            repas: ChargeurFaitsCoucher.repas(modelContext, depuis: borne)
        )
        let profil = ProfilService.shared.profil
        detail = CalculDetailSoiree.analyser(
            soir: soir,
            nuitB1: nuitB1,
            rapides: faits.rapides,
            repas: faits.repas,
            changementDoseRecent: changementDoseRecent,
            config: ConfigEndormissement(
                seuilHypo: Int(profil.seuilsGlycemiques.hypoglycemie),
                diaHeures: profil.dureeActionInsulineHeures,
                picMinutes: profil.insulineRapide.picActionMinutes
            )
        )
    }

    private var titreNuit: String {
        "Nuit du \(soir.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))"
    }

    // MARK: - Contenu

    @ViewBuilder
    private func contenu(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero : la courbe de glycémie de la nuit en vedette, pleine
            // largeur sans carte, tout en haut (même langage visuel que les
            // détails repas/sport). La courbe IOB agrandie la suit — les deux
            // graphiques racontent la nuit, la timeline détaille en dessous.
            if !detail.courbe.isEmpty {
                sectionGlycemie(detail)
            }
            if !detail.courbeIOB.isEmpty {
                sectionIOB(detail)
            }

            if detail.evenements.isEmpty {
                Text("Pas assez de données CGM pour reconstruire cette nuit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else {
                timeline(detail)
            }

            sectionConstatB1(detail.constatB1)
            sectionContexte
        }
        .padding(.top, 8)
    }

    // MARK: - Timeline

    private func timeline(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(detail.evenements.enumerated()), id: \.element.id) { index, evenement in
                LigneTimelineSoiree(
                    evenement: evenement,
                    estDernier: index == detail.evenements.count - 1,
                    onOuvrirRepas: onOuvrirRepas
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: - Courbe glycémie

    private func sectionGlycemie(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glycémie · 21h → 07h")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Chart {
                // Seuil hypo.
                RuleMark(y: .value("Seuil", detail.seuilHypo))
                    .foregroundStyle(Color.red.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(detail.seuilHypo)")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }

                ForEach(detail.courbe) { point in
                    LineMark(
                        x: .value("Heure", point.time),
                        y: .value("mg/dL", point.value)
                    )
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Marqueurs d'événements sur la courbe.
                ForEach(detail.evenements) { evenement in
                    if let marqueur = marqueur(evenement, courbe: detail.courbe) {
                        PointMark(
                            x: .value("Heure", marqueur.heure),
                            y: .value("mg/dL", marqueur.valeur)
                        )
                        .foregroundStyle(marqueur.couleur)
                        .symbolSize(marqueur.taille)
                    }
                }
            }
            .chartYScale(domain: domaineY(detail))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().locale(Locale(identifier: "fr_FR")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { valeur in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let v = valeur.as(Double.self) {
                            Text("\(Int(v))").font(.caption2).monospacedDigit()
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 12).padding(.bottom, 6)
            }
            .frame(height: 260)
            .accessibilityLabel(accessibiliteCourbe(detail))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Marqueur {
        let heure: Date
        let valeur: Double
        let couleur: Color
        let taille: CGFloat
    }

    /// Position + style du marqueur d'un événement sur la courbe. Repas et
    /// réveil ne sont pas marqués (timeline suffit) pour garder la courbe lisible.
    private func marqueur(_ evenement: EvenementSoiree, courbe: [GlucosePoint]) -> Marqueur? {
        func valeurA(_ t: Date) -> Double? {
            courbe.min(by: { abs($0.time.timeIntervalSince(t)) < abs($1.time.timeIntervalSince(t)) })?.value
        }
        switch evenement.genre {
        case .correction:
            guard let v = valeurA(evenement.heure) else { return nil }
            return Marqueur(heure: evenement.heure, valeur: v, couleur: .indigo, taille: 42)
        case .lente:
            guard let v = valeurA(evenement.heure) else { return nil }
            return Marqueur(heure: evenement.heure, valeur: v, couleur: .secondary, taille: 42)
        case .hypo(let valeur, _):
            return Marqueur(heure: evenement.heure, valeur: Double(valeur), couleur: .red, taille: 55)
        case .repas, .reveil:
            return nil
        }
    }

    /// Domaine Y englobant courbe + seuil hypo, avec marge de 20 mg/dL
    /// pour que la ligne de seuil ne colle jamais au bord du cadre.
    private func domaineY(_ detail: DetailSoiree) -> ClosedRange<Double> {
        let valeurs = detail.courbe.map(\.value)
        let bas = min(valeurs.min() ?? 70, Double(detail.seuilHypo)) - 20
        let haut = (valeurs.max() ?? 180) + 20
        return max(35, bas)...haut
    }

    private func accessibiliteCourbe(_ detail: DetailSoiree) -> String {
        let hypos = detail.evenements.compactMap { e -> String? in
            if case let .hypo(valeur, _) = e.genre { return "\(valeur) mg/dL à \(heureFr(e.heure))" }
            return nil
        }
        return hypos.isEmpty
            ? "Courbe de glycémie de la nuit, aucune hypoglycémie."
            : "Courbe de glycémie de la nuit. Hypoglycémies : \(hypos.joined(separator: ", "))."
    }

    // MARK: - Courbe IOB

    private func sectionIOB(_ detail: DetailSoiree) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insuline active (rapide)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Chart {
                ForEach(detail.courbeIOB, id: \.date) { point in
                    AreaMark(
                        x: .value("Heure", point.date),
                        y: .value("IOB", point.iob)
                    )
                    .foregroundStyle(Color.blue.opacity(0.12))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Heure", point.date),
                        y: .value("IOB", point.iob)
                    )
                    .foregroundStyle(Color.blue.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Repère vertical sur la première hypo — relie visuellement
                // l'IOB résiduel à l'événement.
                if detail.iobAuMomentHypo != nil,
                   let premiereHypo = detail.evenements.first(where: {
                       if case .hypo = $0.genre { return true }; return false
                   }) {
                    RuleMark(x: .value("Hypo", premiereHypo.heure))
                        .foregroundStyle(Color.red.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            // Même axe horloge que le hero glycémie au-dessus, pour lire les
            // deux graphiques alignés dans le temps. Axe Y « u » léger.
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().locale(Locale(identifier: "fr_FR")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { valeur in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = valeur.as(Double.self) {
                            Text(v == 0 ? "0" : "\(v.formatted(.number.precision(.fractionLength(0...1))))u")
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 8).padding(.bottom, 6)
            }
            .frame(height: 130)
            .accessibilityHidden(true)

            if let iobHypo = detail.iobAuMomentHypo,
               let premiereHypo = detail.evenements.first(where: {
                   if case .hypo = $0.genre { return true }; return false
               }) {
                Text("~\(String(format: "%.1f", iobHypo))u encore actif au moment de l'hypo (\(heureFr(premiereHypo.heure))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Constat B1

    @ViewBuilder
    private func sectionConstatB1(_ constat: ConstatB1Nuit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tendance basale cette nuit (B1)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                switch constat {
                case let .analysee(derive, categorie):
                    Image(systemName: symboleCategorie(categorie))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(couleurCategorie(categorie))
                    Text("Nuit profonde : dérive \(String(format: "%+d", derive)) mg/dL (\(libelleCategorie(categorie)))")
                        .font(.footnote)
                case let .exclue(motif):
                    Image(systemName: "circle.dashed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Nuit exclue de l'analyse basale — \(motif.lowercased())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .indisponible:
                    Image(systemName: "questionmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Pas de données d'analyse basale pour cette nuit")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private func symboleCategorie(_ categorie: CategorieNuit) -> String {
        switch categorie {
        case .stable:         return "arrow.right"
        case .tendanceBasse:  return "arrow.down.right"
        case .tendanceHaute:  return "arrow.up.right"
        }
    }

    private func couleurCategorie(_ categorie: CategorieNuit) -> Color {
        switch categorie {
        case .stable:         return .green
        case .tendanceBasse:  return .red
        case .tendanceHaute:  return .orange
        }
    }

    private func libelleCategorie(_ categorie: CategorieNuit) -> String {
        switch categorie {
        case .stable:         return "stable"
        case .tendanceBasse:  return "descendante"
        case .tendanceHaute:  return "ascendante"
        }
    }

    // MARK: - Contexte (chips agrandies)

    private var sectionContexte: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contexte")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            FlowLayout(spacing: 8) {
                if soir.chargeVisible {
                    ChipCharge(charge: soir.charge, taille: .large)
                }
                ForEach(soir.chipsContexte) { chip in
                    ChipContexte(chip: chip, taille: .large)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private func heureFr(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Ligne de timeline

/// Une ligne de la timeline verticale : pastille (icône selon le genre),
/// trait de liaison, titre + sous-titre factuel. La ligne repas porte un
/// chevron si un handler d'ouverture est fourni.
private struct LigneTimelineSoiree: View {

    let evenement: EvenementSoiree
    let estDernier: Bool
    var onOuvrirRepas: ((Date) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                pastille
                if !estDernier {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1.5)
                        .frame(minHeight: 18)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre)
                        .font(.footnote.weight(estAlerte ? .semibold : .medium))
                        .foregroundStyle(estAlerte ? .red : .primary)
                    Text(sousTitre)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if estRepas, onOuvrirRepas != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)
                }
            }
            .padding(.bottom, estDernier ? 0 : 14)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if estRepas { onOuvrirRepas?(evenement.heure) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titre), \(sousTitre)")
    }

    // MARK: Pastille

    private var pastille: some View {
        ZStack {
            Circle().fill(fondPastille)
            Image(systemName: symbole)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(teintePastille)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    // MARK: Dérivés par genre

    private var estRepas: Bool {
        if case .repas = evenement.genre { return true }
        return false
    }

    private var estAlerte: Bool {
        if case .hypo = evenement.genre { return true }
        return false
    }

    private var symbole: String {
        switch evenement.genre {
        case .repas:       return "fork.knife"
        case .correction:  return "syringe.fill"
        case .lente:       return "syringe.fill"
        case .hypo:        return "exclamationmark.triangle.fill"
        case .reveil:      return "sunrise.fill"
        }
    }

    private var fondPastille: Color {
        switch evenement.genre {
        case .repas:       return Color(.tertiarySystemFill)
        case .correction:  return Color.indigo.opacity(0.15)
        case .lente:       return Color.indigo.opacity(0.15)
        case .hypo:        return Color.red.opacity(0.15)
        case .reveil:      return Color.orange.opacity(0.15)
        }
    }

    private var teintePastille: Color {
        switch evenement.genre {
        case .repas:       return .secondary
        case .correction, .lente: return .indigo
        case .hypo:        return .red
        case .reveil:      return .orange
        }
    }

    private var titre: String {
        switch evenement.genre {
        case .repas(_, let resucrage): return resucrage ? "Resucrage" : "Repas"
        case .correction:  return "Correction rapide"
        case .lente:       return "Lente"
        case .hypo:        return "Hypo"
        case .reveil:      return "Réveil"
        }
    }

    private var sousTitre: String {
        let heure = heureFr(evenement.heure)
        switch evenement.genre {
        case let .repas(glucides, _):
            return "\(heure) · \(glucides)g de glucides"
        case let .correction(dose, glycemie):
            let g = glycemie.map { " · glycémie \($0) mg/dL" } ?? ""
            return "\(heure) · +\(dose.formatted())u\(g)"
        case let .lente(dose, depuis):
            let d = depuis.map {
                " · depuis le \($0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))"
            } ?? ""
            return "\(heure) · \(dose.formatted())u\(d)"
        case let .hypo(valeur, delai):
            let d = delai.map { " · t+\(formatDelai($0)) après la lente" } ?? ""
            return "\(heure) · \(valeur) mg/dL\(d)"
        case let .reveil(valeur):
            return "\(heure) · \(valeur) mg/dL"
        }
    }

    private func formatDelai(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }

    private func heureFr(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02dh%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Aperçu

#if DEBUG
#Preview("Détail soirée — pipeline réel") {
    // Exerce le vrai pipeline : nuit synthétique B1 + soir fusionné dérivé.
    let analyse = CalculAnalyseBasale.apercu()
    let nuit = analyse.nightChartData.first!
    let correction = (heure: nuit.basaleTime.addingTimeInterval(-20 * 60), dose: 4.0, correction: true)
    let soir = SoirCoucher(
        id: UUID(), date: nuit.date, glycemie: Int(nuit.startGlucose), tendance: .baisse,
        correction: 4, glucides: nil,
        sport: SportResume(type: "Course", intensite: "modéré", dureeMinutes: 45),
        iob: 1.2, charge: .intense, categorieB1: .tendanceBasse,
        enHypo: true, delaiHypoMinutes: nil, issueCorrection: .surCorrection
    )
    return SheetDetailSoiree(
        soir: soir,
        nuitB1: nuit,
        changementDoseRecent: Calendar.current.date(byAdding: .day, value: -12, to: Date()),
        onOuvrirRepas: { _ in },
        faitsApercu: (
            rapides: [correction, (heure: nuit.basaleTime.addingTimeInterval(-3 * 3600), dose: 6, correction: false)],
            repas: [(heure: nuit.basaleTime.addingTimeInterval(-3 * 3600), glucides: 65)]
        )
    )
}
#endif
