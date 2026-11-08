//
//  FeuilleClassementNuit.swift
//  diaviz
//

import SwiftUI

extension ClassementManuelNuit {
    var couleur: Color {
        switch self {
        case .concluante:                         return .green
        case .deriveMontante, .deriveDescendante: return .orange
        case .hypo:                               return .red
        case .ecartee:                            return .secondary
        }
    }

    var icone: String {
        switch self {
        case .concluante:               return "checkmark"
        case .deriveMontante:           return "arrow.up.right"
        case .deriveDescendante, .hypo: return "arrow.down.right"
        case .ecartee:                  return ""
        }
    }
}

/// Feuille « Modifier » de la carte « Verdict de la nuit » : le calcul de
/// l'app (le choisir annule le classement manuel), puis les autres statuts.
struct FeuilleClassementNuit: View {

    let nuit: NightChartData
    /// `nil` = revenir au calcul de l'app.
    let onChoix: (ClassementManuelNuit?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Calcul de l'app") {
                    ligne(nuit.classementCalcul, detail: nuit.motifCalcul, cochee: nuit.classementManuel == nil) {
                        onChoix(nil)
                    }
                }
                Section {
                    ForEach(ClassementManuelNuit.allCases.filter { $0 != nuit.classementCalcul }) { statut in
                        ligne(statut, detail: nil, cochee: nuit.classementManuel == statut) {
                            onChoix(statut)
                        }
                    }
                } header: {
                    Text("Votre classement")
                } footer: {
                    Text("Votre classement remplace le calcul dans le verdict, jusqu'à ce que vous reveniez au calcul de l'app.")
                }
            }
            .navigationTitle("Nuit du \(ConstatVerdictBasale.jour(nuit.date))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func ligne(
        _ statut: ClassementManuelNuit, detail: String?, cochee: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PastilleClassement(statut: statut)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statut.libelle).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if cochee {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityAddTraits(cochee ? .isSelected : [])
    }
}

private struct PastilleClassement: View {
    let statut: ClassementManuelNuit

    var body: some View {
        Group {
            if statut == .ecartee {
                Circle().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
            } else {
                Circle().fill(statut.couleur).overlay {
                    Image(systemName: statut.icone)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
