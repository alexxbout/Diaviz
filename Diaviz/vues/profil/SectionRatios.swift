//
//  SectionRatios.swift
//  diaviz
//
//  Created by Alexandre on 03/05/2026.
//

import SwiftUI

/// Section « RATIOS GLUCIDES / INSULINE » — picker segmenté pour
/// choisir entre un ratio unique ou des ratios par moment, puis les
/// rows de saisie correspondantes.
///
/// **Contrainte volontaire** : la bascule entre `.unique` et
/// `.parMoment` ne reporte aucune valeur. Si l'utilisateur passe de
/// l'un à l'autre, les nouveaux champs sont vides et la sheet affiche
/// « Requis » jusqu'à saisie. Cette contrainte évite les saisies
/// distraites — on veut que l'utilisateur confirme explicitement les
/// nouveaux ratios.
struct SectionRatios: View {

    @Environment(ProfilService.self) private var service

    var body: some View {
        Section {
            // MARK: Picker mode
            Picker("Mode", selection: bindingMode) {
                Text("Unique").tag(ModeRatio.unique)
                Text("Par moment").tag(ModeRatio.parMoment)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // MARK: Saisie selon le mode
            switch service.profil.modeRatio {
            case .unique:
                ligneRatioUnique
            case .parMoment:
                ligneRatioMoment(
                    libelle: "Petit-déjeuner",
                    binding: bindingRatioMoment(\.petitDejeuner, dateKeyPath: \.petitDejeuner)
                )
                ligneRatioMoment(
                    libelle: "Déjeuner",
                    binding: bindingRatioMoment(\.dejeuner, dateKeyPath: \.dejeuner)
                )
                ligneRatioMoment(
                    libelle: "Goûter",
                    binding: bindingRatioMoment(\.gouter, dateKeyPath: \.gouter)
                )
                ligneRatioMoment(
                    libelle: "Dîner",
                    binding: bindingRatioMoment(\.diner, dateKeyPath: \.diner)
                )
            }
        } header: {
            Text("Ratios glucides / insuline")
        } footer: {
            Text("""
            Ces ratios sont utilisés comme référence d'analyse \
            uniquement. L'app ne calcule pas vos doses.
            """)
        }
    }

    // MARK: - Ligne ratio unique

    private var ligneRatioUnique: some View {
        VStack(alignment: .leading, spacing: 4) {
            ligneRatio(libelle: "Ratio", binding: bindingRatioUnique)

            if service.profil.ratioUnique == nil {
                Text("Requis")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Ligne ratio par moment (avec validation locale)

    /// Variante avec mention « Requis » si la valeur est nulle —
    /// utilisée pour les quatre rows du mode `.parMoment`.
    @ViewBuilder
    private func ligneRatioMoment(
        libelle: String,
        binding: Binding<Double?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ligneRatio(libelle: libelle, binding: binding)
            if binding.wrappedValue == nil {
                Text("Requis")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Ligne ratio générique

    /// Row « libellé | valeur 1u / Xg | stepper ». Le label interne du
    /// `Stepper` est masqué car il ne sert qu'à porter le binding ;
    /// l'affichage de la valeur est posé à la main dans le `HStack`
    /// pour pouvoir le mettre en gras et appliquer la transition
    /// numérique.
    @ViewBuilder
    private func ligneRatio(
        libelle: String,
        binding: Binding<Double?>
    ) -> some View {
        HStack {
            Text(libelle)
            Spacer()
            Text(affichageRatio(binding.wrappedValue))
                .fontWeight(.bold)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: binding.wrappedValue)
                .foregroundStyle(binding.wrappedValue == nil ? .secondary : .primary)
            Stepper(
                "",
                value: bindingNonOptionnel(binding, defaut: 10),
                in: 5...30,
                step: 1
            )
            .labelsHidden()
        }
    }

    /// Texte « 1u / Xg » — ou « Non défini » en gris si binding nil.
    /// Affiché en gras pour faire ressortir la valeur dans la row.
    private func affichageRatio(_ valeur: Double?) -> String {
        guard let valeur else { return "Non défini" }
        return "1u / \(Int(valeur))g"
    }

    // MARK: - Petits utilitaires de binding

    /// Fabrique un `Binding<Double>` à partir d'un `Binding<Double?>`.
    /// Lecture : valeur ou défaut. Écriture : remonte une valeur non
    /// nulle (la première interaction matérialise le ratio).
    private func bindingNonOptionnel(
        _ source: Binding<Double?>,
        defaut: Double
    ) -> Binding<Double> {
        Binding(
            get: { source.wrappedValue ?? defaut },
            set: { nouveau in source.wrappedValue = nouveau }
        )
    }

    // MARK: - Bindings sur le modèle

    private var bindingMode: Binding<ModeRatio> {
        Binding(
            get: { service.profil.modeRatio },
            set: { nouveau in
                service.mettreAJour { profil in
                    let ancien = profil.modeRatio
                    guard ancien != nouveau else { return }
                    profil.modeRatio = nouveau
                    // Pas de transfert entre modes — on remet à zéro
                    // les valeurs du nouveau mode pour forcer la
                    // saisie explicite.
                    switch nouveau {
                    case .unique:
                        profil.ratioUnique = nil
                        profil.ratiosParMoment = RatiosParMoment()
                    case .parMoment:
                        profil.ratioUnique = nil
                        profil.ratiosParMoment = RatiosParMoment()
                    }
                    // Nouveau mode = table rase : les dates de changement de
                    // l'ancien mode n'ont plus de sens (les ratios qu'elles
                    // décrivaient viennent d'être effacés).
                    profil.datesChangementRatio = DatesChangementRatio()
                }
            }
        )
    }

    private var bindingRatioUnique: Binding<Double?> {
        Binding(
            get: { service.profil.ratioUnique },
            set: { nouveau in
                service.mettreAJour { profil in
                    let ancien = profil.ratioUnique
                    profil.ratioUnique = nouveau
                    // Stamp uniquement sur une vraie transition (valeur
                    // existante → différente) — jamais sur la configuration
                    // initiale (`nil → valeur`), qui n'invalide aucun
                    // historique.
                    if let ancien, ancien != nouveau {
                        var dates = profil.datesChangementRatioEffectives
                        dates.unique = Date()
                        profil.datesChangementRatio = dates
                    }
                }
            }
        )
    }

    /// Binding paramétré par un keyPath sur `RatiosParMoment` — évite
    /// de répéter quatre bindings quasi identiques pour chaque repas.
    /// `dateKeyPath` pointe vers le champ miroir sur `DatesChangementRatio`,
    /// stampé à la date du jour sur un vrai changement de valeur.
    private func bindingRatioMoment(
        _ keyPath: WritableKeyPath<RatiosParMoment, Double?>,
        dateKeyPath: WritableKeyPath<DatesChangementRatio, Date?>
    ) -> Binding<Double?> {
        Binding(
            get: { service.profil.ratiosParMoment[keyPath: keyPath] },
            set: { nouveau in
                service.mettreAJour { profil in
                    let ancien = profil.ratiosParMoment[keyPath: keyPath]
                    profil.ratiosParMoment[keyPath: keyPath] = nouveau
                    if let ancien, ancien != nouveau {
                        var dates = profil.datesChangementRatioEffectives
                        dates[keyPath: dateKeyPath] = Date()
                        profil.datesChangementRatio = dates
                    }
                }
            }
        )
    }
}
