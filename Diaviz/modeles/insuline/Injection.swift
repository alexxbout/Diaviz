//
//  Injection.swift
//  diaviz
//
//  Created by Alexandre on 01/05/2026.
//

import Foundation
import SwiftData

/// Une injection d'insuline enregistrée dans le hub. Englobe les trois flux
/// possibles : insuline lente quotidienne, correction rapide hors repas, et
/// bolus repas (saisi via la page Repas, exposé ici en lecture).
///
/// **Fait brut horodaté** : `heure` porte l'instant absolu, clé d'alignement
/// avec la glycémie. Entité du hub (`@Model`) : seules l'ingestion et la saisie
/// manuelle l'écrivent ; les analyses la lisent par tranches.
///
/// `repasAssocieId` remonte au repas d'origine pour les bolus ; `labelRepas` /
/// `emojiRepas` sont des dénormalisations d'affichage (évitent un join).
/// Valeurs par défaut ci-dessous : filet de secours schema-only exigé par
/// CloudKit, jamais exercé par le flux normal (l'`init` garde tous ses
/// paramètres obligatoires) — voir `GlucoseReading` pour le principe.
@Model
nonisolated final class Injection {
    var id: UUID = UUID()
    var type: TypeInsuline = TypeInsuline.lente
    var dose: Double = 0
    /// Horodatage absolu de l'injection (clé de tri / découpage).
    var heure: Date = Date.distantPast

    /// Site d'injection — décomposé en zone × côté pour rester compatible
    /// avec le `SiteInjectionPicker` et faciliter la statistique future
    /// (rotation des sites, alerte lipodystrophie).
    var zoneInjection: ZoneInjection = ZoneInjection.ventre
    var coteInjection: CoteInjection = CoteInjection.centre

    var note: String?

    /// Glycémie capillaire saisie manuellement — `nil` pour la lente et les
    /// bolus repas. Utile aux corrections vu le délai de 3h du CGM Dexcom UE.
    var glycemieAuMoment: Double?

    /// `nil` sauf pour les bolus repas : pointe vers `Repas.id`.
    var repasAssocieId: UUID?

    /// Marque commerciale renseignée pour la lente (Lantus, Tresiba…) et
    /// éventuellement pour la rapide (NovoRapid, Humalog…).
    var nomMedicament: String?

    /// Libellé du repas associé (« Petit-déjeuner »…). Dénormalisation d'affichage.
    var labelRepas: String?

    /// Emoji du repas associé. Idem : dénormalisation pour l'affichage.
    var emojiRepas: String?

    /// Motif métier de l'injection. `nil` quand non renseigné (saisie ancienne
    /// ou ambiguë). Trigger de l'analyse B3 quand `.correction` au coucher.
    var motif: MotifInjection?

    /// Provenance de la saisie.
    var source: SourceDonnee = SourceDonnee.manuel

    init(
        id: UUID = UUID(),
        type: TypeInsuline,
        dose: Double,
        heure: Date,
        zoneInjection: ZoneInjection,
        coteInjection: CoteInjection,
        note: String? = nil,
        glycemieAuMoment: Double? = nil,
        repasAssocieId: UUID? = nil,
        nomMedicament: String? = nil,
        labelRepas: String? = nil,
        emojiRepas: String? = nil,
        motif: MotifInjection? = nil,
        source: SourceDonnee = .manuel
    ) {
        self.id = id
        self.type = type
        self.dose = dose
        self.heure = heure
        self.zoneInjection = zoneInjection
        self.coteInjection = coteInjection
        self.note = note
        self.glycemieAuMoment = glycemieAuMoment
        self.repasAssocieId = repasAssocieId
        self.nomMedicament = nomMedicament
        self.labelRepas = labelRepas
        self.emojiRepas = emojiRepas
        self.motif = motif
        self.source = source
    }
}

extension Injection {
    /// Site d'injection composé, formaté « Cuisse gauche ».
    var libelleSite: String {
        SiteInjection(zone: zoneInjection, cote: coteInjection).libelle
    }
}

// MARK: - Conformances rétro-ajoutées sur le modèle de site

// `ZoneInjection` et `CoteInjection` vivent dans `SiteInjectionPicker.swift`
// (ressources partagées avec la page Repas). On y ajoute Codable ici sans
// toucher au fichier source : il est synthétisé pour les `enum: String`.
nonisolated extension ZoneInjection: Codable {}
nonisolated extension CoteInjection: Codable {}
