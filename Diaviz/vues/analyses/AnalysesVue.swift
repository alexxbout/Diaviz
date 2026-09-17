//
//  AnalysesView.swift
//  diaviz
//
//  Created by Alexandre on 19/04/2026.
//

import SwiftUI
import SwiftData

/// Page Analyses — **sommaire** des analyses disponibles. Chaque section
/// est une carte simple qui pousse une page dédiée via `NavigationLink`.
///
/// La page elle-même ne porte **aucun graphique** : c'est un index. Les
/// chiffres, courbes et tableaux vivent dans les pages de détail
/// (`DetailAnalyseBasaleVue`, etc.) pour que l'utilisateur puisse parcourir
/// d'un coup d'œil les verdicts sans charger 5 graphiques.
///
/// Header App Store style (titre + avatar) géré par `EnTetePage`, présent
/// à l'identique sur les quatre onglets racines.
struct AnalysesVue: View {

    @Environment(\.modelContext) private var modelContext

    /// Assembleur B1 réel — instance **partagée** injectée par `AppTabVues`
    /// (pas un `@State` privé) : l'accueil et le badge de cet onglet doivent
    /// voir la même instance pour que « marquer comme vu » se propage partout.
    @Environment(AnalyseBasaleService.self) private var basaleService
    @Environment(AnalyseEndormissementService.self) private var endormissementService
    @Environment(AnalyseCorrectionsService.self) private var correctionsService

    /// Override pour previews : quand fourni, court-circuite le service réel
    /// (et le `.task` de démarrage) pour exercer les états visuels mockés.
    private let coucherOverride: ResumeAnalyseCoucher?

    init(coucher: ResumeAnalyseCoucher? = nil) {
        self.coucherOverride = coucher
    }

    /// Résumé affiché : override de preview, sinon dérivé des trois services réels.
    private var coucher: ResumeAnalyseCoucher {
        coucherOverride ?? basaleService.resumeCoucher(
            endormissement: endormissementService.analyse,
            corrections: correctionsService.analyse
        )
    }

    /// Analyses réelles passées à la carte (→ page détail). Toujours celles des
    /// services, y compris en preview : les services non démarrés exposent leur
    /// état vide, qui est un état légitime — jamais un snapshot mocké, qui
    /// afficherait un faux constat.
    private var analyseReelle: AnalyseBasaleDetail { basaleService.analyse }
    private var endormissementReel: AnalyseEndormissement { endormissementService.analyse }
    private var correctionsReelles: AnalyseCorrections { correctionsService.analyse }

    /// `true` tant qu'au moins une des 3 analyses recalcule — remplace le
    /// chevron de la carte par un spinner (`CarteAnalyseCoucher.chargement`).
    private var chargementEnCours: Bool {
        coucherOverride == nil
            && (basaleService.enCalcul || endormissementService.enCalcul || correctionsService.enCalcul)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Analyses")

                // Pas de `ScrollView` : les cartes sommaires tiennent dans
                // l'écran, et le rebond au scroll d'une page non remplie
                // donnait une impression de flottement. Même parti pris que
                // le Journal — `Spacer` en dessous absorbe l'espace restant.
                //
                // Spacing 28pt entre sections — cohérent avec l'accueil,
                // donne à chaque carte sommaire l'espace de respirer.
                VStack(spacing: 28) {
                    CarteAnalyseCoucher(
                        resume: coucher,
                        analyse: analyseReelle,
                        endormissement: endormissementReel,
                        corrections: correctionsReelles,
                        chargement: chargementEnCours,
                        onOuvrirDetail: { analyseAffichee in
                            basaleService.marquerVerdictCommeVu(pour: analyseAffichee)
                        }
                    )
                }
                // Même correction que l'accueil — marge système au lieu
                // d'un 16 codé en dur, cohérente avec `JournalVue`.
                .padding(.horizontal)
                .padding(.vertical, 16)

                Spacer(minLength: 0)
            }
            .background(Color(.systemGroupedBackground))
        }
        // On arrive sur la page **immédiatement** (le VStack ci-dessus rend
        // avec l'état déjà connu des services, même stale) ; le recalcul tourne
        // en tâche de fond — c'est le calcul (segmentation des nuits), pas
        // l'affichage, qui causait le lag perçu au changement d'onglet. Seul
        // le chevron de la carte devient un spinner pendant ce temps.
        //
        // Re-sync à chaque retour sur la page (ajout d'une lente/CGM depuis un
        // autre onglet → l'analyse se met à jour sans action). `Task` dans
        // `onAppear` est un choix délibéré ici (pas `.task`) : on veut relancer
        // le recalcul à **chaque** apparition, pas seulement à la première.
        .onAppear {
            guard coucherOverride == nil else { return }
            let premierBoot = !basaleService.estDemarre
            Task {
                await basaleService.demarrer(contexte: modelContext)
                async let endo: Void = endormissementService.demarrer(contexte: modelContext, basale: basaleService)
                async let corr: Void = correctionsService.demarrer(contexte: modelContext, basale: basaleService)
                _ = await (endo, corr)

                guard !premierBoot else { return }
                await basaleService.recharger()
                async let endoR: Void = endormissementService.recharger()
                async let corrR: Void = correctionsService.recharger()
                _ = await (endoR, corrR)
            }
        }
    }
}

// MARK: - Aperçus

#if DEBUG
#Preview("Analyses - Coucher défaut") {
    AnalysesVue(coucher: .mockDefault)
        .environment(ProfilService.mockComplet())
        .environment(AnalyseBasaleService())
}

#Preview("Analyses - Coucher mature") {
    AnalysesVue(coucher: .mockMature)
        .environment(ProfilService.mockComplet())
        .environment(AnalyseBasaleService())
}

#Preview("Analyses - Coucher débutant") {
    AnalysesVue(coucher: .mockDebutant)
        .environment(ProfilService.mockComplet())
        .environment(AnalyseBasaleService())
}
#endif
