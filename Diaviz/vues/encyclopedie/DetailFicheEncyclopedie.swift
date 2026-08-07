//
//  DetailFicheEncyclopedie.swift
//  diaviz
//

import SwiftUI

/// Corps d'une fiche : sections courtes, points chiffrés quand la source en
/// donne, puis les références.
///
/// Même registre éditorial que `SheetExplicativeBasale` — descriptif, au
/// constat. Aucune donnée de l'utilisateur n'entre dans cet écran.
struct DetailFicheEncyclopedie: View {

    let fiche: FicheEncyclopedie

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                entete

                ForEach(fiche.sections) { section in
                    sectionVue(section)
                }

                if !fiche.analysesLiees.isEmpty {
                    analysesLiees
                }

                sources

                Text("Ces informations résument des publications scientifiques et ne constituent pas un avis médical. Toute décision concernant votre traitement relève de votre médecin.")
                    .font(.caption.italic())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(fiche.titre)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: fiche.icone)
                .font(.title)
                .foregroundStyle(.tint)

            Text(fiche.titre)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(fiche.resume)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Sections

    private func sectionVue(_ section: FicheEncyclopedie.SectionFiche) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.titre)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(section.texte)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !section.points.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(section.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(.tint)
                                .frame(width: 4, height: 4)
                                .offset(y: -2)
                            Text(point)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Analyses liées
    //
    // Simple repère de lecture : quelles analyses de l'app touchent au même
    // sujet. Aucun lien avec les données — pas de navigation, pas de chiffre.

    private var analysesLiees: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analyses concernées")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(fiche.analysesLiees, id: \.self) { analyse in
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(analyse)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(fiche.sources) { source in
                VStack(alignment: .leading, spacing: 3) {
                    if let url = source.url {
                        Link(destination: url) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(source.titre)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                        }
                    } else {
                        Text(source.titre)
                            .font(.subheadline)
                    }
                    Text(source.reference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DetailFicheEncyclopedie(fiche: CatalogueEncyclopedie.fiches[0])
    }
}
