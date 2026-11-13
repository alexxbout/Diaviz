//
//  DetailAnalyseBasaleVue.swift
//  diaviz
//
//  Created by Alexandre on 16/05/2026.
//

import SwiftData
import SwiftUI

/// Page « Analyse du coucher » — hub des deux sous-analyses du coucher,
/// parcourues via les **pills** :
///
///   1. **Tendance basale** (B1)     — verdict, courbes, timeline, répartition,
///      historique de dose, résumé IA
///   2. **Hypos au coucher** (B2+B3) — fusion endormissement + corrections,
///      focus hypo : métriques comptées, soirs listés, « Comparer à ce soir »
///
/// En-tête : rangée de **pills draguables** (`PillsCoucher`) posée **fixe** au
/// dessus du contenu scrollable.
///
/// L'état `mode` / `indexSelectionne` du chart B1 vit ici pour que le tap
/// timeline puisse basculer le picker sur « Par nuit » et aligner la nuit.
struct DetailAnalyseBasaleVue: View {

    let analyse: AnalyseBasaleDetail
    let endormissement: AnalyseEndormissement
    let corrections: AnalyseCorrections

    /// Fusion B2+B3 dérivée à la volée (calcul pur, instantané) — la timeline
    /// B1 fournit la catégorie de nuit affichée dans la sheet détail de soirée.
    private var hyposCoucher: AnalyseHyposCoucher {
        CalculHyposCoucher.analyser(
            endormissement: endormissement,
            corrections: corrections,
            timeline: analyse.timeline,
            changementDoseRecent: analyse.changementDoseRecent
        )
    }

    /// Appelé à l'apparition de la page avec le snapshot `analyse`
    /// **réellement affiché** — le parent (`CarteAnalyseCoucher`) y marque ce
    /// verdict précis comme vu (efface le badge de l'onglet Analyses et le
    /// point « nouveau » de la carte sommaire). Marquer d'après ce snapshot
    /// plutôt que le service live évite qu'un recalcul concurrent (déclenché
    /// par un retour sur l'onglet Analyses) invalide la marque juste posée.
    var onApparition: ((AnalyseBasaleDetail) -> Void)? = nil

    // Page affichée (index dans `SousAnalyseCoucher.allCases`).
    @State private var selection: Int = 0

    // État du chart B1 lifté ici pour que le tap timeline puisse y agir.
    @State private var mode: ModeAffichageGraphiqueBasale = .toutes
    @State private var indexSelectionne: Int = 0

    /// Guide de lecture B1, ouvert depuis le bouton en pied de page.
    @State private var afficherGuide = false

    /// Service de lecture des stades de sommeil HealthKit — instance propre à
    /// cette page (l'autorisation elle-même est demandée une fois au boot de
    /// l'app, voir `AppTabVues`). Lecture à la demande, jamais persistée.
    #if DEMO
    @State private var sleepService = LecteurSommeilDemo()
    #else
    @State private var sleepService = HealthKitSleepService()
    #endif
    /// Stades de sommeil de la nuit actuellement affichée en vue « Par
    /// nuit » — `[]` par défaut : overlay absent tant que rien n'est chargé
    /// (dégradation gracieuse, jamais de bande approximative).
    @State private var sleepStages: [SleepStageInterval] = []

    @Environment(\.modelContext) private var modelContext

    private let sections = SousAnalyseCoucher.allCases

    /// Sous-analyse actuellement affichée.
    private var pageCourante: SousAnalyseCoucher {
        sections[min(selection, sections.count - 1)]
    }

    /// Pills dérivées des sections (icône + titre). Toutes teintées de la même
    /// couleur — celle de la première section (violet) — pour un sélecteur
    /// visuellement homogène.
    private var pills: [PillCoucher] {
        let teinte = sections.first?.couleur ?? .indigo
        return sections.enumerated().map { index, s in
            PillCoucher(id: index, icone: s.icone, titre: s.titre, couleur: teinte)
        }
    }

    /// Aucune valeur par défaut : les snapshots mockés ne doivent pas être
    /// atteignables depuis le chemin de production — un appelant qui oublie un
    /// argument afficherait un faux constat. Les previews passent leurs
    /// fixtures explicitement.
    init(analyse: AnalyseBasaleDetail,
         endormissement: AnalyseEndormissement,
         corrections: AnalyseCorrections,
         onApparition: ((AnalyseBasaleDetail) -> Void)? = nil) {
        self.analyse = analyse
        self.endormissement = endormissement
        self.corrections = corrections
        self.onApparition = onApparition
    }

    var body: some View {
        // Pills flottantes FIXES en overlay ; le contenu défile DESSOUS pour
        // donner de la matière au Liquid Glass (sinon posé sur le gris plat, il
        // paraît terne). Le contenu est décalé de la hauteur des pills pour ne
        // pas démarrer caché derrière elles au repos.
        ScrollView(.vertical) {
            contenuPage
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.22), value: selection)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) {
            // Posées en bas du bandeau, puis accrochées sous la barre une
            // fois le bandeau remonté.
            PillsSurBandeau(
                selection: $selection,
                items: pills,
                teinteActive: (pageCourante == .basale ? EnTeteAnalyse.Ambiance.nuit : .coucher).palette.profond
            )
        }
        .background(Color(.systemGroupedBackground))
        .pageAvecBandeau(titre: pageCourante.titre, debordHaut: 0)
        .onAppear { onApparition?(analyse) }
        .task(id: indexSelectionne) { await chargerStadesSommeil() }
    }

    /// Recharge les stades de sommeil de la nuit sélectionnée. Silencieux et
    /// dégradé : réglage désactivé, HealthKit indisponible (simulateur) ou
    /// aucune donnée cette nuit-là → `sleepStages` reste `[]`, l'overlay ne
    /// s'affiche simplement pas.
    private var sommeilDisponible: Bool {
        #if DEMO
        LecteurSommeilDemo.disponible
        #else
        HealthKitSleepService.disponible
        #endif
    }

    private func chargerStadesSommeil() async {
        guard ProfilService.shared.profil.preferencesAvancees.overlaySommeilActive ?? true,
              sommeilDisponible,
              let nuit = analyse.nightChartData.indices.contains(indexSelectionne)
                ? analyse.nightChartData[indexSelectionne] : nil,
              let debut = nuit.glucoseValues.first?.time,
              let fin = nuit.glucoseValues.last?.time
        else {
            sleepStages = []
            return
        }
        sleepStages = await sleepService.stades(sur: debut...fin)
    }

    // MARK: - Contenu de la page sélectionnée

    @ViewBuilder
    private var enTete: some View {
        switch pageCourante {
        case .basale:
            EnTeteAnalyse(
                titre: "Tendance basale",
                accroche: "La pente de vos nuits profondes, mesurée depuis votre prise de lente.",
                ambiance: .nuit,
                reserveBas: PillsCoucher.hauteur
            )
        case .hyposCoucher:
            EnTeteAnalyse(
                titre: "Hypos au coucher",
                accroche: "Ce qui suit vos soirées, selon la façon dont elles commencent.",
                ambiance: .coucher,
                reserveBas: PillsCoucher.hauteur
            )
        }
    }

    /// Contenu de la sous-analyse courante. Le `.id(selection)` le recrée à
    /// chaque changement de page → transition d'opacité entre sections.
    private var contenuPage: some View {
        VStack(spacing: 12) {
            // Un seul bandeau pour les deux analyses : sa couleur et son texte
            // suivent l'onglet, en fondu avec le reste de la page (`.id`).
            enTete
                .padding(.bottom, 12)
            switch pageCourante {
            case .basale:        contenuBasale
            case .hyposCoucher:
                PageHyposCoucher(
                    analyse: hyposCoucher,
                    nuitsB1: analyse.nightChartData
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(selection)
        .transition(.opacity)
    }

    /// Contenu B1 — verdict, courbes, timeline, répartition, historique de
    /// dose et résumé IA. La carte « Sur quoi se base ce verdict » a été
    /// fondue dans la carte verdict : elle répétait nuits analysées, dérive
    /// moyenne et nuits exclues ; seuls ses motifs étaient uniques.
    private var contenuBasale: some View {
        // Trois groupes nommés plutôt que six cartes au même écart : sans
        // titres, rien ne dit lesquelles répondent à la même question. Les
        // cartes gardent leur en-tête interne — il précise le contenu
        // (« Glycémie nocturne »), le titre de groupe dit l'intention
        // (« Nuit par nuit ») — sauf la carte verdict, qui n'en a pas.
        //
        // 8pt à l'intérieur d'un groupe, 24 entre deux : c'est l'écart qui
        // porte l'information, pas une ligne de séparation.
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Verdict")
                CarteVerdictBasale(analyse: analyse)
            }

            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Nuit par nuit")
                CourbesNocturnesChart(
                    nights: analyse.nightChartData,
                    mode: $mode,
                    indexSelectionne: $indexSelectionne,
                    chargePour: { ChargeActiveService.shared.contexte?.synthese(a: $0) },
                    sleepStages: sleepStages
                )
                TimelineNuitsVue(
                    timeline: analyse.timeline,
                    onNightSelected: { date in basculerSurNuit(date: date) }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                TitreSection(texte: "Vue d'ensemble")
                RepartitionNuitsVue(analyse: analyse)
                DoseHistoryCard(changes: analyse.doseHistory)
            }

            // Résumé et guide restent sans titre : ce sont des compléments de
            // lecture, pas une quatrième question posée aux données.
            VStack(alignment: .leading, spacing: 12) {
                if analyse.verdict != .donneesInsuffisantes,
                   let resume = analyse.resumeIA {
                    CarteResumeIA(texte: resume)
                }

                boutonGuide
            }
        }
    }

    /// Pied de page B1 — ouvre le guide de lecture. Placé ici plutôt qu'en
    /// barre de navigation : la page porte deux analyses, un bouton de barre
    /// serait ambigu, et on le découvre naturellement en finissant de lire.
    private var boutonGuide: some View {
        Button {
            afficherGuide = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                Text("Comment lire cette analyse")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $afficherGuide) {
            SheetGuideTendanceBasale()
        }
    }

    // MARK: - Helpers

    /// Cherche la nuit dans `nightChartData` qui matche le jour calendaire
    /// de la date tappée, bascule le chart sur « Par nuit » et positionne
    /// `indexSelectionne` dessus.
    private func basculerSurNuit(date: Date) {
        let cal = Calendar.current
        let jourTape = cal.startOfDay(for: date)
        guard let idx = analyse.nightChartData.firstIndex(where: {
            cal.startOfDay(for: $0.date) == jourTape
        }) else {
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            mode = .parNuit
            indexSelectionne = idx
        }
    }
}

// MARK: - Carte résumé IA

/// Carte LLM — texte court (~5 lignes) résumant le verdict en langage
/// naturel + disclaimer « Contenu généré par IA, à vérifier. ».
private struct CarteResumeIA: View {

    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(texte)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Text("Contenu généré par IA, à vérifier.")
                .font(.caption.italic())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(NiveauCarte.carte.forme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Résumé généré par IA. \(texte). Contenu généré par IA, à vérifier.")
    }
}


// MARK: - Aperçus

#if DEBUG
#Preview("Page - Normal (verdict sufficient)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockStandard14j, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - Pipeline réel (synthétique)") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: CalculAnalyseBasale.apercu(), endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - Recent change") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockRecentChange, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - No data") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockNoData, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Page - Basale adaptée") {
    NavigationStack {
        DetailAnalyseBasaleVue(analyse: .mockAdaptee, endormissement: .mock, corrections: .mock)
    }
}

#Preview("Sheet explicative") {
    SheetExplicativeBasale()
}
#endif

/// Sélecteur d'onglet posé sur le bandeau : un conteneur Liquid Glass et
/// une pilule blanche qu'on touche ou qu'on attrape et fait glisser.
///
/// Pendant le glissement, la pilule suit le doigt au point près ; au lâcher,
/// elle se cale sur l'onglet le plus proche (élan compris). L'onglet ne
/// change qu'au lâcher : reconstruire la page sous le doigt saccadait.
///
/// Suit le bas du bandeau tant qu'il est visible, puis reste accroché sous
/// la barre de navigation, libellés inactifs en couleur de texte normale.
private struct PillsSurBandeau: View {
    @Binding var selection: Int
    let items: [PillCoucher]
    /// Couleur du libellé actif : la teinte profonde du bandeau courant.
    let teinteActive: Color

    @Environment(EtatBandeau.self) private var bandeau: EtatBandeau?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    @Environment(\.accessibilityReduceTransparency) private var reduireTransparence

    /// Largeur d'un onglet : celle du plus long libellé, pour des pilules
    /// égales et un calage net.
    @State private var largeurs: [Int: CGFloat] = [:]
    /// Position de la pilule pendant un glissement, `nil` au repos.
    @State private var positionGlissee: CGFloat?
    @State private var debutGlissement: CGFloat = 0

    private var surBandeau: Bool { !(bandeau?.replie ?? false) }
    private var largeurOnglet: CGFloat { max(largeurs.values.max() ?? 0, 60) }
    private var rangSelection: Int { items.firstIndex { $0.id == selection } ?? 0 }
    private var positionRepos: CGFloat { CGFloat(rangSelection) * largeurOnglet }
    private var position: CGFloat { positionGlissee ?? positionRepos }
    /// Onglet sous la pilule — sert à colorer les libellés pendant le geste.
    private var rangSousPilule: Int {
        min(max(Int((position / largeurOnglet).rounded()), 0), items.count - 1)
    }

    private var ressort: Animation? {
        reduireAnimations ? nil : .spring(duration: 0.35, bounce: 0.22)
    }

    var body: some View {
        let haut = bandeau.map {
            max($0.margeHaute + 6, $0.basBandeau - PillsCoucher.hauteur + 8)
        } ?? 8
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                .frame(width: largeurOnglet)
                // Légère dilatation tenue en main, comme les contrôles iOS.
                .scaleEffect(positionGlissee == nil || reduireAnimations ? 1 : 1.06)
                .offset(x: position)
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { rang, item in
                    libelle(item, rang: rang)
                }
            }
        }
        .frame(width: largeurOnglet * CGFloat(items.count), height: 40)
        .contentShape(Capsule())
        .gesture(geste)
        .padding(4)
        .background {
            if reduireTransparence {
                Capsule().fill(surBandeau ? Color.black.opacity(0.35) : Color(.secondarySystemBackground))
            }
        }
        .glassEffect(reduireTransparence ? .identity : .regular.interactive(), in: .capsule)
        .padding(.top, haut)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: rangSousPilule)
        .animation(reduireAnimations ? nil : .smooth(duration: 0.25), value: surBandeau)
        .animation(ressort, value: positionGlissee == nil)
    }

    private func libelle(_ item: PillCoucher, rang: Int) -> some View {
        let actif = rang == rangSousPilule
        return Label(item.titre, systemImage: item.icone)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeurs[item.id] = $0 }
            .frame(width: largeurOnglet)
            .foregroundStyle(actif ? teinteActive : (surBandeau ? Color.white : Color.primary))
            .animation(reduireAnimations ? nil : .smooth(duration: 0.2), value: actif)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(item.id == selection ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { choisir(rang: rang) }
    }

    private var geste: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if positionGlissee == nil {
                    // Un toucher hors de la pilule ne l'attrape pas : il
                    // vaudra sélection au lâcher.
                    let surPilule = abs(g.startLocation.x - (positionRepos + largeurOnglet / 2)) <= largeurOnglet / 2
                    guard surPilule, abs(g.translation.width) > 2 else { return }
                    debutGlissement = positionRepos
                }
                let max = largeurOnglet * CGFloat(items.count - 1)
                let brute = debutGlissement + g.translation.width
                // Résistance élastique au-delà des bords.
                let bornee = brute < 0 ? brute / 3 : (brute > max ? max + (brute - max) / 3 : brute)
                positionGlissee = bornee
            }
            .onEnded { g in
                if positionGlissee != nil {
                    let elan = debutGlissement + g.predictedEndTranslation.width
                    choisir(rang: Int((elan / largeurOnglet).rounded()))
                } else {
                    choisir(rang: Int(g.location.x / largeurOnglet))
                }
            }
    }

    private func choisir(rang: Int) {
        let r = min(max(rang, 0), items.count - 1)
        withAnimation(ressort) {
            positionGlissee = nil
            selection = items[r].id
        }
    }
}
