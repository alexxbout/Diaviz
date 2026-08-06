//
//  VueDiagnosticHealthKit.swift
//  diaviz
//
//  Created by Alexandre on 15/06/2026.
//

import SwiftData
import SwiftUI

/// Vue de contrôle : demande l'accès Santé puis liste les glycémies récentes
/// (valeur, horodatage, source, appareil, métadonnées) pour voir exactement ce
/// que Dexcom écrit dans HealthKit. À lancer **sur iPhone réel**.
struct VueDiagnosticHealthKit: View {
    @State private var service = HealthKitCGMService()
    @State private var echantillons: [EchantillonCGM] = []
    @State private var chargement = false

    /// Mesures réellement stockées dans le hub (vérifie que l'ingestion marche).
    @Query private var lecturesHub: [GlucoseReading]

    @Environment(\.modelContext) private var modelContext
    @State private var reimportEnCours = false
    @State private var messageReimport: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Hub (stockées)", value: "\(lecturesHub.count)")

                Button {
                    Task { await reimporterTout() }
                } label: {
                    if reimportEnCours {
                        HStack(spacing: 8) { ProgressView(); Text("Réimport…") }
                    } else {
                        Label("Réimporter depuis Santé", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(reimportEnCours)

                if let messageReimport {
                    Text(messageReimport)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Nombre de GlucoseReading en base. Confirme que l'ingestion HealthKit alimente le hub. Le réimport oublie l'ancre de synchronisation et recharge les 7 derniers jours — utile si le hub s'est vidé alors que Santé contient toujours les données.")
            }

            if let message = service.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }

            Section {
                if chargement {
                    HStack(spacing: 8) { ProgressView(); Text("Lecture…").foregroundStyle(.secondary) }
                } else if echantillons.isEmpty {
                    Text("Aucun échantillon. Autorise l'accès à la glycémie dans Santé, puis recharge.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(echantillons) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(e.valeur) mg/dL").font(.body.monospacedDigit()).fontWeight(.semibold)
                                Spacer()
                                Text(e.date.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("source : \(e.source)").font(.caption2).foregroundStyle(.secondary)
                            if let arrow = e.trendArrow {
                                Text("trend arrow : \(arrow)").font(.caption2).foregroundStyle(.blue)
                            }
                            if let rate = e.trendRate {
                                Text("trend rate : \(rate)").font(.caption2).foregroundStyle(.blue)
                            }
                            if let appareil = e.appareil {
                                Text("appareil : \(appareil)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Text("métadonnées : \(e.metadata?.isEmpty == false ? e.metadata! : "aucune")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Glycémies récentes (\(echantillons.count))")
            } footer: {
                Text("Si la liste est vide après autorisation : aucune donnée Dexcom dans Santé, ou accès refusé (Réglages › Santé › Accès aux données).")
            }
        }
        .navigationTitle("Diagnostic HealthKit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Recharger") { Task { await recharger() } }
                    .disabled(chargement)
            }
        }
        .task { await recharger() }
    }

    private func recharger() async {
        chargement = true
        await service.demanderAcces()
        echantillons = await service.echantillonsRecents()
        chargement = false
    }

    private func reimporterTout() async {
        reimportEnCours = true
        messageReimport = nil
        await service.demanderAcces()
        let ajoutes = await service.resynchroniserToutDepuisSante(container: modelContext.container)
        messageReimport = ajoutes > 0
            ? "\(ajoutes) mesure\(ajoutes > 1 ? "s" : "") réimportée\(ajoutes > 1 ? "s" : "")."
            : "Aucune nouvelle mesure — le hub était déjà à jour."
        reimportEnCours = false
    }
}
