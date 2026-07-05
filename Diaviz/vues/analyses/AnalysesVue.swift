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

    /// Assembleur B1 réel — branché sur le hub au boot. Produit l'analyse et le
    /// résumé de la carte « Analyse du coucher ».
    @State private var basaleService = AnalyseBasaleService()

    /// Override pour previews : quand fourni, court-circuite le service réel
    /// (et le `.task` de démarrage) pour exercer les états visuels mockés.
    private let coucherOverride: ResumeAnalyseCoucher?

    init(coucher: ResumeAnalyseCoucher? = nil) {
        self.coucherOverride = coucher
    }

    /// Résumé affiché : override de preview, sinon dérivé du service réel.
    private var coucher: ResumeAnalyseCoucher {
        coucherOverride ?? basaleService.resumeCoucher
    }

    /// Analyse réelle passée à la carte (→ page détail). `nil` en preview pour
    /// retomber sur le snapshot mocké routé par le verdict.
    private var analyseReelle: AnalyseBasaleDetail? {
        coucherOverride == nil ? basaleService.analyse : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnTetePage(titre: "Analyses")

                ScrollView {
                    // Spacing 28pt entre sections — cohérent avec l'accueil,
                    // donne à chaque carte sommaire l'espace de respirer.
                    VStack(spacing: 28) {
                        CarteAnalyseCoucher(resume: coucher, analyse: analyseReelle)
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        // Re-sync automatique : on recalcule à chaque retour sur la page
        // (ajout d'une lente/CGM depuis un autre onglet → l'analyse se met à
        // jour sans action). Le premier passage démarre le service (qui calcule
        // déjà) ; les suivants forcent un `recharger()`.
        .onAppear {
            guard coucherOverride == nil else { return }
            let premierBoot = !basaleService.estDemarre
            basaleService.demarrer(contexte: modelContext)
            if !premierBoot { basaleService.recharger() }
        }
    }
}

// MARK: - Aperçus

#Preview("Analyses - Coucher défaut") {
    AnalysesVue(coucher: .mockDefault)
        .environment(ProfilService.mockComplet())
}

#Preview("Analyses - Coucher mature") {
    AnalysesVue(coucher: .mockMature)
        .environment(ProfilService.mockComplet())
}

#Preview("Analyses - Coucher débutant") {
    AnalysesVue(coucher: .mockDebutant)
        .environment(ProfilService.mockComplet())
}
